"""
Tonztoon Komik — Scraper Entry Point (One-off Script)

File ini adalah entry point utama yang dijalankan oleh:
1. GitHub Actions Cron Job (terjadwal)
2. GitHub Actions workflow_dispatch (manual sync via API)

Usage:
    python -m scraper.main  # Log default: logs/main.log
    python -m scraper.main --source komiku_asia
    python -m scraper.main --log-file cron.log
    python -m scraper.main --max-pages 5
    python -m scraper.main --popular-pages 3
    python -m scraper.main --popular-pages 5 --popular-no-early-stop
    python -m scraper.main --max-pages 0 --popular-pages 3

Argumen CLI utama:
- `--source <source_name>`
  - Filter satu source saja.
  - Nilai valid mengikuti registry backend: `komiku`, `komiku_asia`,
    `komikcast`, `shinigami`.
  - Jika tidak diisi, script memproses semua source aktif.
- `--max-pages <N>`
  - Jumlah halaman latest yang dipindai untuk incremental sync.
  - `0` berarti latest dimatikan.
  - Default mengikuti `MAX_LATEST_PAGES`.
- `--popular-pages <N>`
  - Jumlah halaman popular yang dipindai.
  - `0` berarti popular dimatikan.
  - Default mengikuti `DEFAULT_POPULAR_PAGES`.
- `--popular-no-early-stop`
  - Nonaktifkan early-stop untuk popular feed.
  - Cocok saat onboarding source baru atau saat ingin menyapu ranking lebih
    dalam tanpa berhenti walau page awal hanya berisi comic lama.
- `--log-file <path>`
  - Ubah lokasi file log. Jika relatif, file akan ditulis ke `backend/logs/`.

Contoh use case:
- Cron harian ringan satu source:
  `python -m scraper.main --source komiku_asia --max-pages 5`
- Refresh popular lintas source:
  `python -m scraper.main --max-pages 0 --popular-pages 5`
- Sweep popular lebih dalam tanpa early-stop:
  `python -m scraper.main --source komikcast --popular-pages 8 --popular-no-early-stop`
- Run semua source aktif dengan log terpisah:
  `python -m scraper.main --log-file latest_sync.log`

Panduan pemakaian singkat:
- Gunakan script ini untuk sync incremental / operasional rutin.
- Gunakan `sync_full_library.py` untuk seeding katalog besar atau validasi
  range halaman direktori.
- Gunakan `sync_chapter_images.py` untuk backlog images chapter, bukan script ini.

Flow:
    1. Inisialisasi koneksi database (async)
    2. Ambil listing chapter terbaru dari canonical source Komiku
       (`api.komiku.org/manga`) secara bertahap per-page
    3. Validasi setiap item listing terhadap data di database
       untuk menentukan apakah komik/chapter terbaru sudah known atau belum
    4. Fetch detail HANYA untuk komik baru / komik dengan chapter terbaru baru
    5. Validasi data via Pydantic schemas
    6. Upsert comic ke PostgreSQL
       + simpan marker posisi item di canonical latest/popular feed
    7. Simpan metadata SEMUA chapter (agar katalog selalu lengkap & update)
    8. Fetch images HANYA untuk MAX_CHAPTERS_PER_COMIC chapter terbaru
    9. Opsional: sinkronisasi marker popular dari canonical popular feed
   10. Early-stop jika satu halaman penuh tidak menghasilkan kandidat baru
   11. Tutup koneksi dan exit

Strategi "Pre-warm Cache" (Hybrid):
    - Metadata (nomor, judul, url, tanggal) disimpan untuk SEMUA chapter
      sehingga daftar chapter di halaman detail komik selalu up-to-date.
    - Images hanya di-fetch untuk N chapter TERBARU per komik.
      Tujuannya agar chapter yang baru rilis sudah siap sebelum user datang
      (mencegah Thundering Herd), tanpa membebani server dengan ribuan request
      untuk chapter-chapter lama yang mungkin tidak pernah dibaca.
    - Chapter lama yang images-nya masih NULL akan ditangani oleh
      Lazy Loading di API saat ada user yang benar-benar membacanya.

Anti-Blocking:
    - Semua delay menggunakan random.uniform (bukan fixed) agar pola request
      tidak terdeteksi sebagai bot.
    - Delay SELALU dijalankan bahkan saat error, mencegah burst request
      yang terjadi ketika error berturut-turut (kemungkinan tanda rate limit).
    - Ada jeda sebelum fetch detail pertama dan antar-komik.
"""

import asyncio
from dataclasses import dataclass
import logging
import random
import re
import sys
import time
from pathlib import Path
from typing import Any

from sqlalchemy import delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Comic, Chapter, Genre, comic_genre
from app.schemas import ComicCreate

from scraper.base_scraper import BaseComicScraper
from scraper.sources.registry import (
    create_default_scrapers,
    create_scraper,
    get_supported_source_names,
)
from scraper.time_utils import now_wib

# Setup logging
DEFAULT_LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
DEFAULT_LOG_FILE = Path("main.log")


def resolve_log_path(log_file: str | None) -> Path:
    """Resolve path log ke folder backend/logs kecuali path absolut."""
    log_path = Path(log_file or DEFAULT_LOG_FILE).expanduser()
    if not log_path.is_absolute():
        log_path = DEFAULT_LOG_DIR / log_path
    return log_path


def configure_logging(log_file: str | None = None) -> None:
    """Konfigurasi logger root ke stdout dan file UTF-8 di backend/logs."""
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]

    log_path = resolve_log_path(log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handlers.append(logging.FileHandler(log_path, mode="w", encoding="utf-8"))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=handlers,
        force=True,
    )


configure_logging()
logger = logging.getLogger("scraper")

# ── Konfigurasi ───────────────────────────────────────────────────────────────

# Jumlah chapter terbaru per komik yang di-fetch images-nya oleh cron job.
# Chapter di luar batas ini dibiarkan images=NULL dan ditangani lazy load.
MAX_CHAPTERS_PER_COMIC = 3

# Mode incremental sync untuk cron:
# - Scan beberapa halaman latest canonical source
# - Stop lebih cepat jika satu halaman penuh sudah known/tidak berubah
MAX_LATEST_PAGES = 10
# Popular berubah lebih lambat daripada latest, jadi default cron utama tidak
# perlu memprosesnya. Jalankan eksplisit via `--popular-pages N` saat dibutuhkan.
DEFAULT_POPULAR_PAGES = 0
STOP_AFTER_UNCHANGED_PAGES = 3

# Delay antar-request (detik) — random untuk menghindari deteksi bot
DELAY_DETAIL_MIN  = 1.5   # jeda sebelum fetch halaman detail komik
DELAY_DETAIL_MAX  = 3.5
DELAY_CHAPTER_MIN = 2.0   # jeda antar-fetch images chapter
DELAY_CHAPTER_MAX = 4.0
DELAY_COMIC_MIN   = 3.0   # jeda antar-komik (setelah semua chapter selesai)
DELAY_COMIC_MAX   = 6.0

# Cooldown berkala untuk menghindari pola burst request
COOLDOWN_EVERY_N_COMICS = 10
COOLDOWN_MIN = 10.0
COOLDOWN_MAX = 20.0

# Exponential backoff saat terjadi error berturut-turut / kemungkinan rate limit
BACKOFF_BASE = 2.0
BACKOFF_MAX = 60.0
MAX_CONSECUTIVE_ERRORS = 3


# ── Utility ───────────────────────────────────────────────────────────────────

async def random_delay(min_sec: float, max_sec: float, label: str = "") -> None:
    """Jeda acak antara min_sec dan max_sec detik."""
    delay = random.uniform(min_sec, max_sec)
    if label:
        logger.info(f"  ⏳ {label}: menunggu {delay:.1f}s...")
    await asyncio.sleep(delay)


async def backoff_delay(attempt: int, label: str = "") -> None:
    """Exponential backoff dengan jitter kecil agar request tidak kaku."""
    delay = min(BACKOFF_BASE * (2 ** attempt), BACKOFF_MAX)
    jitter = delay * random.uniform(-0.25, 0.25)
    delay = max(1.0, delay + jitter)
    logger.warning(f"  ⏳ Backoff (attempt {attempt + 1}): {label} — menunggu {delay:.1f}s...")
    await asyncio.sleep(delay)


def _format_elapsed_duration(elapsed_seconds: float) -> str:
    """Format durasi menjadi bentuk natural + total detik."""
    total_seconds = max(0, int(elapsed_seconds))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    parts: list[str] = []
    if hours:
        parts.append(f"{hours} jam")
    if minutes:
        parts.append(f"{minutes} menit")
    if seconds or not parts:
        parts.append(f"{seconds} detik")

    return f"{' '.join(parts)} ({total_seconds} detik)"


@dataclass
class ScrapeStats:
    """Statistik runtime untuk sinkronisasi one-off."""

    total_pages_scanned: int = 0
    total_listing_items: int = 0
    total_candidates: int = 0
    total_unchanged_listing: int = 0
    total_comics: int = 0
    total_chapters_meta: int = 0
    total_chapters_images: int = 0
    total_errors: int = 0
    total_skipped: int = 0
    comics_since_cooldown: int = 0


# ── Database Helpers ──────────────────────────────────────────────────────────

async def upsert_genre(session, genre_name: str) -> int:
    """Insert genre jika belum ada, return genre id."""
    slug = genre_name.lower().replace(" ", "-")
    stmt = pg_insert(Genre).values(name=genre_name, slug=slug)
    stmt = stmt.on_conflict_do_nothing(index_elements=["slug"])
    await session.execute(stmt)
    await session.flush()

    result = await session.execute(
        select(Genre.id).where(Genre.slug == slug)
    )
    return result.scalar_one()


async def sync_comic_genres(session, comic_id: int, genre_names: list[str]) -> None:
    """
    Sinkronkan relasi genre komik secara penuh.

    - Tambahkan genre baru yang belum terhubung.
    - Hapus relasi genre lama yang sudah tidak ada di source detail.
    """
    target_genre_ids: list[int] = []
    seen_genre_ids: set[int] = set()

    for genre_name in genre_names:
        genre_id = await upsert_genre(session, genre_name)
        if genre_id in seen_genre_ids:
            continue
        seen_genre_ids.add(genre_id)
        target_genre_ids.append(genre_id)

    current_ids_result = await session.execute(
        select(comic_genre.c.genre_id).where(comic_genre.c.comic_id == comic_id)
    )
    current_genre_ids = set(current_ids_result.scalars().all())
    target_genre_ids_set = set(target_genre_ids)

    stale_genre_ids = current_genre_ids - target_genre_ids_set
    if stale_genre_ids:
        await session.execute(
            delete(comic_genre).where(
                comic_genre.c.comic_id == comic_id,
                comic_genre.c.genre_id.in_(stale_genre_ids),
            )
        )

    missing_genre_ids = target_genre_ids_set - current_genre_ids
    for genre_id in missing_genre_ids:
        genre_link = pg_insert(comic_genre).values(
            comic_id=comic_id,
            genre_id=genre_id,
        )
        genre_link = genre_link.on_conflict_do_nothing()
        await session.execute(genre_link)


async def upsert_comic(session, validated: ComicCreate) -> int:
    """
    Upsert comic ke database tanpa mengubah marker urutan feed apa pun.

    Helper ini dipakai oleh alur lain yang hanya ingin menyimpan metadata
    comic. Untuk cron feed-based (`/latest` dan `/popular`), gunakan helper
    yang menerima marker feed agar urutan endpoint ikut diperbarui.
    """
    return await upsert_comic_with_feed_markers(
        session,
        validated,
        latest_feed_batch_at=None,
        latest_feed_page=None,
        latest_feed_position=None,
        popular_feed_batch_at=None,
        popular_feed_page=None,
        popular_feed_position=None,
    )


async def upsert_comic_with_feed_markers(
    session,
    validated: ComicCreate,
    *,
    latest_feed_batch_at,
    latest_feed_page: int | None,
    latest_feed_position: int | None,
    popular_feed_batch_at,
    popular_feed_page: int | None,
    popular_feed_position: int | None,
) -> int:
    """
    Upsert comic ke database dengan metadata posisi canonical feed opsional.

    `updated_at` tetap di-update sebagai jejak teknis perubahan row, tetapi
    urutan business-level untuk endpoint `/latest` dan `/popular` disimpan
    terpisah di marker `latest_feed_*` dan `popular_feed_*`.
    """
    current_time = now_wib()
    stmt = pg_insert(Comic).values(
        title=validated.title,
        slug=validated.slug,
        alternative_titles=validated.alternative_titles,
        cover_image_url=validated.cover_image_url,
        author=validated.author,
        artist=validated.artist,
        status=validated.status,
        type=validated.type,
        synopsis=validated.synopsis,
        rating=validated.rating,
        total_view=validated.total_view,
        source_url=validated.source_url,
        source_name=validated.source_name,
        created_at=current_time,
        updated_at=current_time,
        latest_feed_batch_at=latest_feed_batch_at,
        latest_feed_page=latest_feed_page,
        latest_feed_position=latest_feed_position,
        popular_feed_batch_at=popular_feed_batch_at,
        popular_feed_page=popular_feed_page,
        popular_feed_position=popular_feed_position,
    )
    update_values = {
        "title": validated.title,
        "alternative_titles": validated.alternative_titles,
        "cover_image_url": validated.cover_image_url,
        "author": validated.author,
        "artist": validated.artist,
        "status": validated.status,
        "synopsis": validated.synopsis,
        "type": validated.type,
        "rating": validated.rating,
        "total_view": validated.total_view,
        "source_url": validated.source_url,
        "updated_at": current_time,
    }
    if latest_feed_batch_at is not None:
        update_values["latest_feed_batch_at"] = latest_feed_batch_at
        update_values["latest_feed_page"] = latest_feed_page
        update_values["latest_feed_position"] = latest_feed_position
    if popular_feed_batch_at is not None:
        update_values["popular_feed_batch_at"] = popular_feed_batch_at
        update_values["popular_feed_page"] = popular_feed_page
        update_values["popular_feed_position"] = popular_feed_position

    stmt = stmt.on_conflict_do_update(
        constraint="uq_source_slug",
        set_=update_values,
    )
    await session.execute(stmt)
    await session.flush()

    result = await session.execute(
        select(Comic.id).where(
            Comic.slug == validated.slug,
            Comic.source_name == validated.source_name
        )
    )
    return result.scalar_one()


async def mark_comic_seen_in_latest_feed(
    session,
    *,
    comic_id: int,
    latest_feed_batch_at,
    latest_feed_page: int,
    latest_feed_position: int,
) -> None:
    """
    Simpan posisi comic saat terlihat di canonical latest feed.

    Fungsi ini dipakai juga untuk item yang dianggap `unchanged`, karena comic
    tersebut tetap muncul di feed terbaru meskipun kita tidak perlu fetch
    detail ulang. Dengan begitu urutan `/latest` tetap mengikuti source.
    """
    await session.execute(
        update(Comic)
        .where(Comic.id == comic_id)
        .values(
            latest_feed_batch_at=latest_feed_batch_at,
            latest_feed_page=latest_feed_page,
            latest_feed_position=latest_feed_position,
        )
    )


async def mark_comic_seen_in_popular_feed(
    session,
    *,
    comic_id: int,
    popular_feed_batch_at,
    popular_feed_page: int,
    popular_feed_position: int,
) -> None:
    """
    Simpan posisi comic saat terlihat di canonical popular feed.

    Bahkan jika comic tidak perlu di-fetch ulang, ranking canonical source
    tetap perlu disalin ke DB agar endpoint `/popular` mengikuti source of
    truth dan tidak fallback ke `rating`.
    """
    await session.execute(
        update(Comic)
        .where(Comic.id == comic_id)
        .values(
            popular_feed_batch_at=popular_feed_batch_at,
            popular_feed_page=popular_feed_page,
            popular_feed_position=popular_feed_position,
        )
    )


async def upsert_chapter_metadata(session, comic_id: int, ch_data: dict) -> None:
    """Upsert metadata chapter ke database (tanpa images)."""
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
        created_at=now_wib(),
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={
            "title": ch_data.get("title"),
            "source_url": ch_data["source_url"],
            "release_date": ch_data.get("release_date"),
        },
    )
    await session.execute(stmt)


async def upsert_chapter_images(session, comic_id: int, ch_data: dict, images: list[dict]) -> None:
    """Update kolom images chapter yang sudah ada di database."""
    images_json = [{"page": img["page"], "url": img["url"]} for img in images]
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
        images=images_json,
        created_at=now_wib(),
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={"images": images_json},
    )
    await session.execute(stmt)


async def fetch_latest_comics_with_retry(scraper: BaseComicScraper, page: int = 1) -> list[dict[str, Any]]:
    """
    Ambil listing latest update dari canonical source dengan retry + backoff.

    Catatan:
    - Data listing ini dipakai sebagai sinyal awal update terbaru.
    - Listing TIDAK langsung di-upsert ke DB.
    - Setiap item listing akan divalidasi dulu terhadap DB sebelum detail fetch.
    """
    comics_list: list[dict[str, Any]] = []
    for attempt in range(3):
        try:
            comics_list = await scraper.get_latest_updates(page=page)
            if comics_list:
                break

            logger.warning(
                f"  ⚠️ Listing {scraper.SOURCE_NAME} page {page} kosong "
                f"(attempt {attempt + 1}/3)."
            )
            if attempt < 2:
                await backoff_delay(attempt, f"retry empty listing {scraper.SOURCE_NAME}")
                continue
            break
        except Exception as e:
            logger.error(
                f"  ✗ Gagal fetch listing {scraper.SOURCE_NAME} page {page} "
                f"(attempt {attempt + 1}): {e}"
            )
            await backoff_delay(attempt, f"retry listing {scraper.SOURCE_NAME}")
    return comics_list


async def fetch_popular_comics_with_retry(scraper: BaseComicScraper, page: int = 1) -> list[dict[str, Any]]:
    """
    Ambil listing popular dari canonical source dengan retry + backoff.

    Data listing ini dipakai sebagai source of truth ranking `/popular`.
    Listing tidak langsung di-upsert; comic baru tetap divalidasi/fetch detail
    sebelum disimpan.
    """
    comics_list: list[dict[str, Any]] = []
    for attempt in range(3):
        try:
            comics_list = await scraper.get_popular(page=page)
            if comics_list:
                break

            logger.warning(
                f"  ⚠️ Popular listing {scraper.SOURCE_NAME} page {page} kosong "
                f"(attempt {attempt + 1}/3)."
            )
            if attempt < 2:
                await backoff_delay(attempt, f"retry empty popular {scraper.SOURCE_NAME}")
                continue
            break
        except Exception as e:
            logger.error(
                f"  ✗ Gagal fetch popular {scraper.SOURCE_NAME} page {page} "
                f"(attempt {attempt + 1}): {e}"
            )
            await backoff_delay(attempt, f"retry popular {scraper.SOURCE_NAME}")
    return comics_list


async def get_existing_comic_id(
    session,
    *,
    scraper: BaseComicScraper,
    comic_basic: dict[str, Any],
) -> int | None:
    """Cari comic id existing dari slug/source_name, fallback ke source_url."""
    slug = comic_basic.get("slug")
    source_url = comic_basic.get("source_url")

    if slug:
        result = await session.execute(
            select(Comic.id).where(
                Comic.slug == slug,
                Comic.source_name == scraper.SOURCE_NAME,
            )
        )
        comic_id = result.scalar_one_or_none()
        if comic_id is not None:
            return comic_id

    if source_url:
        result = await session.execute(
            select(Comic.id).where(
                Comic.source_url == source_url,
                Comic.source_name == scraper.SOURCE_NAME,
            )
        )
        return result.scalar_one_or_none()

    return None


async def should_process_comic_update(
    session,
    *,
    scraper: BaseComicScraper,
    comic_basic: dict[str, Any],
) -> tuple[bool, str, int | None]:
    """
    Tentukan apakah item latest listing perlu diproses lebih lanjut.

    Rules:
    - comic belum ada di DB → proses
    - latest_chapter_url valid dan belum ada di chapter DB → proses
    - jika listing hanya punya nomor chapter, bandingkan dengan chapter DB tertinggi
    - jika sinyal listing tidak cukup andal → proses (safe fallback)
    - selain itu → skip sebagai unchanged

    Intinya, validasi di sini adalah gate sebelum fetch detail:
    hanya kandidat yang kemungkinan benar-benar berubah yang akan masuk
    ke `process_comic()`.

    Return:
    - should_process: apakah detail comic perlu di-fetch
    - reason: alasan untuk log/debug
    - comic_id: id comic existing jika sudah ada di DB, agar caller tetap
      bisa memperbarui marker `latest_feed_*` walau item di-skip
    """
    detail_url = comic_basic.get("source_url", "")
    if not detail_url:
        return False, "no detail url", None

    comic_id = await get_existing_comic_id(session, scraper=scraper, comic_basic=comic_basic)
    if comic_id is None:
        return True, "comic baru", None

    latest_chapter_url = comic_basic.get("latest_chapter_url")
    latest_chapter_number = _extract_listing_chapter_number(scraper, comic_basic)

    if latest_chapter_url and latest_chapter_url != detail_url:
        result = await session.execute(
            select(Chapter.id).where(
                Chapter.comic_id == comic_id,
                Chapter.source_url == latest_chapter_url,
            )
        )
        chapter_id = result.scalar_one_or_none()
        if chapter_id is None:
            return True, "Latest chapter baru (berdasarkan URL)", comic_id
        return False, "Latest chapter sudah ada (berdasarkan URL)", comic_id

    if latest_chapter_number > 0:
        result = await session.execute(
            select(func.max(Chapter.chapter_number)).where(Chapter.comic_id == comic_id)
        )
        db_latest_chapter_number = result.scalar_one_or_none() or 0.0
        if db_latest_chapter_number + 0.0001 < latest_chapter_number:
            return True, "Latest chapter baru (berdasarkan nomor)", comic_id
        return False, "Latest chapter sudah ada (berdasarkan nomor)", comic_id

    return True, "listing tidak punya sinyal update yang andal", comic_id


def _extract_listing_chapter_number(
    scraper: BaseComicScraper,
    comic_basic: dict[str, Any],
) -> float:
    """Ambil nomor chapter dari payload listing, fallback ke parsing teks."""
    latest_chapter_number = comic_basic.get("latest_chapter_number")
    if isinstance(latest_chapter_number, int | float):
        return float(latest_chapter_number)

    latest_chapter_text = comic_basic.get("latest_chapter")
    if not latest_chapter_text:
        return 0.0

    parse_chapter_number = getattr(scraper, "_parse_chapter_number", None)
    if callable(parse_chapter_number):
        parsed_number = parse_chapter_number(latest_chapter_text)
        if isinstance(parsed_number, int | float):
            return float(parsed_number)

    match = re.search(
        r"(?:chapter|chap|ch)\.?\s*([0-9]+(?:[.\-][0-9]+)?)|\b([0-9]+(?:[.\-][0-9]+)?)\b",
        str(latest_chapter_text),
        re.IGNORECASE,
    )
    if not match:
        return 0.0

    raw_number = match.group(1) or match.group(2)
    try:
        return float(raw_number.replace("-", "."))
    except ValueError:
        return 0.0


async def prewarm_latest_chapters(
    session,
    scraper: BaseComicScraper,
    *,
    comic_id: int,
    validated: ComicCreate,
    chapters_sorted: list[dict[str, Any]],
    stats: ScrapeStats,
) -> tuple[int, int]:
    """Pre-warm images untuk chapter terbaru, metadata sisanya tetap lengkap."""
    chapters_to_warm = chapters_sorted[:MAX_CHAPTERS_PER_COMIC]
    chapters_rest = chapters_sorted[MAX_CHAPTERS_PER_COMIC:]
    ch_images_count = 0

    logger.info(
        f"  🔥 Pre-warming {len(chapters_to_warm)} chapter terbaru "
        f"(dari total {len(chapters_sorted)}) untuk {validated.title}..."
    )

    for ch_data in chapters_to_warm:
        ch_url = ch_data.get("source_url", "")
        if not ch_url:
            continue

        existing = await session.execute(
            select(Chapter.id, Chapter.images).where(
                Chapter.comic_id == comic_id,
                Chapter.chapter_number == ch_data["chapter_number"],
            )
        )
        row = existing.first()
        if row and row.images:
            logger.info(
                f"    ⏭️ Ch {ch_data['chapter_number']} sudah punya images, skip."
            )
            stats.total_skipped += 1
            continue

        try:
            images = await scraper.get_chapter_images(ch_url)

            if images:
                await upsert_chapter_images(session, comic_id, ch_data, images)
                ch_images_count += 1
                stats.total_chapters_images += 1
                logger.info(
                    f"    ✅ Ch {ch_data['chapter_number']}: {len(images)} images"
                )
            else:
                stats.total_errors += 1
                logger.warning(
                    f"    ⚠️ Ch {ch_data['chapter_number']}: tidak ada images ditemukan"
                )

        except Exception as e:
            stats.total_errors += 1
            logger.error(
                f"    ✗ Gagal fetch images Ch {ch_data.get('chapter_number')}: {e}"
            )
        finally:
            await random_delay(
                DELAY_CHAPTER_MIN,
                DELAY_CHAPTER_MAX,
                f"post-chapter {ch_data.get('chapter_number')}",
            )

    return ch_images_count, len(chapters_rest)


async def process_comic(
    session,
    scraper: BaseComicScraper,
    comic_basic: dict[str, Any],
    stats: ScrapeStats,
    *,
    latest_feed_batch_at,
    latest_feed_page: int,
    latest_feed_position: int,
    popular_feed_batch_at,
    popular_feed_page: int | None,
    popular_feed_position: int | None,
) -> None:
    """
    Proses satu komik penuh: detail, upsert, metadata chapter, lalu pre-warm.

    Karena fungsi ini dipanggil dari incremental feed sync, upsert comic juga
    ikut memperbarui marker `latest_feed_*` dan/atau `popular_feed_*` supaya
    endpoint feed-based merepresentasikan urutan canonical source.
    """
    detail_url = comic_basic.get("source_url", "")
    title = comic_basic.get("title", "???")

    if not detail_url:
        stats.total_skipped += 1
        logger.warning(f"  ⏭️ Skip (no URL): {title}")
        return

    await random_delay(DELAY_DETAIL_MIN, DELAY_DETAIL_MAX, f"pre-detail {title}")

    logger.info(f"  📖 Mengambil detail: {title}")
    comic_detail = await scraper.get_comic_detail(detail_url)

    if not comic_detail.get("title"):
        stats.total_errors += 1
        logger.warning(f"  ⚠️ Tidak ada title di detail, skip: {detail_url}")
        return

    validated = ComicCreate(
        title=comic_detail["title"],
        slug=comic_detail["slug"],
        alternative_titles=comic_detail.get("alternative_titles"),
        cover_image_url=comic_detail.get("cover_image_url"),
        author=comic_detail.get("author"),
        artist=comic_detail.get("artist"),
        status=comic_detail.get("status"),
        type=comic_detail.get("type"),
        synopsis=comic_detail.get("synopsis"),
        rating=comic_detail.get("rating"),
        total_view=comic_detail.get("total_view"),
        source_url=comic_detail["source_url"],
        source_name=comic_detail["source_name"],
        genres=comic_detail.get("genres", []),
    )

    comic_id = await upsert_comic_with_feed_markers(
        session,
        validated,
        latest_feed_batch_at=latest_feed_batch_at,
        latest_feed_page=latest_feed_page,
        latest_feed_position=latest_feed_position,
        popular_feed_batch_at=popular_feed_batch_at,
        popular_feed_page=popular_feed_page,
        popular_feed_position=popular_feed_position,
    )
    stats.total_comics += 1
    stats.comics_since_cooldown += 1

    await sync_comic_genres(session, comic_id, validated.genres)

    chapters_data = comic_detail.get("chapters", [])
    chapters_sorted = sorted(
        chapters_data,
        key=lambda c: c.get("chapter_number", 0),
        reverse=True,
    )

    for ch_data in chapters_sorted:
        if not ch_data.get("source_url"):
            continue
        await upsert_chapter_metadata(session, comic_id, ch_data)
        stats.total_chapters_meta += 1

    await session.flush()

    ch_images_count, chapters_rest_count = await prewarm_latest_chapters(
        session,
        scraper,
        comic_id=comic_id,
        validated=validated,
        chapters_sorted=chapters_sorted,
        stats=stats,
    )

    logger.info(
        f"  ✅ Done: {validated.title} — "
        f"{len(chapters_sorted)} chapters metadata, "
        f"{ch_images_count} images pre-warmed, "
        f"{chapters_rest_count} chapter lama → lazy load"
    )

    await session.commit()

    if stats.comics_since_cooldown >= COOLDOWN_EVERY_N_COMICS:
        stats.comics_since_cooldown = 0
        logger.info(
            f" 🧊 Cooldown berkala ({COOLDOWN_EVERY_N_COMICS} komik tercapai)..."
        )
        await random_delay(COOLDOWN_MIN, COOLDOWN_MAX, "cooldown berkala")

    await random_delay(DELAY_COMIC_MIN, DELAY_COMIC_MAX, "antar-komik")


async def process_latest_pages(
    session,
    *,
    scraper: BaseComicScraper,
    stats: ScrapeStats,
    max_pages: int,
    latest_feed_batch_at,
) -> None:
    """
    Scan beberapa halaman latest updates secara incremental.

    Strategy:
    - fetch listing terbaru per-page dari canonical source
    - validasi kandidat update terhadap DB
    - fetch detail hanya untuk comic baru / comic dengan latest chapter baru
    - upsert + prewarm dijalankan hanya untuk kandidat yang lolos validasi
    - item unchanged tetap ditandai posisi feed-nya agar endpoint `/latest`
      tidak bergantung pada `updated_at`
    - early-stop jika halaman penuh tidak menghasilkan kandidat baru
    """
    consecutive_errors = 0
    unchanged_pages = 0

    for page in range(1, max_pages + 1):
        logger.info(f"{'─' * 60}")
        logger.info(f"📄 Halaman {page}/{max_pages}")
        logger.info(f"{'─' * 60}")

        comics_list = await fetch_latest_comics_with_retry(scraper, page=page)
        if not comics_list:
            logger.warning(f"  ⚠️ Listing page {page} kosong, stop scan lebih awal.")
            break

        stats.total_pages_scanned += 1
        stats.total_listing_items += len(comics_list)
        logger.info(f"  📋 Page {page}: {len(comics_list)} komik dari listing canonical source")

        page_candidates = 0
        page_unchanged = 0

        for position, comic_basic in enumerate(comics_list, start=1):
            title = comic_basic.get("title", "???")

            should_process, reason, comic_id = await should_process_comic_update(
                session,
                scraper=scraper,
                comic_basic=comic_basic,
            )
            if not should_process:
                if reason == "no detail url":
                    stats.total_skipped += 1
                    logger.warning(f"  ⏭️ Skip invalid listing: {title} ({reason})")
                else:
                    if comic_id is not None:
                        await mark_comic_seen_in_latest_feed(
                            session,
                            comic_id=comic_id,
                            latest_feed_batch_at=latest_feed_batch_at,
                            latest_feed_page=page,
                            latest_feed_position=position,
                        )
                        await session.commit()
                    page_unchanged += 1
                    stats.total_unchanged_listing += 1
                    logger.info(f"  ⏭️ Skip unchanged: {title} ({reason})")
                continue

            page_candidates += 1
            stats.total_candidates += 1
            logger.info(f"  🆕 Kandidat update: {title} ({reason})")

            try:
                await process_comic(
                    session,
                    scraper,
                    comic_basic,
                    stats,
                    latest_feed_batch_at=latest_feed_batch_at,
                    latest_feed_page=page,
                    latest_feed_position=position,
                    popular_feed_batch_at=None,
                    popular_feed_page=None,
                    popular_feed_position=None,
                )
                consecutive_errors = 0

            except Exception as e:
                consecutive_errors += 1
                stats.total_errors += 1
                logger.error(
                    f"  ✗ Error processing comic "
                    f"[{consecutive_errors}/{MAX_CONSECUTIVE_ERRORS}]: {e}"
                )
                await session.rollback()

                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                    logger.error(
                        f"  ⛔ {MAX_CONSECUTIVE_ERRORS} error berturut-turut! "
                        f"Stop scraper {scraper.SOURCE_NAME} lebih awal."
                    )
                    return

                await backoff_delay(
                    consecutive_errors,
                    f"error comic pada scraper {scraper.SOURCE_NAME}",
                )
                await random_delay(
                    DELAY_COMIC_MIN,
                    DELAY_COMIC_MAX,
                    "antar-komik (after error)",
                )

        logger.info(
            f"  📄 Ringkasan page {page}: "
            f"{page_candidates} kandidat, {page_unchanged} unchanged"
        )

        if page_candidates == 0:
            unchanged_pages += 1
            logger.info(
                f"  🛑 Page {page} tidak menghasilkan kandidat update baru "
                f"({unchanged_pages}/{STOP_AFTER_UNCHANGED_PAGES} unchanged pages)"
            )
            if unchanged_pages >= STOP_AFTER_UNCHANGED_PAGES:
                logger.info("  🧠 Early stop: halaman berikutnya diperkirakan berisi update yang lebih lama.")
                break
        else:
            unchanged_pages = 0


async def process_popular_pages(
    session,
    *,
    scraper: BaseComicScraper,
    stats: ScrapeStats,
    max_pages: int,
    popular_feed_batch_at,
    allow_early_stop: bool = True,
) -> None:
    """
    Scan beberapa halaman popular secara incremental.

    Strategy:
    - fetch ranking popular per-page dari canonical source
    - comic existing cukup ditandai marker `popular_feed_*`
    - detail hanya di-fetch untuk comic yang belum ada di DB
    - early-stop jika satu halaman penuh tidak menghasilkan comic baru
      kecuali mode popular no-early-stop diaktifkan
    """
    consecutive_errors = 0
    unchanged_pages = 0

    for page in range(1, max_pages + 1):
        logger.info(f"{'─' * 60}")
        logger.info(f"🔥 Popular Halaman {page}/{max_pages}")
        logger.info(f"{'─' * 60}")

        comics_list = await fetch_popular_comics_with_retry(scraper, page=page)
        if not comics_list:
            logger.warning(f"  ⚠️ Popular page {page} kosong, stop scan lebih awal.")
            break

        stats.total_pages_scanned += 1
        stats.total_listing_items += len(comics_list)
        logger.info(f"  📋 Popular page {page}: {len(comics_list)} komik dari ranking canonical source")

        page_candidates = 0
        page_unchanged = 0

        for position, comic_basic in enumerate(comics_list, start=1):
            title = comic_basic.get("title", "???")
            comic_id = await get_existing_comic_id(
                session,
                scraper=scraper,
                comic_basic=comic_basic,
            )

            if comic_id is not None:
                await mark_comic_seen_in_popular_feed(
                    session,
                    comic_id=comic_id,
                    popular_feed_batch_at=popular_feed_batch_at,
                    popular_feed_page=page,
                    popular_feed_position=position,
                )
                await session.commit()
                page_unchanged += 1
                stats.total_unchanged_listing += 1
                logger.info(f"  ⏭️ Mark popular: {title} (sudah ada di DB)")
                continue

            page_candidates += 1
            stats.total_candidates += 1
            logger.info(f"  🆕 Kandidat popular baru: {title} (comic baru di ranking)")

            try:
                await process_comic(
                    session,
                    scraper,
                    comic_basic,
                    stats,
                    latest_feed_batch_at=None,
                    latest_feed_page=None,
                    latest_feed_position=None,
                    popular_feed_batch_at=popular_feed_batch_at,
                    popular_feed_page=page,
                    popular_feed_position=position,
                )
                consecutive_errors = 0
            except Exception as e:
                consecutive_errors += 1
                stats.total_errors += 1
                logger.error(
                    f"  ✗ Error processing popular comic "
                    f"[{consecutive_errors}/{MAX_CONSECUTIVE_ERRORS}]: {e}"
                )
                await session.rollback()

                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                    logger.error(
                        f"  ⛔ {MAX_CONSECUTIVE_ERRORS} error berturut-turut! "
                        f"Stop popular scraper {scraper.SOURCE_NAME} lebih awal."
                    )
                    return

                await backoff_delay(
                    consecutive_errors,
                    f"error popular comic pada scraper {scraper.SOURCE_NAME}",
                )
                await random_delay(
                    DELAY_COMIC_MIN,
                    DELAY_COMIC_MAX,
                    "antar-komik popular (after error)",
                )

        logger.info(
            f"  🔥 Ringkasan popular page {page}: "
            f"{page_candidates} kandidat baru, {page_unchanged} existing ditandai"
        )

        if page_candidates == 0:
            unchanged_pages += 1
            logger.info(
                f"  🛑 Popular page {page} tidak menghasilkan comic baru "
                f"({unchanged_pages}/{STOP_AFTER_UNCHANGED_PAGES} unchanged pages)"
            )
            if allow_early_stop and unchanged_pages >= STOP_AFTER_UNCHANGED_PAGES:
                logger.info("  🧠 Early stop popular: halaman berikutnya diperkirakan ranking lama.")
                break
        else:
            unchanged_pages = 0


# ── Main Pipeline ─────────────────────────────────────────────────────────────

async def run_scraper(
    max_pages: int = MAX_LATEST_PAGES,
    popular_pages: int = DEFAULT_POPULAR_PAGES,
    source_name: str | None = None,
    popular_allow_early_stop: bool = True,
):
    """
    Main scraping pipeline untuk cron updater incremental.

    Default cron path memprioritaskan `/latest` agar job tetap cepat.
    Sinkronisasi `/popular` bersifat opsional dan hanya dijalankan bila
    `popular_pages > 0`.
    """
    if max_pages <= 0 and popular_pages <= 0:
        logger.warning("Tidak ada feed yang diaktifkan. Gunakan --max-pages > 0 dan/atau --popular-pages > 0.")
        return

    start_time = time.time()
    started_at = now_wib()
    latest_feed_batch_at = started_at
    popular_feed_batch_at = started_at
    logger.info("═" * 60)
    logger.info(f"🚀 One-off Scraper dimulai — {started_at.isoformat()}")
    if max_pages > 0:
        logger.info(
            f"   Target        : latest updates canonical source page 1..{max_pages} "
            f"(early stop after {STOP_AFTER_UNCHANGED_PAGES} unchanged page)"
        )
    else:
        logger.info("   Target        : latest disabled")
    if popular_pages > 0:
        if popular_allow_early_stop:
            logger.info(
                f"   Popular target: canonical popular source page 1..{popular_pages} "
                f"(early stop after {STOP_AFTER_UNCHANGED_PAGES} unchanged page)"
            )
        else:
            logger.info(
                f"   Popular target: canonical popular source page 1..{popular_pages} "
                "(early stop disabled)"
            )
    else:
        logger.info("   Popular target: disabled")
    logger.info(f"   Delay detail  : {DELAY_DETAIL_MIN}-{DELAY_DETAIL_MAX}s (random)")
    logger.info(f"   Delay chapter : {DELAY_CHAPTER_MIN}-{DELAY_CHAPTER_MAX}s (random)")
    logger.info(f"   Delay comic   : {DELAY_COMIC_MIN}-{DELAY_COMIC_MAX}s (random)")
    logger.info(f"   Cooldown      : setiap {COOLDOWN_EVERY_N_COMICS} komik")
    logger.info(f"   Backoff max   : {BACKOFF_MAX:.0f}s")
    logger.info(f"   Source filter : {source_name or 'all active sources'}")
    logger.info("═" * 60)

    scrapers = [create_scraper(source_name)] if source_name else create_default_scrapers()

    stats = ScrapeStats()

    async with async_session() as session:
        for scraper in scrapers:
            logger.info(f"🕷️ Scraper: {scraper.SOURCE_NAME} ({scraper.BASE_URL})")

            scraper_start_comics = stats.total_comics
            scraper_start_meta = stats.total_chapters_meta
            scraper_start_images = stats.total_chapters_images
            scraper_start_pages = stats.total_pages_scanned
            scraper_start_listing = stats.total_listing_items
            scraper_start_candidates = stats.total_candidates
            scraper_start_unchanged = stats.total_unchanged_listing
            scraper_start_skipped = stats.total_skipped
            scraper_start_errors = stats.total_errors
            try:
                if max_pages > 0:
                    await process_latest_pages(
                        session,
                        scraper=scraper,
                        stats=stats,
                        max_pages=max_pages,
                        latest_feed_batch_at=latest_feed_batch_at,
                    )
                if popular_pages > 0:
                    await process_popular_pages(
                        session,
                        scraper=scraper,
                        stats=stats,
                        max_pages=popular_pages,
                        popular_feed_batch_at=popular_feed_batch_at,
                        allow_early_stop=popular_allow_early_stop,
                    )

                logger.info(
                    f"  ✅ Selesai scraper {scraper.SOURCE_NAME}: "
                    f"{stats.total_pages_scanned - scraper_start_pages} pages, "
                    f"{stats.total_listing_items - scraper_start_listing} listing items, "
                    f"{stats.total_candidates - scraper_start_candidates} candidates, "
                    f"{stats.total_unchanged_listing - scraper_start_unchanged} unchanged, "
                    f"{stats.total_comics - scraper_start_comics} comics, "
                    f"{stats.total_chapters_meta - scraper_start_meta} chapter metadata, "
                    f"{stats.total_chapters_images - scraper_start_images} chapter images pre-warmed, "
                    f"{stats.total_skipped - scraper_start_skipped} skipped, "
                    f"{stats.total_errors - scraper_start_errors} errors"
                )

            except Exception as e:
                stats.total_errors += 1
                logger.error(f"  ✗ Scraper {scraper.SOURCE_NAME} failed: {e}")
                await session.rollback()
                continue
            finally:
                try:
                    await scraper.close()
                except Exception as close_error:
                    logger.warning(
                        f"  ⚠️ Gagal menutup resource scraper {scraper.SOURCE_NAME}: {close_error}"
                    )

    elapsed = time.time() - start_time
    finished_at = now_wib()
    logger.info("═" * 60)
    logger.info("🏁 One-off Scraper selesai!")
    logger.info(f"   Mulai       : {started_at.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"   Selesai     : {finished_at.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"   Waktu       : {_format_elapsed_duration(elapsed)}")
    logger.info(f"   Pages       : {stats.total_pages_scanned}")
    logger.info(f"   Listing     : {stats.total_listing_items}")
    logger.info(f"   Candidates  : {stats.total_candidates}")
    logger.info(f"   Unchanged   : {stats.total_unchanged_listing}")
    logger.info(f"   Comics      : {stats.total_comics}")
    logger.info(f"   Chapter meta: {stats.total_chapters_meta}")
    logger.info(f"   Pre-warmed  : {stats.total_chapters_images} chapter images")
    logger.info(f"   Skipped     : {stats.total_skipped}")
    logger.info(f"   Errors      : {stats.total_errors}")
    logger.info("═" * 60)


def parse_args() -> dict[str, str | int | bool]:
    """Parse argumen command-line sederhana untuk logging dan scan depth."""
    args = {
        "log_file": str(DEFAULT_LOG_FILE),
        "max_pages": MAX_LATEST_PAGES,
        "popular_pages": DEFAULT_POPULAR_PAGES,
        "popular_allow_early_stop": True,
        "source": "",
    }
    supported_sources = get_supported_source_names()

    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--log-file" and i + 1 < len(argv):
            args["log_file"] = argv[i + 1]
            i += 1
        elif argv[i] == "--source" and i + 1 < len(argv):
            args["source"] = argv[i + 1].lower()
            i += 1
        elif argv[i] == "--max-pages" and i + 1 < len(argv):
            try:
                args["max_pages"] = max(0, int(argv[i + 1]))
            except ValueError as e:
                raise ValueError("--max-pages harus berupa integer >= 0") from e
            i += 1
        elif argv[i] == "--popular-pages" and i + 1 < len(argv):
            try:
                args["popular_pages"] = max(0, int(argv[i + 1]))
            except ValueError as e:
                raise ValueError("--popular-pages harus berupa integer >= 0") from e
            i += 1
        elif argv[i] == "--popular-no-early-stop":
            args["popular_allow_early_stop"] = False
        elif argv[i] == "--help":
            print(__doc__)
            sys.exit(0)
        i += 1

    if "--log-file" in argv and not args["log_file"]:
        raise ValueError("--log-file membutuhkan path file (ex: --log-file sync.log)")
    if args["source"] and args["source"] not in supported_sources:
        raise ValueError(
            f"--source harus salah satu dari: {', '.join(supported_sources)}"
        )

    return args


def main():
    """Entry point synchronous wrapper."""
    try:
        args = parse_args()
    except ValueError as e:
        print(f"Error argumen: {e}")
        sys.exit(1)

    configure_logging(str(args["log_file"]))
    asyncio.run(
        run_scraper(
            max_pages=int(args["max_pages"]),
            popular_pages=int(args["popular_pages"]),
            source_name=str(args["source"]) or None,
            popular_allow_early_stop=bool(args["popular_allow_early_stop"]),
        )
    )


if __name__ == "__main__":
    main()
