"""
Tonztoon Komik — Sync Chapter Images Backfill

Script khusus untuk mengisi `chapters.images` secara bertahap tanpa
mengganggu alur `sync_full_library` dan `scraper.main`.

Latar belakang arsitektur:
- `sync_full_library` menyimpan comic + chapter metadata saja.
- `scraper.main` melakukan pre-warm images untuk beberapa chapter terbaru.
- Chapter lama atau backlog yang masih `images=NULL` / `[]` dibackfill lewat
  script ini secara terpisah agar proses sync utama tetap cepat.

Mode operasi:
- Script ini berjalan sebagai batch `once`.
- Dipakai untuk backfill lokal sekali jalan atau batch terjadwal via
  GitHub Actions.
- Script mengambil chapter backlog dalam jumlah tertentu (`--limit`) lalu
  selesai.
- Jika backlog masih tersisa, jalankan lagi pada cron/run berikutnya.

Strategi pemilihan chapter:
- `--selection ordered`
  - Memproses backlog berdasarkan `Chapter.id` naik.
  - Cocok untuk backfill deterministik dan progres yang mudah dipantau.
  - Checkpoint `last_processed_chapter_id` dipakai untuk resume dari posisi
    terakhir; jika sudah mencapai ujung backlog, script akan wrap ke awal.
- `--selection random`
  - Memproses backlog secara acak.
  - Cocok untuk workload background agar beban menyebar antar comic/source
    dan tidak selalu menghajar area backlog yang berurutan.

Strategi anti-blocking:
- per chapter commit
- delay acak antar request
- cooldown berkala setelah sejumlah chapter sukses diproses
- exponential backoff saat error berturut-turut
- checkpoint ringan untuk resume statistik / posisi terakhir mode ordered

Checkpoint:
- File checkpoint dipisahkan per `source`.
- Contoh:
  - `data/sync_chapter_images_komikcast.json`
  - `data/sync_chapter_images_all.json`
- `--reset` akan menghapus checkpoint aktif agar proses dimulai dari awal.

Perilaku saat backlog kosong:
- log "tidak ada backlog", lalu exit bersih

Kriteria backlog:
- Chapter dianggap pending jika:
  - `Chapter.images IS NULL`, atau
  - `Chapter.images = []`

Usage:
    cd backend
    python -m scraper.sync_chapter_images
    python -m scraper.sync_chapter_images --source komiku_asia
    python -m scraper.sync_chapter_images --source komikcast --limit 50
    python -m scraper.sync_chapter_images --source shinigami --selection random --limit 20

Argumen CLI utama:
- `--source <source_name>`
  - Filter source tertentu saja.
  - Nilai valid mengikuti registry backend: `komiku`, `komiku_asia`,
    `komikcast`, `shinigami`.
  - Jika tidak diisi, script akan mengambil backlog dari semua source aktif.
- `--selection <ordered|random>`
  - `ordered`: proses backlog berdasarkan `Chapter.id` naik.
  - `random`: proses backlog acak, cocok untuk background sweep.
  - Default: `ordered`.
- `--batch-size <N>`
  - Jumlah chapter yang diambil per batch query ke database.
  - Default: `10`.
- `--limit <N>`
  - Batas maksimum chapter yang diproses dalam satu run.
  - `0` berarti tidak dibatasi oleh budget run; script akan terus mengambil
    batch sampai backlog habis atau proses dihentikan manual.
  - Default: `0`.
- `--reset`
  - Hapus checkpoint aktif lebih dulu sebelum run dimulai.
- `--log-file <path>`
  - Ubah lokasi file log. Jika relatif, file akan disimpan di `backend/logs/`.
  - Default tanpa flag akan menjadi `sync_chapter_images_<source>.log`.

Contoh use case:
- Batch lokal fokus source tertentu:
  `python -m scraper.sync_chapter_images --source komikcast --limit 30`
- Batch lokal deterministik dari semua source:
  `python -m scraper.sync_chapter_images --selection ordered --batch-size 20 --limit 100`
- Cron GitHub Actions sekali jalan:
  `python -m scraper.sync_chapter_images --selection random --batch-size 10 --limit 20`
- Ulang dari awal tanpa memakai checkpoint lama:
  `python -m scraper.sync_chapter_images --source shinigami --reset --limit 40`

Panduan pemakaian singkat:
- Gunakan script ini untuk:
  - backfill lokal manual
  - batch job GitHub Actions
  - pekerjaan sweep yang harus selesai lalu exit
- Gunakan `ordered` saat ingin progres mudah diaudit.
- Gunakan `random` saat ingin beban fetch lebih tersebar.
"""

import asyncio
import json
import logging
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import Select, case, func, or_, select
from sqlalchemy.dialects.postgresql import JSONPATH
from sqlalchemy.sql import cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Chapter, Comic
from app.services.chapter_service import (
    ImageFetchError,
    chapter_images_are_ready,
    fetch_and_save_chapter_images,
)
from scraper.sources.registry import get_supported_source_names
from scraper.time_utils import now_wib
from scraper.utils import (
    GracefulShutdown,
    backoff_delay,
    configure_logging as _configure_logging_base,
    format_elapsed_duration,
    random_delay,
    resolve_log_path as _resolve_log_path_base,
)

DEFAULT_LOG_FILE = Path("sync_chapter_images.log")
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "data"

SUPPORTED_SOURCES = tuple(get_supported_source_names())
SUPPORTED_SELECTIONS = {"ordered", "random"}

DELAY_CHAPTER_MIN = 2.0
DELAY_CHAPTER_MAX = 5.0
COOLDOWN_EVERY_N_CHAPTERS = 10
COOLDOWN_MIN = 10.0
COOLDOWN_MAX = 20.0
BACKOFF_MAX = 120.0
MAX_CONSECUTIVE_ERRORS = 5
IMAGE_FETCH_TIMEOUT = 25.0
CHAPTER_IMAGES_ADVISORY_LOCK_NAMESPACE = 41021
INVALID_IMAGES_JSONPATH = cast(
    '$[*] ? (!exists(@.page) || !exists(@.url) || @.url == "")',
    JSONPATH,
)

_shutdown = GracefulShutdown()
_shutdown.install()


def _build_default_log_filename(*, source_name: str | None) -> Path:
    """Nama file log default yang dipisah per source."""
    scope = source_name or "all"
    return Path(f"sync_chapter_images_{scope}.log")


def resolve_log_path(
    log_file: str | None,
    *,
    source_name: str | None = None,
) -> Path:
    filename = log_file or str(_build_default_log_filename(source_name=source_name))
    return _resolve_log_path_base(filename)


def configure_logging(
    log_file: str | None = None,
    *,
    source_name: str | None = None,
) -> None:
    filename = log_file or str(_build_default_log_filename(source_name=source_name))
    _configure_logging_base(filename, default_filename=str(DEFAULT_LOG_FILE))

logger = logging.getLogger("sync-chapter-images")


def get_checkpoint_file(source_name: str | None) -> Path:
    scope = source_name or "all"
    return CHECKPOINT_DIR / f"sync_chapter_images_{scope}.json"


def _default_stats() -> dict:
    return {
        "total_batches": 0,
        "total_scanned": 0,
        "total_fetched": 0,
        "total_skipped": 0,
        "total_errors": 0,
    }


def _default_progress() -> dict:
    return {
        "source": None,
        "selection": None,
        "batch_size": 0,
        "limit": 0,
        "current_pending_total": 0,
        "current_batch_number": 0,
        "current_batch_size": 0,
        "current_chapter_id": 0,
        "current_chapter_position": 0,
        "current_chapter_total": 0,
        "current_source_name": None,
        "current_comic_title": None,
        "current_chapter_number": None,
        "current_chapter_url": None,
        "state": "idle",
        "note": None,
    }


def _default_checkpoint() -> dict:
    return {
        "last_processed_chapter_id": 0,
        "updated_at": None,
        "stats": _default_stats(),
        "progress": _default_progress(),
    }


def _normalize_checkpoint(data: dict | None) -> dict:
    checkpoint = data or {}
    checkpoint.setdefault("last_processed_chapter_id", 0)
    checkpoint.setdefault("updated_at", None)

    default_stats = _default_stats()
    stats = checkpoint.setdefault("stats", default_stats.copy())
    for key, value in default_stats.items():
        stats.setdefault(key, value)

    default_progress = _default_progress()
    progress = checkpoint.setdefault("progress", default_progress.copy())
    for key, value in default_progress.items():
        progress.setdefault(key, value)

    if progress["current_chapter_id"] == 0 and checkpoint["last_processed_chapter_id"] > 0:
        progress["current_chapter_id"] = checkpoint["last_processed_chapter_id"]

    return checkpoint


def update_progress(
    checkpoint: dict,
    *,
    source: str | None = None,
    selection: str | None = None,
    batch_size: int | None = None,
    limit: int | None = None,
    current_pending_total: int | None = None,
    current_batch_number: int | None = None,
    current_batch_size: int | None = None,
    current_chapter_id: int | None = None,
    current_chapter_position: int | None = None,
    current_chapter_total: int | None = None,
    current_source_name: str | None = None,
    current_comic_title: str | None = None,
    current_chapter_number: float | None = None,
    current_chapter_url: str | None = None,
    state: str | None = None,
    note: str | None = None,
) -> dict:
    progress = checkpoint.setdefault("progress", _default_progress())

    if source is not None:
        progress["source"] = source
    if selection is not None:
        progress["selection"] = selection
    if batch_size is not None:
        progress["batch_size"] = batch_size
    if limit is not None:
        progress["limit"] = limit
    if current_pending_total is not None:
        progress["current_pending_total"] = current_pending_total
    if current_batch_number is not None:
        progress["current_batch_number"] = current_batch_number
    if current_batch_size is not None:
        progress["current_batch_size"] = current_batch_size
    if current_chapter_id is not None:
        progress["current_chapter_id"] = current_chapter_id
    if current_chapter_position is not None:
        progress["current_chapter_position"] = current_chapter_position
    if current_chapter_total is not None:
        progress["current_chapter_total"] = current_chapter_total
    if current_source_name is not None:
        progress["current_source_name"] = current_source_name
    if current_comic_title is not None:
        progress["current_comic_title"] = current_comic_title
    if current_chapter_number is not None:
        progress["current_chapter_number"] = current_chapter_number
    if current_chapter_url is not None:
        progress["current_chapter_url"] = current_chapter_url
    if state is not None:
        progress["state"] = state
    if note is not None:
        progress["note"] = note

    return progress


def load_checkpoint(source_name: str | None) -> dict:
    checkpoint_file = get_checkpoint_file(source_name)
    if not checkpoint_file.exists():
        return _default_checkpoint()
    try:
        with open(checkpoint_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        checkpoint = _normalize_checkpoint(data)
        logger.info("📂 Checkpoint ditemukan: %s", checkpoint_file)
        return checkpoint
    except Exception as exc:
        logger.warning("⚠️ Checkpoint rusak, mulai baru: %s", exc)
        return _default_checkpoint()


def save_checkpoint(source_name: str | None, checkpoint: dict) -> None:
    checkpoint_file = get_checkpoint_file(source_name)
    checkpoint["updated_at"] = now_wib().isoformat()
    checkpoint_file.parent.mkdir(parents=True, exist_ok=True)
    with open(checkpoint_file, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)


def reset_checkpoint(source_name: str | None) -> None:
    checkpoint_file = get_checkpoint_file(source_name)
    if checkpoint_file.exists():
        checkpoint_file.unlink()
        logger.info("🗑️ Checkpoint dihapus: %s", checkpoint_file)


# random_delay, backoff_delay, format_elapsed_duration telah dipindahkan ke scraper.utils


@dataclass
class ImageSyncStats:
    total_batches: int = 0
    total_scanned: int = 0
    total_fetched: int = 0
    total_skipped: int = 0
    total_errors: int = 0
    processed_since_cooldown: int = 0


def _build_pending_query(
    *,
    source_name: str | None,
    selection: str,
    last_processed_chapter_id: int,
    limit: int,
) -> Select:
    invalid_images = case(
        (Chapter.images.is_(None), True),
        (func.jsonb_typeof(Chapter.images) != "array", True),
        else_=or_(
            func.jsonb_array_length(Chapter.images) == 0,
            func.jsonb_path_exists(
                Chapter.images,
                INVALID_IMAGES_JSONPATH,
            ),
        ),
    )

    stmt = (
        select(Chapter, Comic.source_name, Comic.title)
        .join(Comic, Comic.id == Chapter.comic_id)
        .where(invalid_images)
    )
    if source_name:
        stmt = stmt.where(Comic.source_name == source_name)

    if selection == "ordered":
        stmt = stmt.where(Chapter.id > last_processed_chapter_id).order_by(Chapter.id.asc())
    else:
        stmt = stmt.order_by(func.random())

    return stmt.limit(limit)


async def _load_pending_batch(
    *,
    source_name: str | None,
    selection: str,
    last_processed_chapter_id: int,
    limit: int,
):
    async with async_session() as session:
        result = await session.execute(
            _build_pending_query(
                source_name=source_name,
                selection=selection,
                last_processed_chapter_id=last_processed_chapter_id,
                limit=limit,
            )
        )
        rows = result.all()

        if selection == "ordered" and not rows and last_processed_chapter_id > 0:
            result = await session.execute(
                _build_pending_query(
                    source_name=source_name,
                    selection=selection,
                    last_processed_chapter_id=0,
                    limit=limit,
                )
            )
            rows = result.all()

        return rows


async def _count_pending(*, source_name: str | None) -> int:
    async with async_session() as session:
        invalid_images = case(
            (Chapter.images.is_(None), True),
            (func.jsonb_typeof(Chapter.images) != "array", True),
            else_=or_(
                func.jsonb_array_length(Chapter.images) == 0,
                func.jsonb_path_exists(
                    Chapter.images,
                    INVALID_IMAGES_JSONPATH,
                ),
            ),
        )
        stmt = (
            select(func.count())
            .select_from(Chapter)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(invalid_images)
        )
        if source_name:
            stmt = stmt.where(Comic.source_name == source_name)
        result = await session.execute(stmt)
        return int(result.scalar_one() or 0)


async def _try_claim_chapter(session, chapter_id: int) -> bool:
    result = await session.execute(
        select(func.pg_try_advisory_lock(CHAPTER_IMAGES_ADVISORY_LOCK_NAMESPACE, chapter_id))
    )
    return bool(result.scalar())


async def _release_claim(session, chapter_id: int) -> None:
    await session.execute(
        select(func.pg_advisory_unlock(CHAPTER_IMAGES_ADVISORY_LOCK_NAMESPACE, chapter_id))
    )


async def process_pending_images_batch(
    *,
    batch_number: int,
    pending_total: int,
    source_name: str | None,
    selection: str,
    batch_size: int,
    checkpoint: dict,
    stats: ImageSyncStats,
) -> int:
    rows = await _load_pending_batch(
        source_name=source_name,
        selection=selection,
        last_processed_chapter_id=int(checkpoint.get("last_processed_chapter_id", 0) or 0),
        limit=batch_size,
    )
    if not rows:
        logger.info("ℹ️ Tidak ada chapter backlog tanpa images untuk batch ini.")
        return 0

    logger.info(f"{'─' * 60}")
    logger.info(
        "🖼️ Batch %s — %s chapter dipilih dari %s pending",
        batch_number,
        len(rows),
        pending_total,
    )
    logger.info(f"{'─' * 60}")
    update_progress(
        checkpoint,
        current_pending_total=pending_total,
        current_batch_number=batch_number,
        current_batch_size=len(rows),
        current_chapter_position=0,
        current_chapter_total=len(rows),
        state="batch-started",
        note=f"Memulai batch {batch_number} ({len(rows)} chapter)",
    )
    save_checkpoint(source_name, checkpoint)

    consecutive_errors = 0
    processed = 0
    fetched_in_batch = 0
    skipped_in_batch = 0
    errors_in_batch = 0
    for idx, (chapter, row_source_name, comic_title) in enumerate(rows, start=1):
        if _shutdown.requested:
            break

        stats.total_scanned += 1
        processed += 1
        checkpoint["last_processed_chapter_id"] = chapter.id
        update_progress(
            checkpoint,
            current_chapter_id=chapter.id,
            current_chapter_position=idx,
            current_chapter_total=len(rows),
            current_source_name=row_source_name,
            current_comic_title=comic_title or f"comic_id={chapter.comic_id}",
            current_chapter_number=chapter.chapter_number,
            current_chapter_url=chapter.source_url,
            state="fetching-chapter-images",
            note=f"Memproses chapter [{idx}/{len(rows)}] pada batch {batch_number}",
        )

        logger.info(
            "  🖼️ [%s/%s] [%s] %s — Ch %s (chapter_id=%s)",
            idx,
            len(rows),
            row_source_name,
            comic_title or f"comic_id={chapter.comic_id}",
            chapter.chapter_number,
            chapter.id,
        )

        async with async_session() as session:
            try:
                claimed = await _try_claim_chapter(session, chapter.id)
                if not claimed:
                    stats.total_skipped += 1
                    skipped_in_batch += 1
                    logger.info("    ⏭️ Sedang diproses job/proses lain, skip.")
                    update_progress(
                        checkpoint,
                        state="chapter-skipped-claimed",
                        note=f"Chapter {chapter.id} sedang diproses proses lain",
                    )
                    continue

                chapter_in_session = await session.get(Chapter, chapter.id)
                if chapter_in_session is None:
                    stats.total_skipped += 1
                    skipped_in_batch += 1
                    update_progress(
                        checkpoint,
                        state="chapter-skipped-missing",
                        note=f"Chapter {chapter.id} tidak ditemukan saat reload session",
                    )
                    continue

                if chapter_images_are_ready(chapter_in_session.images):
                    stats.total_skipped += 1
                    skipped_in_batch += 1
                    logger.info("    ⏭️ Sudah punya images valid, skip.")
                    update_progress(
                        checkpoint,
                        state="chapter-skipped-ready",
                        note=f"Chapter {chapter.id} sudah punya images valid",
                    )
                    continue

                ok = await fetch_and_save_chapter_images(
                    chapter=chapter_in_session,
                    source_name=row_source_name,
                    timeout_seconds=IMAGE_FETCH_TIMEOUT,
                    db=session,
                )
                if ok:
                    fetched_in_batch += 1
                    stats.total_fetched += 1
                    stats.processed_since_cooldown += 1
                    consecutive_errors = 0
                    update_progress(
                        checkpoint,
                        state="chapter-complete",
                        note=f"Images chapter {chapter.id} berhasil disimpan",
                    )
                else:
                    skipped_in_batch += 1
                    stats.total_skipped += 1
                    update_progress(
                        checkpoint,
                        state="chapter-no-images",
                        note=f"Tidak ada images ditemukan untuk chapter {chapter.id}",
                    )
            except ImageFetchError as exc:
                consecutive_errors += 1
                errors_in_batch += 1
                stats.total_errors += 1
                logger.warning("    ✗ Gagal fetch images: %s", exc)
                update_progress(
                    checkpoint,
                    state="chapter-error",
                    note=f"Error image fetch chapter {chapter.id}: {exc}",
                )
                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                    await backoff_delay(consecutive_errors - 1, f"{row_source_name} images")
                    consecutive_errors = 0
            except Exception as exc:
                consecutive_errors += 1
                errors_in_batch += 1
                stats.total_errors += 1
                logger.error("    ✗ Error tidak terduga: %s", exc)
                update_progress(
                    checkpoint,
                    state="chapter-error",
                    note=f"Error tidak terduga chapter {chapter.id}: {exc}",
                )
                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                    await backoff_delay(consecutive_errors - 1, f"{row_source_name} images")
                    consecutive_errors = 0
            finally:
                try:
                    await _release_claim(session, chapter.id)
                except Exception:
                    pass

        save_checkpoint(
            source_name,
            {
                **checkpoint,
                "stats": {
                    "total_scanned": stats.total_scanned,
                    "total_fetched": stats.total_fetched,
                    "total_skipped": stats.total_skipped,
                    "total_errors": stats.total_errors,
                },
            },
        )

        if stats.processed_since_cooldown >= COOLDOWN_EVERY_N_CHAPTERS:
            stats.processed_since_cooldown = 0
            logger.info("  🧊 Cooldown berkala images...")
            await random_delay(COOLDOWN_MIN, COOLDOWN_MAX, "cooldown images")

        await random_delay(DELAY_CHAPTER_MIN, DELAY_CHAPTER_MAX, "antar-chapter images")

    logger.info(
        "  ✅ Batch %s selesai: scanned=%s, fetched=%s, skipped=%s, errors=%s",
        batch_number,
        processed,
        fetched_in_batch,
        skipped_in_batch,
        errors_in_batch,
    )
    update_progress(
        checkpoint,
        state="batch-complete",
        note=(
            f"Batch {batch_number} selesai: "
            f"scanned={processed}, fetched={fetched_in_batch}, "
            f"skipped={skipped_in_batch}, errors={errors_in_batch}"
        ),
    )
    save_checkpoint(source_name, checkpoint)
    return processed


async def run_image_backfill(
    *,
    source_name: str | None,
    selection: str,
    batch_size: int,
    limit: int,
    reset: bool,
) -> None:
    start_time = time.time()
    started_at = now_wib()
    checkpoint_file = get_checkpoint_file(source_name)
    if reset:
        reset_checkpoint(source_name)
    checkpoint = load_checkpoint(source_name)
    stats = ImageSyncStats(**checkpoint.get("stats", {}))
    update_progress(
        checkpoint,
        source=source_name or "all",
        selection=selection,
        batch_size=batch_size,
        limit=limit,
        state="starting",
        note="Sync chapter images dimulai",
    )
    save_checkpoint(source_name, checkpoint)

    logger.info("═" * 60)
    logger.info(f"🚀 Sync Chapter Images dimulai — {started_at.isoformat()}")
    logger.info("   Source       : %s", source_name or "all active sources")
    logger.info("   Selection    : %s", selection)
    logger.info("   Batch size   : %s", batch_size)
    logger.info("   Limit        : %s", limit)
    logger.info("   Delay chapter: %s-%ss (random)", DELAY_CHAPTER_MIN, DELAY_CHAPTER_MAX)
    logger.info("   Cooldown     : setiap %s chapter", COOLDOWN_EVERY_N_CHAPTERS)
    logger.info("   Backoff max  : %ss", int(BACKOFF_MAX))
    logger.info("   Checkpoint   : %s", checkpoint_file)
    logger.info("═" * 60)

    remaining_budget = limit if limit > 0 else None
    batch_number = 0
    end_state = "complete"
    end_note = "Sync chapter images selesai"

    while not _shutdown.requested:
        pending_total = await _count_pending(source_name=source_name)
        logger.info("📊 Pending chapter images: %s", pending_total)
        if pending_total == 0:
            logger.info("ℹ️ Tidak ada backlog images. Proses selesai.")
            update_progress(
                checkpoint,
                current_pending_total=0,
                state="idle",
                note="Tidak ada backlog images",
            )
            end_state = "complete"
            end_note = "Tidak ada backlog images"
            break

        current_batch_size = batch_size
        if remaining_budget is not None:
            if remaining_budget <= 0:
                end_state = "budget-exhausted"
                end_note = "Batas --limit tercapai"
                break
            current_batch_size = min(current_batch_size, remaining_budget)

        batch_number += 1
        stats.total_batches = batch_number
        processed = await process_pending_images_batch(
            batch_number=batch_number,
            pending_total=pending_total,
            source_name=source_name,
            selection=selection,
            batch_size=current_batch_size,
            checkpoint=checkpoint,
            stats=stats,
        )
        checkpoint["stats"] = {
            "total_batches": stats.total_batches,
            "total_scanned": stats.total_scanned,
            "total_fetched": stats.total_fetched,
            "total_skipped": stats.total_skipped,
            "total_errors": stats.total_errors,
        }
        save_checkpoint(source_name, checkpoint)

        if remaining_budget is not None:
            remaining_budget -= processed
            if remaining_budget <= 0:
                end_state = "budget-exhausted"
                end_note = "Batas --limit tercapai"
                break

        if processed == 0:
            end_state = "no-progress"
            end_note = "Tidak ada progress baru pada batch terakhir"
            break

    checkpoint["stats"] = {
        "total_batches": stats.total_batches,
        "total_scanned": stats.total_scanned,
        "total_fetched": stats.total_fetched,
        "total_skipped": stats.total_skipped,
        "total_errors": stats.total_errors,
    }
    update_progress(
        checkpoint,
        state="stopped-by-user" if _shutdown.requested else end_state,
        note="Sync dihentikan oleh user" if _shutdown.requested else end_note,
    )
    save_checkpoint(source_name, checkpoint)
    finished_at = now_wib()
    elapsed = time.time() - start_time
    logger.info("═" * 60)
    if _shutdown.requested:
        logger.info("🛑 Sync Chapter Images dihentikan oleh user.")
    else:
        logger.info("🏁 Sync Chapter Images selesai!")
    logger.info("   Mulai       : %s", started_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Selesai     : %s", finished_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Waktu       : %s", format_elapsed_duration(elapsed))
    logger.info("   Batches     : %s", stats.total_batches)
    logger.info(
        "   Scanned     : %s",
        stats.total_scanned,
    )
    logger.info("   Fetched     : %s", stats.total_fetched)
    logger.info("   Skipped     : %s", stats.total_skipped)
    logger.info("   Errors      : %s", stats.total_errors)
    logger.info("   State       : %s", checkpoint.get("progress", {}).get("state", "-"))
    logger.info("   Catatan     : %s", checkpoint.get("progress", {}).get("note") or "-")
    logger.info("   Checkpoint  : %s", checkpoint_file)
    logger.info("═" * 60)


def parse_args(argv: list[str]) -> dict:
    args = {
        "source": None,
        "selection": "ordered",
        "batch_size": 10,
        "limit": 0,
        "reset": False,
        "log_file": None,
    }
    i = 0
    while i < len(argv):
        if argv[i] == "--source" and i + 1 < len(argv):
            args["source"] = argv[i + 1].strip().lower()
            i += 2
        elif argv[i] == "--selection" and i + 1 < len(argv):
            args["selection"] = argv[i + 1].strip().lower()
            i += 2
        elif argv[i] == "--batch-size" and i + 1 < len(argv):
            args["batch_size"] = int(argv[i + 1])
            i += 2
        elif argv[i] == "--limit" and i + 1 < len(argv):
            args["limit"] = int(argv[i + 1])
            i += 2
        elif argv[i] == "--reset":
            args["reset"] = True
            i += 1
        elif argv[i] == "--log-file" and i + 1 < len(argv):
            args["log_file"] = argv[i + 1]
            i += 2
        else:
            i += 1

    if args["source"] and args["source"] not in SUPPORTED_SOURCES:
        raise ValueError(
            f"--source tidak valid. Gunakan salah satu dari: {', '.join(SUPPORTED_SOURCES)}"
        )
    if args["selection"] not in SUPPORTED_SELECTIONS:
        raise ValueError(
            f"--selection tidak valid. Gunakan salah satu dari: {', '.join(sorted(SUPPORTED_SELECTIONS))}"
        )
    if args["batch_size"] < 1:
        raise ValueError("--batch-size harus >= 1")
    if args["limit"] < 0:
        raise ValueError("--limit harus >= 0")

    return args


async def main(argv: list[str] | None = None) -> None:
    argv = list(sys.argv[1:] if argv is None else argv)
    args = parse_args(argv)
    configure_logging(args["log_file"], source_name=args["source"])
    await run_image_backfill(
        source_name=args["source"],
        selection=args["selection"],
        batch_size=args["batch_size"],
        limit=args["limit"],
        reset=args["reset"],
    )


if __name__ == "__main__":
    asyncio.run(main())
