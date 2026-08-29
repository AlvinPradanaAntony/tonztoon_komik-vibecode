"""
Tonztoon Komik — Chapter Service (Lazy Loading + Background Prefetch)

Flow lengkap saat user membuka chapter:
    1. Cek DB: apakah chapter sudah punya images?
       → Ya  : langsung return (cache hit)
       → Tidak: on-demand scrape dengan timeout ON_DEMAND_TIMEOUT
                → Berhasil : simpan ke DB → return
                → Komiku Asia URL legacy/gagal: refresh listing metadata dari slug,
                  upsert URL chapter tanpa images, lalu retry sekali
                → Timeout/gagal setelah repair: raise ImageFetchError
                  sehingga API mengembalikan HTTP 503 ke user,
                  bukan mengembalikan data kosong tanpa pesan error.

    2. Setelah response dikirim ke user (background task):
       → Cek cooldown: apakah prefetch untuk komik ini sudah dipicu
         dalam PREFETCH_COOLDOWN_SECONDS terakhir?
         → Ya  : abaikan, prefetch sebelumnya masih berjalan
         → Tidak: catat timestamp, lanjutkan prefetch
       → Cari chapter dalam radius ±PREFETCH_WINDOW dari chapter yang dibuka
       → Filter: hanya chapter dengan images NULL / [] / invalid
       → Fetch & simpan images diam-diam, 1 per 1 dengan delay random

Catatan arsitektur — mencegah Thundering Herd:
    scraper/main.py sudah melakukan "pre-warm" images untuk N chapter terbaru
    setiap kali cron job berjalan. Artinya chapter terbaru (yang paling mungkin
    dibuka ramai-ramai setelah notifikasi rilis) sudah berisi images SEBELUM
    user datang → Cache Hit langsung → tidak ada lazy load → tidak ada race.

    Lazy loading di sini hanya menjadi FALLBACK untuk chapter-chapter lama
    dari hasil sync_full_library yang belum pernah dibuka user.

Pencegahan Prefetch Berantai (Prefetch Chaining):
    Jika user membaca cepat (Ch 10 → Ch 11 → Ch 12 dalam 3 detik), tanpa
    pencegahan akan ada 3 background task yang saling tumpang-tindih untuk
    komik yang sama, berpotensi scraping chapter yang sama secara paralel.

    Solusi: in-memory cooldown dict {comic_id: last_triggered_timestamp}.
    Background task baru untuk comic_id yang sama akan diabaikan jika
    task sebelumnya baru saja dipicu (< PREFETCH_COOLDOWN_SECONDS).

    Catatan: cooldown ini per-worker process. Pada deployment multi-worker,
    worst case adalah N_WORKERS task paralel (bukan tak terbatas). Karena
    data selalu disimpan idempoten (ON CONFLICT DO UPDATE), tidak ada
    masalah integritas data meskipun ada overlap kecil antar-worker.

Timeout Policy:
    ON_DEMAND_TIMEOUT = 10 detik  — user sedang menunggu, harus cepat
    PREFETCH_TIMEOUT  = 20 detik  — background, tidak ada yang menunggu

Prefetch Window:
    PREFETCH_WINDOW = 5
    Contoh: user buka Ch 10 → prefetch Ch 5–9 dan Ch 11–15 (yang images invalid)
    KOMIKU_ASIA_PREFETCH_WINDOW = 2
    Komiku Asia tetap memakai radius lebih konservatif, tetapi fetch dilakukan
    langsung oleh API-first scraper seperti source lainnya.

Prefetch Cooldown:
    PREFETCH_COOLDOWN_SECONDS = 60
    Prefetch untuk komik yang sama tidak akan dipicu ulang dalam 60 detik.
"""

import asyncio
import logging
import random
import time
from collections import OrderedDict
from urllib.parse import quote

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload

from app.config import settings
from app.database import async_session
from app.models import Chapter, Comic
from app.services.image_service import (
    chapter_image_has_dimensions,
    enrich_chapter_image_dimensions,
)

logger = logging.getLogger("service.chapter")

# ── Konfigurasi ──────────────────────────────────────────────────────────────
ON_DEMAND_TIMEOUT = 10   # detik — batas waktu lazy load realtime
KOMIKU_ASIA_METADATA_REFRESH_TIMEOUT = 10
PREFETCH_TIMEOUT = 20   # detik — batas waktu per chapter saat background prefetch
PREFETCH_WINDOW = 5    # radius chapter kiri & kanan yang di-prefetch
KOMIKU_ASIA_PREFETCH_WINDOW = 2  # radius khusus Komiku Asia agar biaya/traffic lazy tetap terkendali
PREFETCH_COOLDOWN_SECONDS = 60  # detik — jeda minimum antar-trigger prefetch per komik
PREFETCH_COOLDOWN_MAX_ENTRIES = 2_048  # batas entry cooldown per worker process
CHAPTER_NUMBER_TOLERANCE = 0.0001

# Delay antar-request images saat prefetch (random untuk anti-bot detection)
PREFETCH_DELAY_MIN = 1.5
PREFETCH_DELAY_MAX = 3.0

# ── In-memory Cooldown Tracker ───────────────────────────────────────────────
# {comic_id: monotonic_timestamp_last_triggered}
# Mencegah prefetch berantai saat user membaca cepat lintas chapter.
# OrderedDict menjaga eviction deterministik agar map tidak tumbuh monoton.
_prefetch_cooldowns: OrderedDict[int, float] = OrderedDict()

# Komiku Asia dapat memiliki banyak chapter lama dengan URL page legacy.
# Satu lock per komik mencegah beberapa reader melakukan refresh listing yang
# sama secara bersamaan ketika katalog lokal belum sempat diperbarui.
_komiku_asia_metadata_refresh_locks: dict[int, asyncio.Lock] = {}


# ── Custom Exception ─────────────────────────────────────────────────────────

class ImageFetchError(Exception):
    """
    Dilempar ketika on-demand image fetching gagal (timeout / scraper error).
    Ditangkap di layer router untuk dikembalikan sebagai HTTP 503.
    """
    pass


def _prune_prefetch_cooldowns(now: float | None = None) -> None:
    """Remove expired cooldown entries and keep the map bounded."""
    current_time = time.monotonic() if now is None else now
    expired_before = current_time - PREFETCH_COOLDOWN_SECONDS

    for comic_id, triggered_at in list(_prefetch_cooldowns.items()):
        if triggered_at > expired_before:
            continue
        _prefetch_cooldowns.pop(comic_id, None)

    while len(_prefetch_cooldowns) > PREFETCH_COOLDOWN_MAX_ENTRIES:
        _prefetch_cooldowns.popitem(last=False)


def _register_prefetch_cooldown(
    comic_id: int,
    *,
    now: float | None = None,
) -> tuple[bool, float]:
    """
    Return whether a prefetch may run and the elapsed time since last trigger.
    """
    current_time = time.monotonic() if now is None else now
    _prune_prefetch_cooldowns(current_time)

    last_triggered = _prefetch_cooldowns.get(comic_id)
    if last_triggered is not None:
        elapsed_since_last = current_time - last_triggered
        if elapsed_since_last < PREFETCH_COOLDOWN_SECONDS:
            _prefetch_cooldowns.move_to_end(comic_id)
            return False, elapsed_since_last
    else:
        elapsed_since_last = PREFETCH_COOLDOWN_SECONDS

    # Catat timestamp sebelum mulai agar request berikutnya langsung terkena cooldown.
    _prefetch_cooldowns[comic_id] = current_time
    _prefetch_cooldowns.move_to_end(comic_id)
    _prune_prefetch_cooldowns(current_time)
    return True, elapsed_since_last


def chapter_images_are_ready(images: list | None) -> bool:
    """
    Validasi ringan apakah payload images chapter sudah layak dipakai sebagai cache.

    Syarat minimum:
    - bertipe list
    - tidak kosong
    - setiap item berupa dict
    - setiap item punya `page` dan `url`
    - `url` berupa string non-kosong
    """
    if not isinstance(images, list) or not images:
        return False

    for item in images:
        if not isinstance(item, dict):
            return False
        if "page" not in item or "url" not in item:
            return False
        if not isinstance(item.get("url"), str) or not item["url"].strip():
            return False

    return True


def chapter_images_are_invalid_expression():
    """Indexed SQL expression: chapter images belum layak dipakai reader."""
    return Chapter.images_are_invalid.is_(True)


# ── Factory Scraper ──────────────────────────────────────────────────────────

def _get_scraper_for_source(source_name: str):
    """
    Factory: return scraper instance berdasarkan source_name.
    Registry-based agar source baru tidak perlu di-hardcode di banyak tempat.
    """
    if source_name == "komiku_asia":
        return _get_komiku_asia_live_scraper()

    from scraper.sources.registry import create_scraper

    try:
        return create_scraper(source_name)
    except ValueError:
        return None


def _get_komiku_asia_live_scraper():
    """
    Return the API-first Komiku Asia scraper for lazy/backfill images.

    The provider setting is retained for backwards-compatible configuration
    parsing, but ZenRows is no longer selected: the first-party `/api/v2`
    chapter endpoint exposes the page URLs directly and does not require DOM
    rendering.
    """
    provider = settings.KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER.strip().lower()
    if provider not in {"auto", "", "zenrows", "scrapling", "legacy", "stealth"}:
        raise ValueError(
            "KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER harus salah satu dari: "
            "auto, scrapling"
        )
    if provider == "zenrows":
        logger.warning(
            "Provider ZenRows Komiku Asia sudah deprecated; gunakan API-first scraper."
        )

    from scraper.sources.registry import create_scraper

    return create_scraper("komiku_asia")


# ── Core Helper: Fetch & Save Images untuk 1 Chapter ────────────────────────

async def fetch_and_save_chapter_images(
    chapter: Chapter,
    source_name: str,
    timeout_seconds: float,
    db: AsyncSession,
) -> bool:
    """
    Fetch images dari sumber untuk satu chapter, lalu simpan ke DB.

    Args:
        chapter         : Chapter ORM object
        source_name     : e.g. "komiku"
        timeout_seconds : Batas waktu maksimal scraping
        db              : Database session yang aktif

    Returns:
        True jika berhasil, False jika timeout atau tidak ada images.

    Raises:
        ImageFetchError : jika terjadi error yang bukan TimeoutError
                          (dipakai oleh on-demand flow untuk trigger HTTP 503)
    """
    scraper = _get_scraper_for_source(source_name)
    if not scraper:
        raise ImageFetchError(f"Tidak ada scraper untuk source: {source_name}")

    # Keep the database transaction short.  Callers normally queried the
    # chapter immediately before entering this helper, which implicitly
    # starts a transaction in SQLAlchemy.  The scraper and image-dimension
    # enrichment are external I/O and can take seconds, so do not keep that
    # transaction/connection checked out while waiting for them.
    chapter_id = chapter.id
    chapter_number = chapter.chapter_number
    chapter_source_url = chapter.source_url
    await db.rollback()

    try:
        images = await asyncio.wait_for(
            scraper.get_chapter_images(chapter_source_url),
            timeout=timeout_seconds,
        )

        if not images:
            logger.warning(
                f"Fetch Ch {chapter_number}: "
                f"tidak ada gambar di {chapter_source_url}"
            )
            return False

        images_json = await enrich_chapter_image_dimensions(images)

        await db.execute(
            update(Chapter)
            .where(Chapter.id == chapter_id)
            .values(images=images_json)
        )
        await db.commit()

        logger.info(
            f"✅ Images tersimpan: Ch {chapter_number} "
            f"➡️  {len(images_json)} gambar"
        )
        return True

    except asyncio.TimeoutError:
        logger.warning(
            f"⏳ Timeout ({timeout_seconds}s) saat fetch Ch {chapter_number}"
        )
        await db.rollback()
        return False

    except Exception as e:
        logger.error(f"❌ Error fetch Ch {chapter_number}: {e}")
        await db.rollback()
        raise ImageFetchError(str(e)) from e


# ── On-Demand Lazy Load ──────────────────────────────────────────────────────

async def get_comic_by_source_and_slug(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
) -> Comic | None:
    """Ambil comic berdasarkan source publik dan slug."""
    result = await db.execute(
        select(Comic)
        .options(noload(Comic.genres), noload(Comic.chapters))
        .where(
            Comic.source_name == source_name,
            Comic.slug == comic_slug,
        )
    )
    return result.scalars().first()


async def get_chapter_by_source_slug_and_number(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> Chapter | None:
    """Ambil chapter berdasarkan identitas publik source/comic/chapter."""
    lower_bound = chapter_number - CHAPTER_NUMBER_TOLERANCE
    upper_bound = chapter_number + CHAPTER_NUMBER_TOLERANCE

    result = await db.execute(
        select(Chapter)
        .join(Comic, Comic.id == Chapter.comic_id)
        .where(
            Comic.source_name == source_name,
            Comic.slug == comic_slug,
            Chapter.chapter_number >= lower_bound,
            Chapter.chapter_number <= upper_bound,
        )
    )
    return result.scalars().first()


async def _refresh_komiku_asia_chapter_metadata(
    db: AsyncSession,
    *,
    comic_id: int,
    comic_slug: str,
    comic_title: str | None = None,
    chapter: Chapter | None = None,
) -> bool:
    """
    Refresh listing chapter Komiku Asia secara lazy dan metadata-only.

    Ini dipakai sebagai repair path untuk record lama yang masih menyimpan URL
    chapter legacy. ``get_comic_detail`` mengambil detail dan seluruh listing
    chapter dari API resmi, sedangkan upsert metadata tidak menyentuh kolom
    ``images``. Setelah commit, caller dapat mengulang fetch images hanya untuk
    chapter yang sedang diminta.
    """
    from scraper.db_ops import upsert_chapter_metadata_many
    from scraper.sources.komiku_asia_api import KOMIKU_ASIA_BASE_URL

    refresh_lock = _komiku_asia_metadata_refresh_locks.setdefault(
        comic_id,
        asyncio.Lock(),
    )

    async with refresh_lock:
        # Jika request lain dalam process yang sama sudah memperbaiki row ini,
        # tidak perlu mengulang request detail/listing ke source.
        if chapter is not None:
            try:
                await db.refresh(chapter)
            except Exception as exc:
                await db.rollback()
                logger.warning(
                    "Komiku Asia: gagal membaca ulang row chapter %s: %s",
                    chapter.id,
                    exc,
                )
                return False
            if "/read/id/" in (chapter.source_url or "").lower():
                return True

        detail_url = (
            f"{KOMIKU_ASIA_BASE_URL}/manga/{quote(comic_slug, safe='')}"
        )
        logger.warning(
            "Komiku Asia: refresh listing chapter metadata dari slug %s "
            "(tanpa pages/images).",
            comic_slug,
        )

        try:
            # Metadata refresh is also external I/O.  End the read transaction
            # created by the caller before waiting for Komiku Asia.
            await db.rollback()
            scraper = _get_komiku_asia_live_scraper()
            comic_detail = await asyncio.wait_for(
                scraper.get_comic_detail(
                    detail_url,
                    search_title=comic_title,
                ),
                timeout=KOMIKU_ASIA_METADATA_REFRESH_TIMEOUT,
            )
            chapters = comic_detail.get("chapters") if isinstance(comic_detail, dict) else None
            valid_chapters = [
                {
                    "chapter_number": chapter_data["chapter_number"],
                    "title": chapter_data.get("title"),
                    "source_url": chapter_data["source_url"],
                    "release_date": chapter_data.get("release_date"),
                }
                for chapter_data in chapters or []
                if isinstance(chapter_data, dict)
                and chapter_data.get("chapter_number") is not None
                and chapter_data.get("source_url")
            ]
            if not valid_chapters:
                logger.warning(
                    "Komiku Asia: listing chapter kosong/tidak valid untuk slug %s.",
                    comic_slug,
                )
                await db.rollback()
                return False

            saved_count = await upsert_chapter_metadata_many(
                db,
                comic_id,
                valid_chapters,
            )
            await db.commit()
            logger.info(
                "Komiku Asia: %s metadata chapter diperbarui untuk %s.",
                saved_count,
                comic_slug,
            )
            return saved_count > 0
        except Exception as exc:
            await db.rollback()
            logger.warning(
                "Komiku Asia: refresh listing chapter gagal untuk %s: %s",
                comic_slug,
                exc,
            )
            return False


async def _ensure_chapter_images_loaded(
    db: AsyncSession,
    chapter: Chapter,
    *,
    source_name: str | None = None,
    comic_slug: str | None = None,
) -> Chapter:
    """Pastikan chapter memiliki daftar gambar, fetch on-demand bila perlu."""
    if chapter_images_are_ready(chapter.images):
        logger.debug(
            f"Cache hit: Chapter {chapter.id} "
            f"sudah punya {len(chapter.images)} images"
        )
        return chapter

    resolved_source_name = source_name
    resolved_comic_slug = comic_slug
    resolved_comic_id = chapter.comic_id
    resolved_comic_title: str | None = None
    if (
        not resolved_source_name
        or not resolved_comic_slug
        or resolved_source_name == "komiku_asia"
    ):
        comic_result = await db.execute(
            select(Comic.source_name, Comic.slug, Comic.title).where(
                Comic.id == resolved_comic_id
            )
        )
        comic_row = comic_result.one_or_none()
        if comic_row:
            resolved_source_name = resolved_source_name or comic_row.source_name
            resolved_comic_slug = resolved_comic_slug or comic_row.slug
            resolved_comic_title = comic_row.title

    if not resolved_source_name:
        raise ImageFetchError(
            f"Comic {chapter.comic_id} tidak ditemukan, "
            f"tidak bisa menentukan scraper."
        )

    # fetch_and_save_chapter_images melakukan rollback saat fetch gagal.
    # Rollback dapat expire atribut ORM, sehingga identitas ini harus dicache
    # sebelum fallback mengakses session/database kembali.
    resolved_chapter_id = chapter.id
    resolved_chapter_number = chapter.chapter_number

    logger.info(
        f"Lazy loading: Chapter {resolved_chapter_id} (Ch {resolved_chapter_number}) "
        f"belum punya images — on-demand scraping (timeout={ON_DEMAND_TIMEOUT}s)..."
    )

    metadata_repair_available = (
        resolved_source_name == "komiku_asia" and bool(resolved_comic_slug)
    )
    metadata_repair_attempted = False
    while True:
        try:
            ok = await fetch_and_save_chapter_images(
                chapter=chapter,
                source_name=resolved_source_name,
                timeout_seconds=ON_DEMAND_TIMEOUT,
                db=db,
            )
        except ImageFetchError:
            if not metadata_repair_available or metadata_repair_attempted:
                raise
            metadata_repair_attempted = True
            repaired = await _refresh_komiku_asia_chapter_metadata(
                db,
                comic_id=resolved_comic_id,
                comic_slug=resolved_comic_slug,
                comic_title=resolved_comic_title,
                chapter=chapter,
            )
            if repaired:
                await db.refresh(chapter)
                continue
            raise

        if ok:
            break

        # Timeout/empty payload dikembalikan sebagai False oleh helper fetch.
        # Untuk Komiku Asia, lakukan satu kali repair metadata sebelum
        # mengembalikan 503 agar URL legacy tidak memblokir reader selamanya.
        if metadata_repair_available and not metadata_repair_attempted:
            metadata_repair_attempted = True
            repaired = await _refresh_komiku_asia_chapter_metadata(
                db,
                comic_id=resolved_comic_id,
                comic_slug=resolved_comic_slug,
                comic_title=resolved_comic_title,
                chapter=chapter,
            )
            if repaired:
                await db.refresh(chapter)
                continue
        break

    if not ok:
        raise ImageFetchError(
            f"Sumber {resolved_source_name} tidak mengembalikan images untuk "
            f"chapter {resolved_chapter_number} setelah fetch on-demand. "
            f"Silakan coba lagi beberapa saat."
        )

    await db.refresh(chapter)
    return chapter


async def _ensure_chapter_image_dimensions(
    db: AsyncSession,
    chapter: Chapter,
) -> Chapter:
    """Lengkapi metadata dimensi record lama sebelum payload reader dikirim."""
    images = chapter.images or []
    if not images or all(chapter_image_has_dimensions(image) for image in images):
        return chapter

    # Preserve the payload and primary key before ending the ORM transaction;
    # rollback may expire attributes on the attached Chapter instance.
    chapter_id = chapter.id
    images = list(images)
    await db.rollback()
    enriched_images = await enrich_chapter_image_dimensions(images)
    if enriched_images == images:
        # The rollback above may expire the ORM attribute.  Keep the original
        # payload available for the response when probing was unsuccessful.
        chapter.images = images
        return chapter

    await db.execute(
        update(Chapter)
        .where(Chapter.id == chapter_id)
        .values(images=enriched_images)
    )
    await db.commit()
    chapter.images = enriched_images
    return chapter


async def get_chapter_with_images(
    db: AsyncSession,
    chapter_id: int,
) -> Chapter:
    """
    Ambil chapter dari DB. Jika images masih NULL, lakukan on-demand scraping
    dengan batas waktu ON_DEMAND_TIMEOUT detik.

    Args:
        db         : Database session
        chapter_id : ID chapter

    Returns:
        Chapter object dengan images terisi.

    Raises:
        LookupError     : chapter tidak ditemukan di DB (→ HTTP 404)
        ImageFetchError : scraping gagal/timeout (→ HTTP 503)
    """
    # 1. Ambil chapter dari DB
    result = await db.execute(
        select(Chapter).where(Chapter.id == chapter_id)
    )
    chapter = result.scalars().first()

    if not chapter:
        raise LookupError(f"Chapter {chapter_id} tidak ditemukan")

    chapter = await _ensure_chapter_images_loaded(db, chapter)
    return await _ensure_chapter_image_dimensions(db, chapter)


async def get_chapter_with_images_by_identity(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> Chapter:
    """
    Ambil chapter dari identitas publik source/comic/chapter.

    Jika images masih kosong, lakukan lazy load on-demand.
    """
    chapter = await get_chapter_by_source_slug_and_number(
        db,
        source_name,
        comic_slug,
        chapter_number,
    )
    if not chapter and source_name == "komiku_asia":
        comic = await get_comic_by_source_and_slug(db, source_name, comic_slug)
        if comic:
            repaired = await _refresh_komiku_asia_chapter_metadata(
                db,
                comic_id=comic.id,
                comic_slug=comic_slug,
                comic_title=comic.title,
            )
            if repaired:
                chapter = await get_chapter_by_source_slug_and_number(
                    db,
                    source_name,
                    comic_slug,
                    chapter_number,
                )
    if not chapter:
        raise LookupError(
            f"Chapter {chapter_number} untuk {source_name}/{comic_slug} tidak ditemukan"
        )
    chapter = await _ensure_chapter_images_loaded(
        db,
        chapter,
        source_name=source_name,
        comic_slug=comic_slug,
    )
    return await _ensure_chapter_image_dimensions(db, chapter)


async def get_chapter_images_only(
    db: AsyncSession,
    chapter_id: int,
) -> dict:
    """
    Ambil hanya images dari chapter.
    Jika kosong, lazy load terlebih dahulu.

    Returns:
        {"chapter_id": int, "images": list, "total": int}

    Raises:
        LookupError     : chapter tidak ada (→ HTTP 404)
        ImageFetchError : scraping gagal (→ HTTP 503)
    """
    chapter = await get_chapter_with_images(db, chapter_id)
    images = chapter.images or []

    return {
        "chapter_id": chapter_id,
        "images": images,
        "total": len(images),
    }


async def get_chapter_images_only_by_identity(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> dict:
    """
    Ambil hanya images untuk chapter berdasarkan identitas publik.
    """
    chapter = await get_chapter_with_images_by_identity(
        db,
        source_name,
        comic_slug,
        chapter_number,
    )
    images = chapter.images or []

    return {
        "source_name": source_name,
        "comic_slug": comic_slug,
        "chapter_number": chapter.chapter_number,
        "images": images,
        "total": len(images),
    }


# ── Background Prefetch ──────────────────────────────────────────────────────

async def prefetch_nearby_chapters(
    chapter_id: int,
    comic_id: int,
    current_chapter_number: float,
) -> None:
    """
    Background task: fetch images untuk chapter-chapter di sekitar chapter
    yang sedang dibuka user, dalam radius ±PREFETCH_WINDOW.

    Contoh (PREFETCH_WINDOW=5, user buka Ch 10):
        Target : Ch 5–9 dan Ch 11–15
        Skip   : Ch 10 (sudah di-handle on-demand)
        Skip   : Chapter yang images-nya sudah ada
        Skip   : Jika prefetch untuk comic_id ini baru saja dipicu
                 (< PREFETCH_COOLDOWN_SECONDS) → mencegah prefetch berantai

    Menggunakan session DB sendiri karena berjalan setelah response dikirim.

    Args:
        chapter_id             : ID chapter yang diminta (untuk log)
        comic_id               : ID komik untuk query chapter sekitarnya
        current_chapter_number : Nomor chapter yang sedang dibuka
    """
    # ── Cek Cooldown (Pencegahan Prefetch Berantai) ───────────────────────────
    should_prefetch, elapsed_since_last = _register_prefetch_cooldown(comic_id)

    if not should_prefetch:
        logger.debug(
            f"[Prefetch] Diabaikan — comic_id={comic_id} baru dipicu "
            f"{elapsed_since_last:.0f}s lalu (cooldown={PREFETCH_COOLDOWN_SECONDS}s). "
            f"Ch {current_chapter_number} tidak akan memicu prefetch baru."
        )
        return

    logger.info(
        f"[Prefetch] Mulai untuk Ch {current_chapter_number} "
        f"(comic_id={comic_id})"
    )

    async with async_session() as db:
        try:
            comic_result = await db.execute(
                select(Comic.source_name).where(Comic.id == comic_id)
            )
            source_name = comic_result.scalar()

            if not source_name:
                logger.warning(f"[Prefetch] Comic {comic_id} tidak ditemukan, batal.")
                return

            prefetch_window = (
                KOMIKU_ASIA_PREFETCH_WINDOW
                if source_name == "komiku_asia"
                else PREFETCH_WINDOW
            )
            logger.info(
                "[Prefetch] Source %s memakai radius ±%s; fetch langsung via scraper.",
                source_name,
                prefetch_window,
            )
            lower = current_chapter_number - prefetch_window
            upper = current_chapter_number + prefetch_window

            result = await db.execute(
                select(Chapter)
                .where(
                    Chapter.comic_id == comic_id,
                    Chapter.chapter_number >= lower,
                    Chapter.chapter_number <= upper,
                    Chapter.chapter_number != current_chapter_number,
                    chapter_images_are_invalid_expression(),
                )
                # Prioritaskan chapter terdekat; jika jaraknya sama, chapter
                # berikutnya lebih penting untuk flow baca maju.
                .order_by(
                    func.abs(Chapter.chapter_number - current_chapter_number).asc(),
                    Chapter.chapter_number.desc(),
                )
            )
            nearby = result.scalars().all()

            if not nearby:
                logger.info(
                    f"[Prefetch] Tidak ada chapter yang perlu di-prefetch "
                    f"di window Ch {lower:.0f}–{upper:.0f}"
                )
                return

            logger.info(
                f"[Prefetch] {len(nearby)} chapter tanpa images "
                f"di window Ch {lower:.0f}–{upper:.0f}: "
                f"{[ch.chapter_number for ch in nearby]}"
            )

            success = 0
            for ch in nearby:
                logger.info(f"[Prefetch] Fetching Ch {ch.chapter_number} (id={ch.id})...")
                try:
                    ok = await fetch_and_save_chapter_images(
                        chapter=ch,
                        source_name=source_name,
                        timeout_seconds=PREFETCH_TIMEOUT,
                        db=db,
                    )
                    if ok:
                        success += 1
                except ImageFetchError as e:
                    logger.warning(f"[Prefetch] Ch {ch.chapter_number} gagal: {e}")
                finally:
                    # Delay random antar-request SELALU jalan (sukses maupun gagal)
                    await asyncio.sleep(
                        random.uniform(PREFETCH_DELAY_MIN, PREFETCH_DELAY_MAX)
                    )

            logger.info(
                f"[Prefetch] Selesai: {success}/{len(nearby)} berhasil "
                f"(comic_id={comic_id})"
            )

        except Exception as e:
            logger.error(f"[Prefetch] Error tidak terduga: {e}")
