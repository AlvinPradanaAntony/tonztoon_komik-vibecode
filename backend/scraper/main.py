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
import re
import sys
import time
from pathlib import Path
from typing import Any

from sqlalchemy import func, select

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Comic, Chapter
from app.schemas import ComicCreate

from scraper.base_scraper import BaseComicScraper
from scraper.db_ops import (
    mark_comic_seen_in_latest_feed,
    mark_comic_seen_in_popular_feed,
    sync_comic_genres,
    upsert_chapter_images,
    upsert_chapter_metadata,
    upsert_comic_with_feed_markers,
)
from scraper.sources.registry import (
    create_default_scrapers,
    create_scraper,
    get_supported_source_names,
)
from scraper.time_utils import now_wib
from scraper.utils import (
    CliLiveProgress,
    RealtimeConsoleHandler,
    backoff_delay,
    configure_external_loggers,
    configure_logging as _configure_logging_base,
    format_elapsed_duration,
    random_delay,
    resolve_log_path,
)

# Setup logging
DEFAULT_LOG_FILE = Path("main.log")


def configure_logging(log_file: str | None = None) -> None:
    """Konfigurasi logger `main.py` agar konsisten dengan sync_full_library."""
    _configure_logging_base(
        log_file,
        default_filename=str(DEFAULT_LOG_FILE),
        stdout_handler=RealtimeConsoleHandler(sys.stdout),
    )
    configure_external_loggers()


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
# random_delay, backoff_delay, format_elapsed_duration telah dipindahkan
# ke scraper.utils untuk menghindari duplikasi lintas CLI scripts.


async def _backoff_delay(attempt: int, label: str) -> None:
    """Gunakan profil backoff legacy milik scraper incremental ini."""
    await backoff_delay(
        attempt,
        label,
        base=BACKOFF_BASE,
        maximum=BACKOFF_MAX,
    )


def _comic_progress_label(comic_position: int, page_total: int) -> str:
    """Label posisi komik di halaman aktif."""
    return f"[{comic_position}/{page_total}]"


async def _stop_progress(progress: CliLiveProgress | None) -> None:
    """Stop progress jika ada, aman dipanggil berulang."""
    if progress is not None:
        await progress.stop()


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
# Semua DB operations (upsert_comic, upsert_genre, sync_comic_genres,
# upsert_chapter_metadata, upsert_chapter_images, mark_comic_seen_*)
# telah diekstrak ke scraper.db_ops untuk SoC dan menghindari
# cross-import antar CLI scripts.


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
                await _backoff_delay(attempt, f"retry empty listing {scraper.SOURCE_NAME}")
                continue
            break
        except Exception as e:
            logger.error(
                f"  ✗ Gagal fetch listing {scraper.SOURCE_NAME} page {page} "
                f"(attempt {attempt + 1}): {e}"
            )
            await _backoff_delay(attempt, f"retry listing {scraper.SOURCE_NAME}")
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
                await _backoff_delay(attempt, f"retry empty popular {scraper.SOURCE_NAME}")
                continue
            break
        except Exception as e:
            logger.error(
                f"  ✗ Gagal fetch popular {scraper.SOURCE_NAME} page {page} "
                f"(attempt {attempt + 1}): {e}"
            )
            await _backoff_delay(attempt, f"retry popular {scraper.SOURCE_NAME}")
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
    comic_position: int,
    page_total: int,
) -> tuple[int, int]:
    """Pre-warm images untuk chapter terbaru, metadata sisanya tetap lengkap."""
    comic_label = _comic_progress_label(comic_position, page_total)
    chapters_to_warm = chapters_sorted[:MAX_CHAPTERS_PER_COMIC]
    chapters_rest = chapters_sorted[MAX_CHAPTERS_PER_COMIC:]
    ch_images_count = 0
    image_progress: CliLiveProgress | None = None

    logger.info(
        f"  🔥 {comic_label} Pre-warming {len(chapters_to_warm)} chapter terbaru "
        f"(dari total {len(chapters_sorted)}) untuk {validated.title}..."
    )

    if chapters_to_warm:
        image_progress = CliLiveProgress(
            label=f"{comic_label} prewarm chapter",
            total_steps=len(chapters_to_warm),
        )
        image_progress.start()
        image_progress.set_detail(
            f"menyiapkan {len(chapters_to_warm)} chapter terbaru"
        )

    for ch_data in chapters_to_warm:
        ch_url = ch_data.get("source_url", "")
        if not ch_url:
            if image_progress is not None:
                image_progress.advance(
                    f"skip ch {ch_data.get('chapter_number', '?')}: tidak ada source_url"
                )
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
                f"    ⏭️ {comic_label} Ch {ch_data['chapter_number']} sudah punya images, skip."
            )
            stats.total_skipped += 1
            if image_progress is not None:
                image_progress.advance(
                    f"ch {ch_data['chapter_number']}: sudah punya images"
                )
            continue

        try:
            if image_progress is not None:
                image_progress.set_detail(
                    f"fetch images ch {ch_data.get('chapter_number', '?')}"
                )
            images = await scraper.get_chapter_images(ch_url)

            if images:
                await upsert_chapter_images(session, comic_id, ch_data, images)
                ch_images_count += 1
                stats.total_chapters_images += 1
                logger.info(
                    f"    ✅ {comic_label} Ch {ch_data['chapter_number']}: {len(images)} images"
                )
                if image_progress is not None:
                    image_progress.advance(
                        f"ch {ch_data['chapter_number']}: {len(images)} images"
                    )
            else:
                stats.total_errors += 1
                logger.warning(
                    f"    ⚠️ {comic_label} Ch {ch_data['chapter_number']}: tidak ada images ditemukan"
                )
                if image_progress is not None:
                    image_progress.advance(
                        f"ch {ch_data['chapter_number']}: tidak ada images"
                    )

        except Exception as e:
            stats.total_errors += 1
            logger.error(
                f"    ✗ {comic_label} Gagal fetch images Ch {ch_data.get('chapter_number')}: {e}"
            )
            if image_progress is not None:
                image_progress.advance(
                    f"ch {ch_data.get('chapter_number', '?')}: error fetch images"
                )
        finally:
            await random_delay(
                DELAY_CHAPTER_MIN,
                DELAY_CHAPTER_MAX,
                f"post-chapter {ch_data.get('chapter_number')}",
            )

    await _stop_progress(image_progress)
    return ch_images_count, len(chapters_rest)


async def save_chapter_metadata(
    session,
    *,
    comic_id: int,
    chapters_data: list[dict[str, Any]],
    comic_position: int,
    page_total: int,
) -> int:
    """Simpan metadata chapter sambil melaporkan progres per chapter."""
    comic_label = _comic_progress_label(comic_position, page_total)
    saved_count = 0
    progress: CliLiveProgress | None = None
    valid_chapter_total = sum(1 for chapter in chapters_data if chapter.get("source_url", ""))

    if chapters_data:
        total_steps = len(chapters_data) + (1 if valid_chapter_total else 0)
        logger.info(
            f"  📚 {comic_label} Upsert chapter metadata: "
            f"{len(chapters_data)} chapter"
            + (" + 1 flush" if valid_chapter_total else "")
        )
        progress = CliLiveProgress(
            label=f"{comic_label} chapter metadata",
            total_steps=total_steps,
        )
        progress.start()
        progress.set_detail(
            f"menyiapkan {len(chapters_data)} chapter"
            + (" + flush final" if valid_chapter_total else "")
        )
    else:
        logger.info(f"  📚 {comic_label} Tidak ada chapter metadata.")

    try:
        total_chapters = len(chapters_data)
        total_progress_steps = total_chapters + (1 if valid_chapter_total else 0)
        for chapter_index, ch_data in enumerate(chapters_data, start=1):
            ch_num = ch_data.get("chapter_number", 0)
            if not ch_data.get("source_url"):
                if progress is not None:
                    progress.advance(
                        "chapter "
                        f"{chapter_index}/{total_chapters} | "
                        f"langkah {chapter_index}/{total_progress_steps}: "
                        f"skip ch {ch_num} (no source_url)"
                    )
                continue

            if progress is not None:
                progress.set_detail(
                    "chapter "
                    f"{chapter_index}/{total_chapters} | "
                    f"langkah {chapter_index}/{total_progress_steps}: "
                    f"upsert ch {ch_num}"
                )
            await upsert_chapter_metadata(session, comic_id, ch_data)
            saved_count += 1
            if progress is not None:
                progress.advance(
                    "chapter "
                    f"{chapter_index}/{total_chapters} | "
                    f"langkah {chapter_index}/{total_progress_steps}: "
                    f"tersimpan ch {ch_num}"
                )

        if valid_chapter_total and progress is not None:
            progress.set_detail(
                f"flush final | langkah {total_progress_steps}/{total_progress_steps}"
            )
            await session.flush()
            progress.advance(
                f"flush final selesai | langkah {total_progress_steps}/{total_progress_steps}"
            )
        elif valid_chapter_total:
            await session.flush()
    finally:
        await _stop_progress(progress)

    return saved_count


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
    comic_position: int,
    page_total: int,
) -> None:
    """
    Proses satu komik penuh: detail, upsert, metadata chapter, lalu pre-warm.

    Karena fungsi ini dipanggil dari incremental feed sync, upsert comic juga
    ikut memperbarui marker `latest_feed_*` dan/atau `popular_feed_*` supaya
    endpoint feed-based merepresentasikan urutan canonical source.
    """
    detail_url = comic_basic.get("source_url", "")
    title = comic_basic.get("title", "???")
    comic_label = _comic_progress_label(comic_position, page_total)
    fetch_progress: CliLiveProgress | None = None
    upsert_progress: CliLiveProgress | None = None

    if not detail_url:
        stats.total_skipped += 1
        logger.warning(f"  ⏭️ {comic_label} Skip (no URL): {title}")
        return

    await random_delay(DELAY_DETAIL_MIN, DELAY_DETAIL_MAX, f"pre-detail {title}")

    try:
        logger.info(f"  📖 {comic_label} Mengambil detail: {title}")
        fetch_progress = CliLiveProgress(
            label=f"{comic_label} fetch detail",
            total_steps=1,
        )
        fetch_progress.start()
        fetch_progress.set_detail("langkah 1/1: menunggu response detail komik")
        comic_detail = await scraper.get_comic_detail(detail_url)
        fetch_progress.advance("langkah 1/1 selesai: detail komik diterima")
        await _stop_progress(fetch_progress)
        fetch_progress = None

        if not comic_detail.get("title"):
            stats.total_errors += 1
            logger.warning(f"  ⚠️ {comic_label} Tidak ada title di detail, skip: {detail_url}")
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

        genre_total = len(validated.genres)
        upsert_total_steps = 2
        logger.info(
            f"  💾 {comic_label} Upsert komik: {validated.title} "
            f"(metadata + sinkron genre)"
        )
        upsert_progress = CliLiveProgress(
            label=f"{comic_label} upsert DB",
            total_steps=upsert_total_steps,
        )
        upsert_progress.start()
        upsert_progress.set_detail("langkah 1/2: menyimpan metadata komik")
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
        upsert_progress.advance("langkah 1/2 selesai: metadata komik tersimpan")
        upsert_progress.set_detail(
            f"langkah 2/2: sinkron genre ({genre_total} genre)"
        )
        await sync_comic_genres(session, comic_id, validated.genres)
        upsert_progress.advance("langkah 2/2 selesai: genre tersinkron")
        await _stop_progress(upsert_progress)
        upsert_progress = None

        stats.total_comics += 1
        stats.comics_since_cooldown += 1
        logger.info(
            f"    💾 {comic_label} Upsert selesai: {validated.title} "
            f"({genre_total} genre) [Total komik: {stats.total_comics}]"
        )

        chapters_data = comic_detail.get("chapters", [])
        chapters_sorted = sorted(
            chapters_data,
            key=lambda c: c.get("chapter_number", 0),
            reverse=True,
        )
        chapter_saved_count = await save_chapter_metadata(
            session,
            comic_id=comic_id,
            chapters_data=chapters_sorted,
            comic_position=comic_position,
            page_total=page_total,
        )
        stats.total_chapters_meta += chapter_saved_count
        if chapter_saved_count:
            logger.info(
                f"    📚 {comic_label} {chapter_saved_count} chapter metadata tersimpan "
                f"[Total chapter metadata: {stats.total_chapters_meta}]"
            )

        ch_images_count, chapters_rest_count = await prewarm_latest_chapters(
            session,
            scraper,
            comic_id=comic_id,
            validated=validated,
            chapters_sorted=chapters_sorted,
            stats=stats,
            comic_position=comic_position,
            page_total=page_total,
        )

        logger.info(
            f"  ✅ {comic_label} Done: {validated.title} — "
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
    finally:
        await _stop_progress(fetch_progress)
        await _stop_progress(upsert_progress)


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
                    logger.warning(
                        f"  ⏭️ {_comic_progress_label(position, len(comics_list))} "
                        f"Skip invalid listing: {title} ({reason})"
                    )
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
                    logger.info(
                        f"  ⏭️ {_comic_progress_label(position, len(comics_list))} "
                        f"Skip unchanged: {title} ({reason})"
                    )
                continue

            page_candidates += 1
            stats.total_candidates += 1
            logger.info(
                f"  🆕 {_comic_progress_label(position, len(comics_list))} "
                f"Kandidat update: {title} ({reason})"
            )

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
                    comic_position=position,
                    page_total=len(comics_list),
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

                await _backoff_delay(
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
                logger.info(
                    f"  ⏭️ {_comic_progress_label(position, len(comics_list))} "
                    f"Mark popular: {title} (sudah ada di DB)"
                )
                continue

            page_candidates += 1
            stats.total_candidates += 1
            logger.info(
                f"  🆕 {_comic_progress_label(position, len(comics_list))} "
                f"Kandidat popular baru: {title} (comic baru di ranking)"
            )

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
                    comic_position=position,
                    page_total=len(comics_list),
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

                await _backoff_delay(
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
    logger.info(f"   Waktu       : {format_elapsed_duration(elapsed)}")
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
        "log_file": "",
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

    log_file = resolve_log_path(str(args["log_file"]) if args["log_file"] else "main.log")
    configure_logging(str(log_file))
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
