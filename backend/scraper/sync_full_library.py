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
    python -m scraper.sync_full_library  # Log default: logs/sync_full_library.log
    python -m scraper.sync_full_library --source komiku_asia
    python -m scraper.sync_full_library --mode validate
    python -m scraper.sync_full_library --mode refresh
    python -m scraper.sync_full_library --log-file validate.log
    python -m scraper.sync_full_library --mode validate --reset   # Hapus checkpoint validate
    python -m scraper.sync_full_library --mode refresh --reset    # Hapus checkpoint refresh
    python -m scraper.sync_full_library --start 5 --max 20  # Jumlah halaman 20 -> target 5-24
    python -m scraper.sync_full_library --start 36 --end 37  # Hanya halaman 36-37
    python -m scraper.sync_full_library --start 70 --end 72 --mode validate --reset --log-file sync.log
"""

import asyncio
from dataclasses import dataclass
import json
import logging
import random
import signal
import sys
import time
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Chapter, Comic, comic_genre
from app.schemas import ComicCreate

from scraper.base_scraper import BaseComicScraper
from scraper.sources.registry import create_scraper, get_supported_source_names
# Reuse upsert methods dari main
from scraper.main import upsert_comic, upsert_genre
from scraper.time_utils import now_wib

# ═══════════════════════════════════════════════════════════════════
# LOGGING SETUP
# ═══════════════════════════════════════════════════════════════════

DEFAULT_LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
DEFAULT_LOG_FILE = Path("sync_full_library.log")


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
SUPPORTED_MODES = {"validate", "refresh"}
SUPPORTED_SOURCES = tuple(get_supported_source_names())

# -- Checkpoint --
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "data"
LEGACY_CHECKPOINT_FILE = CHECKPOINT_DIR / "sync_checkpoint.json"

# ═══════════════════════════════════════════════════════════════════
# CHECKPOINT STATE HELPERS
# ═══════════════════════════════════════════════════════════════════


def get_checkpoint_file(mode: str, source_name: str) -> Path:
    """Ambil path checkpoint sesuai mode sync."""
    if mode not in SUPPORTED_MODES:
        raise ValueError(
            f"Mode checkpoint tidak valid: {mode}. "
            f"Gunakan salah satu dari {', '.join(sorted(SUPPORTED_MODES))}."
        )
    if source_name not in SUPPORTED_SOURCES:
        raise ValueError(
            f"Source tidak valid: {source_name}. "
            f"Gunakan salah satu dari {', '.join(SUPPORTED_SOURCES)}."
        )
    return CHECKPOINT_DIR / f"sync_checkpoint_{source_name}_{mode}.json"


def get_checkpoint_scope_label(mode: str, source_name: str) -> str:
    """Label singkat untuk menjelaskan isolasi checkpoint per mode."""
    return f"{source_name}:{mode} (terpisah per source dan mode)"


def _default_stats() -> dict:
    """Default statistik sync."""
    return {
        "total_upserted": 0,
        "total_skipped": 0,
        "total_errors": 0,
        "total_chapters_saved": 0,
    }


def _default_progress() -> dict:
    """Default progress runtime untuk summary dan checkpoint."""
    return {
        "mode": None,
        "target_start_page": 0,
        "target_end_page": 0,
        "current_page": 0,
        "page_comics_total": 0,
        "current_comic_index": -1,
        "current_comic_position": 0,
        "current_comic_title": None,
        "current_comic_slug": None,
        "current_comic_url": None,
        "state": "idle",
        "note": None,
    }


def _normalize_checkpoint(data: dict | None) -> dict:
    """Pastikan shape checkpoint konsisten, termasuk file lama."""
    checkpoint = data or {}
    checkpoint.setdefault("last_completed_page", 0)
    checkpoint.setdefault("last_comic_index", -1)
    checkpoint.setdefault("completed_slugs", [])
    checkpoint.setdefault("updated_at", None)

    default_stats = _default_stats()
    stats = checkpoint.setdefault("stats", default_stats.copy())
    for key, value in default_stats.items():
        stats.setdefault(key, value)

    default_progress = _default_progress()
    progress = checkpoint.setdefault("progress", default_progress.copy())
    for key, value in default_progress.items():
        progress.setdefault(key, value)

    # Backward compatibility untuk checkpoint lama yang belum punya `progress`.
    if progress["current_page"] == 0:
        progress["current_page"] = checkpoint["last_completed_page"]
    if progress["current_comic_index"] == -1 and checkpoint["last_comic_index"] >= 0:
        progress["current_comic_index"] = checkpoint["last_comic_index"]
        progress["current_comic_position"] = checkpoint["last_comic_index"] + 1
    elif progress["current_comic_index"] < 0:
        progress["current_comic_position"] = 0

    return checkpoint


def update_progress(
    checkpoint: dict,
    *,
    mode: str | None = None,
    target_start_page: int | None = None,
    target_end_page: int | None = None,
    current_page: int | None = None,
    page_comics_total: int | None = None,
    current_comic_index: int | None = None,
    current_comic_title: str | None = None,
    current_comic_slug: str | None = None,
    current_comic_url: str | None = None,
    state: str | None = None,
    note: str | None = None,
) -> dict:
    """Update progress aktif di dalam checkpoint."""
    progress = checkpoint.setdefault("progress", _default_progress())

    if mode is not None:
        progress["mode"] = mode
    if target_start_page is not None:
        progress["target_start_page"] = target_start_page
    if target_end_page is not None:
        progress["target_end_page"] = target_end_page
    if current_page is not None:
        progress["current_page"] = current_page
    if page_comics_total is not None:
        progress["page_comics_total"] = page_comics_total
    if current_comic_index is not None:
        progress["current_comic_index"] = current_comic_index
        progress["current_comic_position"] = current_comic_index + 1 if current_comic_index >= 0 else 0
        if current_comic_index < 0:
            progress["current_comic_title"] = None
            progress["current_comic_slug"] = None
            progress["current_comic_url"] = None
    if current_comic_title is not None:
        progress["current_comic_title"] = current_comic_title
    if current_comic_slug is not None:
        progress["current_comic_slug"] = current_comic_slug
    if current_comic_url is not None:
        progress["current_comic_url"] = current_comic_url
    if state is not None:
        progress["state"] = state
    if note is not None:
        progress["note"] = note

    return progress


# ═══════════════════════════════════════════════════════════════════
# CHECKPOINT PERSISTENCE HELPERS
# ═══════════════════════════════════════════════════════════════════


def persist_checkpoint_state(
    checkpoint: dict,
    *,
    checkpoint_file: Path,
    stats: dict,
    completed_slugs: set[str] | None = None,
    last_completed_page: int | None = None,
    last_comic_index: int | None = None,
    **progress_kwargs,
) -> dict:
    """Sinkronkan state runtime ke checkpoint lalu simpan ke file."""
    if last_completed_page is not None:
        checkpoint["last_completed_page"] = last_completed_page
    if last_comic_index is not None:
        checkpoint["last_comic_index"] = last_comic_index
    if completed_slugs is not None:
        checkpoint["completed_slugs"] = sorted(completed_slugs)

    checkpoint["stats"] = stats
    progress = update_progress(checkpoint, **progress_kwargs)
    save_checkpoint(checkpoint, checkpoint_file)
    return progress


# ═══════════════════════════════════════════════════════════════════
# RANGE & RESUME HELPERS
# ═══════════════════════════════════════════════════════════════════


def resolve_target_end_page(start_page: int, max_pages: int, end_page: int | None) -> int:
    """Hitung halaman akhir target sync."""
    if start_page < 1:
        raise ValueError("--start harus lebih besar atau sama dengan 1")
    if max_pages < 1:
        raise ValueError("--max harus lebih besar atau sama dengan 1")
    if end_page is not None:
        if end_page < start_page:
            raise ValueError("--end harus lebih besar atau sama dengan --start")
        return end_page
    return start_page + max_pages - 1


def resolve_resume_position(
    checkpoint: dict,
    mode: str,
    start_page: int,
    end_page: int,
) -> tuple[int, int, str]:
    """
    Tentukan resume page/index berdasarkan checkpoint.

    Checkpoint hanya dipakai jika posisinya masih berada di dalam range target.
    Jika user menjalankan range eksplisit yang berbeda, sync mulai dari range itu.
    """
    checkpoint_page = checkpoint.get("last_completed_page", 0)
    checkpoint_index = checkpoint.get("last_comic_index", -1)
    checkpoint_mode = checkpoint.get("progress", {}).get("mode")

    if checkpoint_mode and checkpoint_mode != mode:
        return start_page, -1, "checkpoint-ignored-mode-mismatch"

    if start_page <= checkpoint_page <= end_page:
        if checkpoint_index == -1:
            next_page = checkpoint_page + 1
            if next_page <= end_page:
                return next_page, -1, "resume-next-page-after-complete"
            return end_page + 1, -1, "range-already-complete"
        return checkpoint_page, checkpoint_index, "checkpoint-in-range"

    return start_page, -1, "checkpoint-ignored-outside-range"


# ═══════════════════════════════════════════════════════════════════
# PROGRESS DISPLAY HELPERS
# ═══════════════════════════════════════════════════════════════════


def _format_page_progress(progress: dict) -> str:
    """Format posisi halaman untuk summary log."""
    current_page = progress.get("current_page") or 0
    target_start = progress.get("target_start_page") or 0
    target_end = progress.get("target_end_page") or 0

    if current_page and target_end:
        if target_start and target_start != 1:
            return f"{current_page} (range {target_start}-{target_end})"
        return f"{current_page}/{target_end}"
    if current_page:
        return str(current_page)
    return "-"


def _format_comic_progress(progress: dict) -> str:
    """Format posisi komik aktif untuk summary log."""
    comic_title = progress.get("current_comic_title")
    comic_position = progress.get("current_comic_position") or 0
    page_total = progress.get("page_comics_total") or 0

    if comic_title and comic_position and page_total:
        return f"[{comic_position}/{page_total}] {comic_title}"
    if comic_title and comic_position:
        return f"[{comic_position}] {comic_title}"
    if comic_title:
        return comic_title
    return "-"


def _format_elapsed_duration(elapsed_seconds: float) -> str:
    """Format durasi menjadi bentuk yang lebih natural."""
    total_seconds = max(0, int(round(elapsed_seconds)))
    minutes, seconds = divmod(total_seconds, 60)
    hours, minutes = divmod(minutes, 60)

    parts = []
    if hours:
        parts.append(f"{hours} jam")
    if minutes:
        parts.append(f"{minutes} menit")
    if seconds or not parts:
        parts.append(f"{seconds} detik")

    return f"{' '.join(parts)} ({total_seconds} detik)"


# ═══════════════════════════════════════════════════════════════════
# DATABASE LOOKUP HELPERS
# ═══════════════════════════════════════════════════════════════════


async def get_existing_comic_slugs(
    session,
    *,
    source_name: str,
    slugs: list[str],
) -> set[str]:
    """Ambil slug komik yang sudah ada di database untuk satu source."""
    unique_slugs = sorted({slug for slug in slugs if slug})
    if not unique_slugs:
        return set()

    stmt = select(Comic.slug).where(
        Comic.source_name == source_name,
        Comic.slug.in_(unique_slugs),
    )
    result = await session.execute(stmt)
    return set(result.scalars().all())

# ═══════════════════════════════════════════════════════════════════
# CHECKPOINT IO HELPERS
# ═══════════════════════════════════════════════════════════════════


def load_checkpoint(mode: str, source_name: str) -> dict:
    """
    Muat checkpoint dari file JSON.
    
    Struktur checkpoint:
        {
            "last_completed_page": 3,
            "last_comic_index": 12,
            "completed_slugs": ["slug-1", "slug-2", ...],
            "stats": {"total_upserted": 45, "total_skipped": 3},
            "progress": {
                "current_page": 3,
                "current_comic_position": 13,
                "current_comic_title": "Judul Komik"
            },
            "updated_at": "2026-04-13T..."
        }
    """
    checkpoint_file = get_checkpoint_file(mode, source_name)
    if checkpoint_file.exists():
        try:
            with open(checkpoint_file, "r", encoding="utf-8") as f:
                data = _normalize_checkpoint(json.load(f))
            logger.info(
                f"📂 Checkpoint ditemukan! "
                f"Terakhir: halaman {data.get('last_completed_page', 0)}, "
                f"komik index {data.get('last_comic_index', 0)}, "
                f"{len(data.get('completed_slugs', []))} komik sudah selesai."
            )
            logger.info(f"    File checkpoint : {checkpoint_file}")
            progress = data["progress"]
            if progress.get("current_page"):
                logger.info(
                    "    Posisi progress: halaman %s | komik %s | state=%s",
                    _format_page_progress(progress),
                    _format_comic_progress(progress),
                    progress.get("state", "unknown"),
                )
            return data
        except (json.JSONDecodeError, KeyError) as e:
            logger.warning(f"⚠️ Checkpoint rusak, akan mulai dari awal: {e}")
    elif LEGACY_CHECKPOINT_FILE.exists():
        logger.info(
            f"ℹ️ Checkpoint legacy terdeteksi di {LEGACY_CHECKPOINT_FILE}, "
            f"tetapi diabaikan karena checkpoint kini dipisah per mode. "
            f"Menggunakan file aktif: {checkpoint_file}"
        )
    return _normalize_checkpoint(None)


def save_checkpoint(checkpoint: dict, checkpoint_file: Path) -> None:
    """Simpan checkpoint ke file JSON."""
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint["updated_at"] = now_wib().isoformat()
    with open(checkpoint_file, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)
    logger.debug("💾 Checkpoint tersimpan.")


def reset_checkpoint(mode: str, source_name: str) -> None:
    """Hapus file checkpoint untuk mode aktif."""
    checkpoint_file = get_checkpoint_file(mode, source_name)
    if checkpoint_file.exists():
        checkpoint_file.unlink()
        logger.info(f"🗑️ Checkpoint {source_name}:{mode} dihapus: {checkpoint_file}")
    else:
        logger.info(f"ℹ️ Tidak ada checkpoint {source_name}:{mode} yang perlu dihapus.")

    if LEGACY_CHECKPOINT_FILE.exists():
        LEGACY_CHECKPOINT_FILE.unlink()
        logger.info(f"🧹 Checkpoint legacy juga dihapus: {LEGACY_CHECKPOINT_FILE}")


# ═══════════════════════════════════════════════════════════════════
# DELAY & BACKOFF HELPERS
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


@dataclass
class SyncRuntime:
    """State runtime yang dipakai lintas fase sync."""

    checkpoint: dict
    checkpoint_file: Path
    mode: str
    stats: dict
    completed_slugs: set[str]
    comics_since_cooldown: int = 0


def persist_runtime_checkpoint(runtime: SyncRuntime, **progress_kwargs) -> dict:
    """Persist checkpoint dengan state runtime aktif."""
    return persist_checkpoint_state(
        runtime.checkpoint,
        checkpoint_file=runtime.checkpoint_file,
        stats=runtime.stats,
        completed_slugs=runtime.completed_slugs,
        mode=runtime.mode,
        **progress_kwargs,
    )


async def save_chapter_metadata(
    session,
    *,
    comic_id: int,
    chapters_data: list[dict[str, Any]],
) -> int:
    """Simpan metadata chapter tanpa fetch images."""
    ch_saved = 0

    for ch_data in chapters_data:
        ch_num = ch_data.get("chapter_number", 0)
        ch_url = ch_data.get("source_url", "")
        if not ch_url:
            continue

        stmt = pg_insert(Chapter).values(
            comic_id=comic_id,
            chapter_number=ch_num,
            title=ch_data.get("title"),
            source_url=ch_url,
            release_date=ch_data.get("release_date"),
            created_at=now_wib(),
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

    if ch_saved:
        await session.commit()

    return ch_saved


async def process_comic(
    session,
    scraper: BaseComicScraper,
    runtime: SyncRuntime,
    comic_basic: dict[str, Any],
    *,
    page: int,
    idx: int,
    page_total: int,
    existing_db_slugs: set[str],
    resume_page: int,
    resume_comic_index: int,
    consecutive_errors: int,
) -> tuple[int, bool]:
    """Proses satu komik: skip, fetch detail, upsert, lalu simpan chapter."""
    if page == resume_page and idx <= resume_comic_index:
        return consecutive_errors, False

    slug = comic_basic.get("slug", "")
    title = comic_basic.get("title", "???")
    detail_url = comic_basic.get("source_url", "")

    if slug and slug in runtime.completed_slugs:
        logger.info(f"  ⏭️ [{idx + 1}/{page_total}] Skip (sudah done): {title}")
        runtime.stats["total_skipped"] += 1
        return consecutive_errors, False

    if slug and slug in existing_db_slugs:
        runtime.completed_slugs.add(slug)
        runtime.stats["total_skipped"] += 1
        logger.info(f"  ⏭️ [{idx + 1}/{page_total}] Skip (sudah ada di DB): {title}")
        persist_runtime_checkpoint(
            runtime,
            last_completed_page=page,
            last_comic_index=idx,
            current_page=page,
            page_comics_total=page_total,
            current_comic_index=idx,
            current_comic_title=title,
            current_comic_slug=slug,
            current_comic_url=detail_url,
            state="comic-skipped-db",
            note=f"Skip DB [{idx + 1}/{page_total}]",
        )
        return consecutive_errors, False

    if not detail_url:
        logger.warning(f"  ⏭️ [{idx + 1}/{page_total}] Skip (no URL): {title}")
        return consecutive_errors, False

    logger.info(f"  📖 [{idx + 1}/{page_total}] Mengambil detail: {title}")
    persist_runtime_checkpoint(
        runtime,
        current_page=page,
        page_comics_total=page_total,
        current_comic_index=idx,
        current_comic_title=title,
        current_comic_slug=slug,
        current_comic_url=detail_url,
        state="fetching-comic-detail",
        note=f"Mengambil detail komik [{idx + 1}/{page_total}]",
    )

    await random_delay(DELAY_DETAIL_MIN, DELAY_DETAIL_MAX, "delay pre-detail")

    try:
        comic_detail = await scraper.get_comic_detail(detail_url)

        if not comic_detail.get("title"):
            logger.warning(f"  ⚠️ Tidak ada title di detail, skip: {title}")
            runtime.stats["total_errors"] += 1
            return consecutive_errors, False

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

        comic_id = await upsert_comic(session, validated)

        for genre_name in validated.genres:
            genre_id = await upsert_genre(session, genre_name)
            genre_link = pg_insert(comic_genre).values(
                comic_id=comic_id,
                genre_id=genre_id,
            )
            genre_link = genre_link.on_conflict_do_nothing()
            await session.execute(genre_link)

        await session.commit()

        runtime.stats["total_upserted"] += 1
        runtime.comics_since_cooldown += 1
        consecutive_errors = 0

        logger.info(
            f"  ✅ Upserted: {validated.title} "
            f"({len(validated.genres)} genre) "
            f"[Total: {runtime.stats['total_upserted']}]"
        )

        persist_runtime_checkpoint(
            runtime,
            current_page=page,
            page_comics_total=page_total,
            current_comic_index=idx,
            current_comic_title=validated.title,
            current_comic_slug=validated.slug,
            current_comic_url=detail_url,
            state="saving-chapter-metadata",
            note=f"Menyimpan chapter [{idx + 1}/{page_total}]",
        )

        chapters_data = comic_detail.get("chapters", [])
        ch_saved = await save_chapter_metadata(
            session,
            comic_id=comic_id,
            chapters_data=chapters_data,
        )
        if ch_saved:
            runtime.stats["total_chapters_saved"] += ch_saved
            logger.info(
                f"    📚 {ch_saved} chapter metadata tersimpan "
                f"(images akan di-fetch on-demand)"
            )
        else:
            logger.info("    ℹ️ Tidak ada daftar chapter dari detail page.")

        runtime.completed_slugs.add(validated.slug)
        persist_runtime_checkpoint(
            runtime,
            last_completed_page=page,
            last_comic_index=idx,
            current_page=page,
            page_comics_total=page_total,
            current_comic_index=idx,
            current_comic_title=validated.title,
            current_comic_slug=validated.slug,
            current_comic_url=detail_url,
            state="comic-complete",
            note=f"Komik selesai [{idx + 1}/{page_total}]",
        )

        if runtime.comics_since_cooldown >= COOLDOWN_EVERY_N_COMICS:
            runtime.comics_since_cooldown = 0
            logger.info(
                f"\n  🧊 Cooldown berkala ({COOLDOWN_EVERY_N_COMICS} komik tercapai)..."
            )
            await random_delay(COOLDOWN_MIN, COOLDOWN_MAX, "cooldown berkala")

        await random_delay(DELAY_COMIC_MIN, DELAY_COMIC_MAX, "delay antar-komik")
        return consecutive_errors, False

    except Exception as e:
        consecutive_errors += 1
        runtime.stats["total_errors"] += 1
        logger.error(
            f"  ✗ Error [{consecutive_errors}/{MAX_CONSECUTIVE_ERRORS}] pada {title}: {e}"
        )
        await session.rollback()

        persist_runtime_checkpoint(
            runtime,
            last_completed_page=page,
            last_comic_index=idx,
            current_page=page,
            page_comics_total=page_total,
            current_comic_index=idx,
            current_comic_title=title,
            current_comic_slug=slug,
            current_comic_url=detail_url,
            state="comic-error",
            note=f"Error saat memproses komik [{idx + 1}/{page_total}]",
        )

        if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
            logger.error(
                f"  ⛔ {MAX_CONSECUTIVE_ERRORS} error berturut-turut! "
                f"Skip sisa halaman {page}."
            )
            return consecutive_errors, True

        await backoff_delay(consecutive_errors, f"error pada {title}")
        return consecutive_errors, False


async def process_page(
    session,
    scraper: BaseComicScraper,
    runtime: SyncRuntime,
    *,
    page: int,
    end_page: int,
    resume_page: int,
    resume_comic_index: int,
) -> bool:
    """Proses satu halaman daftar komik sampai seluruh item selesai."""
    logger.info(f"{'─' * 60}")
    logger.info(f"📄 Halaman {page}/{end_page}")
    logger.info(f"{'─' * 60}")

    persist_runtime_checkpoint(
        runtime,
        current_page=page,
        page_comics_total=0,
        current_comic_index=-1,
        state="fetching-page",
        note=f"Mengambil daftar komik untuk halaman {page}",
    )

    comics_list = None
    for attempt in range(3):
        try:
            comics_list = await scraper.get_comic_list(page=page)
            break
        except Exception as e:
            logger.error(f"  ✗ Gagal fetch halaman {page} (attempt {attempt + 1}): {e}")
            await backoff_delay(attempt, f"retry halaman {page}")

    if not comics_list:
        logger.warning(
            f"  ⚠️ Tidak ada komik ditemukan di halaman {page}. "
            f"Kemungkinan sudah akhir daftar."
        )
        persist_runtime_checkpoint(
            runtime,
            last_completed_page=page,
            last_comic_index=-1,
            current_page=page,
            page_comics_total=0,
            current_comic_index=-1,
            state="page-empty",
            note=f"Halaman {page} kosong atau sudah akhir daftar",
        )
        return False

    page_total = len(comics_list)
    logger.info(f"  📋 Ditemukan {page_total} komik di halaman {page}")
    persist_runtime_checkpoint(
        runtime,
        current_page=page,
        page_comics_total=page_total,
        current_comic_index=-1,
        state="page-loaded",
        note=f"Halaman {page} siap diproses ({page_total} komik)",
    )

    existing_db_slugs = set()
    if runtime.mode == "validate":
        existing_db_slugs = await get_existing_comic_slugs(
            session,
            source_name=scraper.SOURCE_NAME,
            slugs=[comic.get("slug", "") for comic in comics_list],
        )
    if existing_db_slugs:
        logger.info(
            f"  🗃️ {len(existing_db_slugs)} komik di halaman {page} sudah ada di database"
        )

    consecutive_errors = 0
    for idx, comic_basic in enumerate(comics_list):
        if _shutdown_requested:
            break

        consecutive_errors, stop_page = await process_comic(
            session,
            scraper,
            runtime,
            comic_basic,
            page=page,
            idx=idx,
            page_total=page_total,
            existing_db_slugs=existing_db_slugs,
            resume_page=resume_page,
            resume_comic_index=resume_comic_index,
            consecutive_errors=consecutive_errors,
        )
        if stop_page:
            break

    if not _shutdown_requested:
        logger.info(f"\n  ✅ Halaman {page} selesai.")
        persist_runtime_checkpoint(
            runtime,
            last_completed_page=page,
            last_comic_index=-1,
            current_page=page,
            page_comics_total=page_total,
            current_comic_index=-1,
            state="page-complete",
            note=f"Halaman {page} selesai",
        )

        if page < end_page:
            await random_delay(DELAY_PAGE_MIN, DELAY_PAGE_MAX, "delay antar-halaman")

    return True


async def run_sync_full_library(
    start_page: int,
    max_pages: int,
    end_page: int | None = None,
    mode: str = "validate",
    source: str = "komiku",
):
    """Pipeline utama mass-scraping dengan semua strategi anti-blocking."""
    global _shutdown_requested

    start_time = time.time()
    started_at = now_wib()
    checkpoint_file = get_checkpoint_file(mode, source)
    checkpoint = load_checkpoint(mode, source)
    completed_slugs = set(checkpoint.get("completed_slugs", []))
    stats = _default_stats()
    stats.update(checkpoint.get("stats", {}))

    end_page = resolve_target_end_page(
        start_page=start_page,
        max_pages=max_pages,
        end_page=end_page,
    )
    resume_page, resume_comic_index, resume_reason = resolve_resume_position(
        checkpoint=checkpoint,
        mode=mode,
        start_page=start_page,
        end_page=end_page,
    )
    if resume_reason in {"checkpoint-ignored-outside-range", "checkpoint-ignored-mode-mismatch"}:
        completed_slugs = set()
        stats = _default_stats()
    progress_page = min(resume_page, end_page) if end_page >= start_page else start_page

    runtime = SyncRuntime(
        checkpoint=checkpoint,
        checkpoint_file=checkpoint_file,
        mode=mode,
        stats=stats,
        completed_slugs=completed_slugs,
    )

    persist_runtime_checkpoint(
        runtime,
        target_start_page=start_page,
        target_end_page=end_page,
        current_page=progress_page,
        current_comic_index=resume_comic_index,
        state="starting",
        note=f"Sync full library dimulai ({resume_reason})",
    )

    logger.info("═" * 60)
    logger.info(f"🚀 Sync Full Library dimulai — {started_at.isoformat()}")
    logger.info(f"   Source          : {source}")
    logger.info(f"   Mode          : {mode}")
    logger.info(f"   Target halaman  : {start_page} → {end_page}")
    logger.info(f"   Resume dari     : halaman {resume_page}, komik index > {resume_comic_index}")
    logger.info(f"   Resume reason   : {resume_reason}")
    logger.info(f"   Komik sudah done: {len(completed_slugs)}")
    logger.info(f"   Checkpoint scope: {get_checkpoint_scope_label(mode, source)}")
    logger.info(f"   Delay komik     : {DELAY_COMIC_MIN}-{DELAY_COMIC_MAX}s (random)")
    logger.info(f"   Delay halaman   : {DELAY_PAGE_MIN}-{DELAY_PAGE_MAX}s (random)")
    logger.info(f"   Cooldown setiap : {COOLDOWN_EVERY_N_COMICS} komik")
    logger.info(f"   Checkpoint file : {checkpoint_file}")
    logger.info("═" * 60)

    # Inisialisasi scraper
    scraper = create_scraper(source)
    logger.info(f"   Base URL        : {scraper.BASE_URL}")

    async with async_session() as session:
        for page in range(resume_page, end_page + 1):
            if _shutdown_requested:
                break
            should_continue = await process_page(
                session,
                scraper,
                runtime,
                page=page,
                end_page=end_page,
                resume_page=resume_page,
                resume_comic_index=resume_comic_index,
            )
            if not should_continue:
                break

    # ═══════════════════════════════════════════════════════════════
    # RINGKASAN
    # ═══════════════════════════════════════════════════════════════
    elapsed = time.time() - start_time
    finished_at = now_wib()
    final_state = "stopped-by-user" if _shutdown_requested else "finished"
    final_note = "Sync dihentikan oleh user" if _shutdown_requested else "Sync full library selesai"
    progress = persist_runtime_checkpoint(
        runtime,
        state=final_state,
        note=final_note,
    )

    logger.info("═" * 60)
    if _shutdown_requested:
        logger.info("🛑 Sync dihentikan oleh user (Ctrl+C).")
    else:
        logger.info("🏁 Sync Full Library selesai!")
    logger.info(f"   Mulai       : {started_at.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"   Selesai     : {finished_at.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"   Waktu       : {_format_elapsed_duration(elapsed)}")
    logger.info(f"   Mode        : {mode}")
    logger.info(f"   Upserted    : {runtime.stats['total_upserted']} komik")
    logger.info(f"   Chapters    : {runtime.stats['total_chapters_saved']} chapter metadata tersimpan")
    logger.info(f"   Skipped     : {runtime.stats['total_skipped']} komik (sudah ada)")
    logger.info(f"   Errors      : {runtime.stats['total_errors']}")
    logger.info(f"   Posisi page : {_format_page_progress(progress)}")
    logger.info(f"   Fetch comic : {_format_comic_progress(progress)}")
    logger.info(f"   State       : {progress.get('state', '-')}")
    logger.info(f"   Catatan     : {progress.get('note') or '-'}")
    logger.info(f"   Checkpoint  : {checkpoint_file}")
    logger.info("═" * 60)


# ═══════════════════════════════════════════════════════════════════
# CLI HELPERS & ENTRY POINT
# ═══════════════════════════════════════════════════════════════════


def parse_args():
    """Parse argumen command-line sederhana (tanpa argparse agar ringan)."""
    args = {
        "source": "komiku",
        "start": DEFAULT_START_PAGE,
        "max": DEFAULT_MAX_PAGES,
        "end": None,
        "mode": "validate",
        "reset": False,
        "log_file": str(DEFAULT_LOG_FILE),
    }
    max_explicitly_set = False

    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--reset":
            args["reset"] = True
        elif argv[i] == "--source" and i + 1 < len(argv):
            args["source"] = argv[i + 1].lower()
            i += 1
        elif argv[i] == "--start" and i + 1 < len(argv):
            args["start"] = int(argv[i + 1])
            i += 1
        elif argv[i] == "--max" and i + 1 < len(argv):
            args["max"] = int(argv[i + 1])
            max_explicitly_set = True
            i += 1
        elif argv[i] == "--end" and i + 1 < len(argv):
            args["end"] = int(argv[i + 1])
            i += 1
        elif argv[i] == "--mode" and i + 1 < len(argv):
            args["mode"] = argv[i + 1].lower()
            i += 1
        elif argv[i] == "--log-file" and i + 1 < len(argv):
            args["log_file"] = argv[i + 1]
            i += 1
        elif argv[i] == "--help":
            print(__doc__)
            sys.exit(0)
        i += 1

    if max_explicitly_set and args["end"] is not None:
        raise ValueError("Gunakan salah satu: --max untuk jumlah halaman atau --end untuk halaman akhir, bukan keduanya sekaligus.")
    if args["mode"] not in SUPPORTED_MODES:
        raise ValueError(
            f"--mode harus salah satu dari: {', '.join(sorted(SUPPORTED_MODES))}"
        )
    if args["source"] not in SUPPORTED_SOURCES:
        raise ValueError(
            f"--source harus salah satu dari: {', '.join(SUPPORTED_SOURCES)}"
        )
    if "--log-file" in argv and not args["log_file"]:
        raise ValueError("--log-file membutuhkan path file, misalnya --log-file sync.log")

    return args


def main():
    """Entry point."""
    try:
        args = parse_args()
    except ValueError as e:
        print(f"Error argumen: {e}")
        print("Gunakan --help untuk melihat contoh penggunaan.")
        sys.exit(1)

    configure_logging(args["log_file"])

    # Daftarkan signal handler untuk graceful shutdown
    signal.signal(signal.SIGINT, _signal_handler)
    # SIGTERM biasanya tidak tersedia di Windows, tapi kita coba
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _signal_handler)

    if args["reset"]:
        reset_checkpoint(args["mode"], args["source"])

    try:
        asyncio.run(run_sync_full_library(
            source=args["source"],
            start_page=args["start"],
            max_pages=args["max"],
            end_page=args["end"],
            mode=args["mode"],
        ))
    except ValueError as e:
        print(f"Error konfigurasi sync: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
