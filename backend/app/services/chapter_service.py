"""
Tonztoon Komik — Chapter Service (Lazy Loading + Background Prefetch)

Flow lengkap saat user membuka chapter:
    1. Cek DB: apakah chapter sudah punya images?
       → Ya  : langsung return (cache hit)
       → Tidak: on-demand scrape dengan timeout ON_DEMAND_TIMEOUT
                → Berhasil : simpan ke DB → return
                → Timeout/gagal : raise ImageFetchError
                  sehingga API mengembalikan HTTP 503 ke user,
                  bukan mengembalikan data kosong tanpa pesan error.

    2. Setelah response dikirim ke user (background task):
       → Cek cooldown: apakah prefetch untuk komik ini sudah dipicu
         dalam PREFETCH_COOLDOWN_SECONDS terakhir?
         → Ya  : abaikan, prefetch sebelumnya masih berjalan
         → Tidak: catat timestamp, lanjutkan prefetch
       → Cari chapter dalam radius ±PREFETCH_WINDOW dari chapter yang dibuka
       → Filter: hanya yang images-nya masih NULL
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
    Contoh: user buka Ch 10 → prefetch Ch 5–9 dan Ch 11–15 (yang images=NULL)

Prefetch Cooldown:
    PREFETCH_COOLDOWN_SECONDS = 60
    Prefetch untuk komik yang sama tidak akan dipicu ulang dalam 60 detik.
"""

import asyncio
import logging
import random
import time

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models import Chapter, Comic

logger = logging.getLogger("service.chapter")

# ── Konfigurasi ──────────────────────────────────────────────────────────────
ON_DEMAND_TIMEOUT        = 10   # detik — batas waktu lazy load realtime
PREFETCH_TIMEOUT         = 20   # detik — batas waktu per chapter saat background prefetch
PREFETCH_WINDOW          = 5    # radius chapter kiri & kanan yang di-prefetch
PREFETCH_COOLDOWN_SECONDS = 60  # detik — jeda minimum antar-trigger prefetch per komik
CHAPTER_NUMBER_TOLERANCE = 0.0001

# Delay antar-request images saat prefetch (random untuk anti-bot detection)
PREFETCH_DELAY_MIN = 1.5
PREFETCH_DELAY_MAX = 3.0

# ── In-memory Cooldown Tracker ───────────────────────────────────────────────
# {comic_id: unix_timestamp_last_triggered}
# Mencegah prefetch berantai saat user membaca cepat lintas chapter.
_prefetch_cooldowns: dict[int, float] = {}


# ── Custom Exception ─────────────────────────────────────────────────────────

class ImageFetchError(Exception):
    """
    Dilempar ketika on-demand image fetching gagal (timeout / scraper error).
    Ditangkap di layer router untuk dikembalikan sebagai HTTP 503.
    """
    pass


# ── Factory Scraper ──────────────────────────────────────────────────────────

def _get_scraper_for_source(source_name: str):
    """
    Factory: return scraper instance berdasarkan source_name.
    Registry-based agar source baru tidak perlu di-hardcode di banyak tempat.
    """
    from scraper.sources.registry import create_scraper

    try:
        return create_scraper(source_name)
    except ValueError:
        return None


# ── Core Helper: Fetch & Save Images untuk 1 Chapter ────────────────────────

async def _fetch_and_save_images(
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

    try:
        images = await asyncio.wait_for(
            scraper.get_chapter_images(chapter.source_url),
            timeout=timeout_seconds,
        )

        if not images:
            logger.warning(
                f"Fetch Ch {chapter.chapter_number}: "
                f"tidak ada gambar di {chapter.source_url}"
            )
            return False

        images_json = [{"page": img["page"], "url": img["url"]} for img in images]

        await db.execute(
            update(Chapter)
            .where(Chapter.id == chapter.id)
            .values(images=images_json)
        )
        await db.commit()

        logger.info(
            f"✓ Images tersimpan: Ch {chapter.chapter_number} "
            f"→ {len(images_json)} gambar"
        )
        return True

    except asyncio.TimeoutError:
        logger.warning(
            f"⏱ Timeout ({timeout_seconds}s) saat fetch Ch {chapter.chapter_number}"
        )
        await db.rollback()
        return False

    except Exception as e:
        logger.error(f"✗ Error fetch Ch {chapter.chapter_number}: {e}")
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
        select(Comic).where(
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


async def _ensure_chapter_images_loaded(
    db: AsyncSession,
    chapter: Chapter,
    *,
    source_name: str | None = None,
) -> Chapter:
    """Pastikan chapter memiliki daftar gambar, fetch on-demand bila perlu."""
    if chapter.images:
        logger.debug(
            f"Cache hit: Chapter {chapter.id} "
            f"sudah punya {len(chapter.images)} images"
        )
        return chapter

    resolved_source_name = source_name
    if not resolved_source_name:
        comic_result = await db.execute(
            select(Comic.source_name).where(Comic.id == chapter.comic_id)
        )
        resolved_source_name = comic_result.scalar()

    if not resolved_source_name:
        raise ImageFetchError(
            f"Comic {chapter.comic_id} tidak ditemukan, "
            f"tidak bisa menentukan scraper."
        )

    logger.info(
        f"Lazy loading: Chapter {chapter.id} (Ch {chapter.chapter_number}) "
        f"belum punya images — on-demand scraping (timeout={ON_DEMAND_TIMEOUT}s)..."
    )

    ok = await _fetch_and_save_images(
        chapter=chapter,
        source_name=resolved_source_name,
        timeout_seconds=ON_DEMAND_TIMEOUT,
        db=db,
    )

    if not ok:
        raise ImageFetchError(
            f"Sumber komik tidak merespons dalam {ON_DEMAND_TIMEOUT} detik. "
            f"Silakan coba lagi beberapa saat."
        )

    await db.refresh(chapter)
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

    return await _ensure_chapter_images_loaded(db, chapter)


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
    if not chapter:
        raise LookupError(
            f"Chapter {chapter_number} untuk {source_name}/{comic_slug} tidak ditemukan"
        )
    return await _ensure_chapter_images_loaded(db, chapter, source_name=source_name)


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
    now = time.monotonic()
    last_triggered = _prefetch_cooldowns.get(comic_id, 0.0)
    elapsed_since_last = now - last_triggered

    if elapsed_since_last < PREFETCH_COOLDOWN_SECONDS:
        logger.debug(
            f"[Prefetch] Diabaikan — comic_id={comic_id} baru dipicu "
            f"{elapsed_since_last:.0f}s lalu (cooldown={PREFETCH_COOLDOWN_SECONDS}s). "
            f"Ch {current_chapter_number} tidak akan memicu prefetch baru."
        )
        return

    # Catat timestamp sebelum mulai agar request berikutnya langsung terkena cooldown
    _prefetch_cooldowns[comic_id] = now

    logger.info(
        f"[Prefetch] Mulai untuk Ch {current_chapter_number} "
        f"(comic_id={comic_id}, window=±{PREFETCH_WINDOW})"
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

            lower = current_chapter_number - PREFETCH_WINDOW
            upper = current_chapter_number + PREFETCH_WINDOW

            result = await db.execute(
                select(Chapter)
                .where(
                    Chapter.comic_id == comic_id,
                    Chapter.chapter_number >= lower,
                    Chapter.chapter_number <= upper,
                    Chapter.chapter_number != current_chapter_number,
                    Chapter.images.is_(None),
                )
                # Prioritaskan chapter yang paling dekat dengan yang sedang dibaca
                # (chapter berikutnya lebih penting dari chapter sebelumnya)
                .order_by(Chapter.chapter_number.desc())
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
                    ok = await _fetch_and_save_images(
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
