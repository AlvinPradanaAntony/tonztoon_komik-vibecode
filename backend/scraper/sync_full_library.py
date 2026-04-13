"""
Tonztoon Komik — Sync Full Library (Mass Scraper)

Script untuk mengambil seluruh direktori komik dari sumber dan menyimpannya
ke database. Dirancang untuk berjalan lama tanpa terblokir oleh situs sumber.

Strategi Anti-Blocking / Anti-Rate-Limit:
──────────────────────────────────────────
1. Random Delay         → Jeda acak (bukan kaku) antar-request menggunakan
                          modul `random` agar pola request tidak terdeteksi.
2. Checkpoint / Resume  → Menyimpan progres ke file JSON. Jika script mati
                          atau terputus, saat dijalankan ulang akan melanjutkan
                          dari halaman & komik terakhir, BUKAN dari awal.
3. Exponential Backoff  → Jika terjadi error berturut-turut (misalnya 429 /
                          timeout), jeda akan meningkat secara eksponensial
                          (2s → 4s → 8s → ...) hingga batas maksimum.
4. Per-Comic Commit     → Setiap 1 komik selesai langsung di-commit ke DB,
                          sehingga data tidak hilang jika crash di tengah jalan.
5. Cooldown Berkala     → Setiap N komik, script istirahat lebih lama
                          (cool-down period) untuk menghindari deteksi burst.
6. Graceful Shutdown    → Menangkap SIGINT (Ctrl+C) dengan aman: menyimpan
                          checkpoint sebelum berhenti.

Usage:
    cd backend
    python -m scraper.sync_full_library
    python -m scraper.sync_full_library --reset   # Hapus checkpoint, mulai ulang
    python -m scraper.sync_full_library --start 5 --max 20  # Halaman 5-24
"""

import asyncio
import json
import logging
import os
import random
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.schemas import ComicCreate
from app.models import Comic, Chapter, Genre, comic_genre

from sqlalchemy.dialects.postgresql import insert as pg_insert

from scraper.sources.komiku_scraper import KomikuScraper
# Reuse upsert methods dari main
from scraper.main import upsert_comic, upsert_genre

# ═══════════════════════════════════════════════════════════════════
# LOGGING SETUP
# ═══════════════════════════════════════════════════════════════════
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("sync-full-library")

# ═══════════════════════════════════════════════════════════════════
# KONFIGURASI
# ═══════════════════════════════════════════════════════════════════

# -- Halaman --
DEFAULT_START_PAGE = 1
DEFAULT_MAX_PAGES = 10  # Jumlah halaman yang di-scrape

# -- Delay (dalam detik) --
DELAY_COMIC_MIN = 2.0        # Jeda minimum antar-komik
DELAY_COMIC_MAX = 5.0        # Jeda maksimum antar-komik
DELAY_PAGE_MIN = 4.0         # Jeda minimum antar-halaman
DELAY_PAGE_MAX = 8.0         # Jeda maksimum antar-halaman
DELAY_DETAIL_MIN = 1.5       # Jeda minimum sebelum fetch detail
DELAY_DETAIL_MAX = 3.5       # Jeda maksimum sebelum fetch detail

# -- Cooldown Berkala --
COOLDOWN_EVERY_N_COMICS = 15  # Setiap 15 komik, istirahat lebih lama
COOLDOWN_MIN = 10.0           # Cooldown minimum (detik)
COOLDOWN_MAX = 20.0           # Cooldown maksimum (detik)

# -- Exponential Backoff --
BACKOFF_BASE = 2.0            # Base delay untuk backoff (detik)
BACKOFF_MAX = 120.0           # Maksimum delay backoff (2 menit)
MAX_CONSECUTIVE_ERRORS = 5    # Batas error berturut-turut sebelum skip halaman

# -- Checkpoint --
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "data"
CHECKPOINT_FILE = CHECKPOINT_DIR / "sync_checkpoint.json"

# ═══════════════════════════════════════════════════════════════════
# CHECKPOINT SYSTEM
# ═══════════════════════════════════════════════════════════════════


def load_checkpoint() -> dict:
    """
    Muat checkpoint dari file JSON.
    
    Struktur checkpoint:
        {
            "last_completed_page": 3,
            "last_comic_index": 12,
            "completed_slugs": ["slug-1", "slug-2", ...],
            "stats": {"total_upserted": 45, "total_skipped": 3},
            "updated_at": "2026-04-13T..."
        }
    """
    if CHECKPOINT_FILE.exists():
        try:
            with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            logger.info(
                f"📂 Checkpoint ditemukan! "
                f"Terakhir: halaman {data.get('last_completed_page', 0)}, "
                f"komik index {data.get('last_comic_index', 0)}, "
                f"{len(data.get('completed_slugs', []))} komik sudah selesai."
            )
            return data
        except (json.JSONDecodeError, KeyError) as e:
            logger.warning(f"⚠️ Checkpoint rusak, akan mulai dari awal: {e}")
    return {
        "last_completed_page": 0,
        "last_comic_index": -1,
        "completed_slugs": [],
        "stats": {"total_upserted": 0, "total_skipped": 0, "total_errors": 0, "total_chapters_saved": 0},
        "updated_at": None,
    }


def save_checkpoint(checkpoint: dict) -> None:
    """Simpan checkpoint ke file JSON."""
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint["updated_at"] = datetime.now().isoformat()
    with open(CHECKPOINT_FILE, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)
    logger.debug("💾 Checkpoint tersimpan.")


def reset_checkpoint() -> None:
    """Hapus file checkpoint."""
    if CHECKPOINT_FILE.exists():
        CHECKPOINT_FILE.unlink()
        logger.info("🗑️ Checkpoint dihapus. Akan mulai dari awal.")
    else:
        logger.info("ℹ️ Tidak ada checkpoint yang perlu dihapus.")


# ═══════════════════════════════════════════════════════════════════
# UTILITY: RANDOM DELAY & BACKOFF
# ═══════════════════════════════════════════════════════════════════


async def random_delay(min_sec: float, max_sec: float, label: str = "") -> None:
    """Jeda acak antara min_sec dan max_sec detik."""
    delay = random.uniform(min_sec, max_sec)
    if label:
        logger.info(f"  ⏳ {label}: menunggu {delay:.1f}s...")
    await asyncio.sleep(delay)


async def backoff_delay(attempt: int, label: str = "") -> None:
    """
    Exponential backoff: delay = base * 2^attempt, dengan jitter.
    Contoh: 2s → 4s → 8s → 16s → ... (maks BACKOFF_MAX).
    """
    delay = min(BACKOFF_BASE * (2 ** attempt), BACKOFF_MAX)
    # Tambahkan jitter ±25% agar tidak persis sama
    jitter = delay * random.uniform(-0.25, 0.25)
    delay = max(1.0, delay + jitter)
    logger.warning(f"  ⏳ Backoff (attempt {attempt + 1}): {label} — menunggu {delay:.1f}s...")
    await asyncio.sleep(delay)


# ═══════════════════════════════════════════════════════════════════
# GRACEFUL SHUTDOWN
# ═══════════════════════════════════════════════════════════════════

_shutdown_requested = False


def _signal_handler(signum, frame):
    """Handle Ctrl+C dengan menyimpan checkpoint terlebih dahulu."""
    global _shutdown_requested
    if _shutdown_requested:
        logger.warning("⛔ Paksa berhenti!")
        sys.exit(1)
    _shutdown_requested = True
    logger.warning(
        "\n🛑 Shutdown diminta (Ctrl+C). "
        "Menyelesaikan komik saat ini dan menyimpan checkpoint..."
    )


# ═══════════════════════════════════════════════════════════════════
# MAIN PIPELINE
# ═══════════════════════════════════════════════════════════════════


async def run_sync_full_library(start_page: int, max_pages: int):
    """Pipeline utama mass-scraping dengan semua strategi anti-blocking."""
    global _shutdown_requested

    start_time = time.time()
    checkpoint = load_checkpoint()
    completed_slugs = set(checkpoint.get("completed_slugs", []))
    stats = checkpoint.get("stats", {"total_upserted": 0, "total_skipped": 0, "total_errors": 0, "total_chapters_saved": 0})
    stats.setdefault("total_chapters_saved", 0)
    comics_since_cooldown = 0  # Counter untuk cooldown berkala

    # Tentukan halaman awal berdasarkan checkpoint
    resume_page = max(start_page, checkpoint.get("last_completed_page", 0))
    resume_comic_index = checkpoint.get("last_comic_index", -1)

    # Jika checkpoint menunjukkan halaman terakhir sudah selesai semua komiknya,
    # lanjutkan ke halaman berikutnya mulai dari komik index 0
    if resume_page > start_page or (resume_page == checkpoint.get("last_completed_page", 0) and resume_comic_index == -1):
        resume_comic_index = -1  # Akan di-increment ke 0

    end_page = start_page + max_pages - 1

    logger.info("═" * 60)
    logger.info(f"🚀 Sync Full Library dimulai — {datetime.now().isoformat()}")
    logger.info(f"   Target halaman  : {start_page} → {end_page}")
    logger.info(f"   Resume dari     : halaman {resume_page}, komik index > {resume_comic_index}")
    logger.info(f"   Komik sudah done: {len(completed_slugs)}")
    logger.info(f"   Delay komik     : {DELAY_COMIC_MIN}-{DELAY_COMIC_MAX}s (random)")
    logger.info(f"   Delay halaman   : {DELAY_PAGE_MIN}-{DELAY_PAGE_MAX}s (random)")
    logger.info(f"   Cooldown setiap : {COOLDOWN_EVERY_N_COMICS} komik")
    logger.info(f"   Checkpoint file : {CHECKPOINT_FILE}")
    logger.info("═" * 60)

    # Inisialisasi scraper
    scraper = KomikuScraper()

    async with async_session() as session:
        for page in range(resume_page, end_page + 1):
            if _shutdown_requested:
                break

            # Skip halaman yang sudah selesai (kecuali halaman resume)
            if page < resume_page:
                continue

            logger.info(f"\n{'─' * 50}")
            logger.info(f"📄 Halaman {page}/{end_page}")
            logger.info(f"{'─' * 50}")

            # Fetch daftar komik di halaman ini
            consecutive_errors = 0
            comics_list = None

            for attempt in range(3):  # Retry sampai 3x untuk fetch halaman
                try:
                    comics_list = await scraper.get_comic_list(page=page)
                    break
                except Exception as e:
                    logger.error(f"  ✗ Gagal fetch halaman {page} (attempt {attempt + 1}): {e}")
                    await backoff_delay(attempt, f"retry halaman {page}")

            if not comics_list:
                logger.warning(f"  ⚠️ Tidak ada komik ditemukan di halaman {page}. "
                               f"Kemungkinan sudah akhir daftar.")
                # Simpan checkpoint — halaman ini dianggap selesai (kosong)
                checkpoint["last_completed_page"] = page
                checkpoint["last_comic_index"] = -1
                checkpoint["completed_slugs"] = list(completed_slugs)
                checkpoint["stats"] = stats
                save_checkpoint(checkpoint)
                break  # Sudah di ujung daftar

            logger.info(f"  📋 Ditemukan {len(comics_list)} komik di halaman {page}")

            for idx, comic_basic in enumerate(comics_list):
                if _shutdown_requested:
                    break

                # ── Skip komik yang sudah diproses (checkpoint resume) ──
                if page == resume_page and idx <= resume_comic_index:
                    continue

                slug = comic_basic.get("slug", "")
                title = comic_basic.get("title", "???")
                detail_url = comic_basic.get("source_url", "")

                # ── Skip komik yang sudah ada di checkpoint ──
                if slug and slug in completed_slugs:
                    logger.info(f"  ⏭️ [{idx + 1}/{len(comics_list)}] Skip (sudah done): {title}")
                    stats["total_skipped"] += 1
                    continue

                if not detail_url:
                    logger.warning(f"  ⏭️ [{idx + 1}/{len(comics_list)}] Skip (no URL): {title}")
                    continue

                logger.info(f"  📖 [{idx + 1}/{len(comics_list)}] Mengambil detail: {title}")

                # ── Random delay sebelum fetch detail ──
                await random_delay(DELAY_DETAIL_MIN, DELAY_DETAIL_MAX, "delay pre-detail")

                try:
                    # Fetch detail komik
                    comic_detail = await scraper.get_comic_detail(detail_url)

                    if not comic_detail.get("title"):
                        logger.warning(f"  ⚠️ Tidak ada title di detail, skip: {title}")
                        stats["total_errors"] += 1
                        continue

                    # Validasi dengan Pydantic
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
                        source_url=comic_detail["source_url"],
                        source_name=comic_detail["source_name"],
                        genres=comic_detail.get("genres", []),
                    )

                    # Upsert comic ke DB
                    comic_id = await upsert_comic(session, validated)

                    # Upsert genres & link
                    for genre_name in validated.genres:
                        genre_id = await upsert_genre(session, genre_name)
                        genre_link = pg_insert(comic_genre).values(
                            comic_id=comic_id, genre_id=genre_id
                        )
                        genre_link = genre_link.on_conflict_do_nothing()
                        await session.execute(genre_link)

                    # ── Per-comic commit (crash resilience) ──
                    await session.commit()

                    stats["total_upserted"] += 1
                    comics_since_cooldown += 1
                    consecutive_errors = 0  # Reset error counter

                    logger.info(
                        f"  ✅ Upserted: {validated.title} "
                        f"({len(validated.genres)} genre) "
                        f"[Total: {stats['total_upserted']}]"
                    )

                    # ═══════════════════════════════════════════
                    # SIMPAN METADATA CHAPTER (tanpa fetch images)
                    # Images akan di-fetch on-demand (lazy loading)
                    # saat user membaca chapter via API.
                    # ═══════════════════════════════════════════
                    chapters_data = comic_detail.get("chapters", [])
                    if chapters_data:
                        ch_saved = 0
                        for ch_data in chapters_data:
                            ch_num = ch_data.get("chapter_number", 0)
                            ch_url = ch_data.get("source_url", "")
                            if not ch_url:
                                continue

                            # Upsert chapter metadata saja (images=NULL)
                            # Jika chapter sudah ada, update title & release_date
                            stmt = pg_insert(Chapter).values(
                                comic_id=comic_id,
                                chapter_number=ch_num,
                                title=ch_data.get("title"),
                                source_url=ch_url,
                                release_date=ch_data.get("release_date"),
                            )
                            stmt = stmt.on_conflict_do_update(
                                constraint="uq_comic_chapter",
                                set_={
                                    "title": ch_data.get("title"),
                                    "source_url": ch_url,
                                    "release_date": ch_data.get("release_date"),
                                },
                            )
                            await session.execute(stmt)
                            ch_saved += 1

                        await session.commit()
                        stats["total_chapters_saved"] += ch_saved
                        logger.info(
                            f"    📚 {ch_saved} chapter metadata tersimpan "
                            f"(images akan di-fetch on-demand)"
                        )
                    else:
                        logger.info(f"    ℹ️ Tidak ada daftar chapter dari detail page.")

                    # Tandai slug sebagai selesai
                    completed_slugs.add(validated.slug)

                    # ── Simpan checkpoint setiap komik selesai ──
                    checkpoint["last_completed_page"] = page
                    checkpoint["last_comic_index"] = idx
                    checkpoint["completed_slugs"] = list(completed_slugs)
                    checkpoint["stats"] = stats
                    save_checkpoint(checkpoint)

                    # ── Cooldown berkala ──
                    if comics_since_cooldown >= COOLDOWN_EVERY_N_COMICS:
                        comics_since_cooldown = 0
                        logger.info(
                            f"\n  🧊 Cooldown berkala ({COOLDOWN_EVERY_N_COMICS} komik tercapai)..."
                        )
                        await random_delay(COOLDOWN_MIN, COOLDOWN_MAX, "cooldown berkala")

                    # ── Random delay antar-komik ──
                    await random_delay(DELAY_COMIC_MIN, DELAY_COMIC_MAX, "delay antar-komik")

                except Exception as e:
                    consecutive_errors += 1
                    stats["total_errors"] += 1
                    logger.error(
                        f"  ✗ Error [{consecutive_errors}/{MAX_CONSECUTIVE_ERRORS}] "
                        f"pada {title}: {e}"
                    )
                    await session.rollback()

                    # Simpan checkpoint meskipun error
                    checkpoint["last_completed_page"] = page
                    checkpoint["last_comic_index"] = idx
                    checkpoint["completed_slugs"] = list(completed_slugs)
                    checkpoint["stats"] = stats
                    save_checkpoint(checkpoint)

                    # ── Exponential backoff pada error berturut-turut ──
                    if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                        logger.error(
                            f"  ⛔ {MAX_CONSECUTIVE_ERRORS} error berturut-turut! "
                            f"Skip sisa halaman {page}."
                        )
                        break
                    else:
                        await backoff_delay(consecutive_errors, f"error pada {title}")
                    continue

            # ── Halaman selesai ──
            if not _shutdown_requested:
                logger.info(f"\n  ✅ Halaman {page} selesai.")

                # Update checkpoint: halaman ini sudah komplit
                checkpoint["last_completed_page"] = page
                checkpoint["last_comic_index"] = -1  # Reset untuk halaman berikutnya
                checkpoint["completed_slugs"] = list(completed_slugs)
                checkpoint["stats"] = stats
                save_checkpoint(checkpoint)

                # Random delay antar-halaman
                if page < end_page:
                    await random_delay(DELAY_PAGE_MIN, DELAY_PAGE_MAX, "delay antar-halaman")

    # ═══════════════════════════════════════════════════════════════
    # RINGKASAN
    # ═══════════════════════════════════════════════════════════════
    elapsed = time.time() - start_time
    minutes = elapsed / 60

    logger.info("\n" + "═" * 60)
    if _shutdown_requested:
        logger.info("🛑 Sync dihentikan oleh user (Ctrl+C).")
    else:
        logger.info("🏁 Sync Full Library selesai!")
    logger.info(f"   Waktu       : {minutes:.1f} menit ({elapsed:.0f} detik)")
    logger.info(f"   Upserted    : {stats['total_upserted']} komik")
    logger.info(f"   Chapters    : {stats['total_chapters_saved']} chapter metadata tersimpan")
    logger.info(f"   Skipped     : {stats['total_skipped']} komik (sudah ada)")
    logger.info(f"   Errors      : {stats['total_errors']}")
    logger.info(f"   Checkpoint  : {CHECKPOINT_FILE}")
    logger.info("═" * 60)


# ═══════════════════════════════════════════════════════════════════
# CLI ENTRY POINT
# ═══════════════════════════════════════════════════════════════════


def parse_args():
    """Parse argumen command-line sederhana (tanpa argparse agar ringan)."""
    args = {
        "start": DEFAULT_START_PAGE,
        "max": DEFAULT_MAX_PAGES,
        "reset": False,
    }

    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--reset":
            args["reset"] = True
        elif argv[i] == "--start" and i + 1 < len(argv):
            args["start"] = int(argv[i + 1])
            i += 1
        elif argv[i] == "--max" and i + 1 < len(argv):
            args["max"] = int(argv[i + 1])
            i += 1
        elif argv[i] == "--help":
            print(__doc__)
            sys.exit(0)
        i += 1

    return args


def main():
    """Entry point."""
    args = parse_args()

    # Daftarkan signal handler untuk graceful shutdown
    signal.signal(signal.SIGINT, _signal_handler)
    # SIGTERM biasanya tidak tersedia di Windows, tapi kita coba
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _signal_handler)

    if args["reset"]:
        reset_checkpoint()

    asyncio.run(run_sync_full_library(
        start_page=args["start"],
        max_pages=args["max"],
    ))


if __name__ == "__main__":
    main()
