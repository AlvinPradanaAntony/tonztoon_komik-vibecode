"""
Tonztoon Komik — Refresh Komikcast Cover URLs

Komikcast cover images are short-lived signed MinIO/S3 URLs. This script
refreshes `comics.cover_image_url` for source `komikcast` by resolving the
latest `coverImage` from the Komikcast JSON API.

Mode operasi:
- Batch once, cocok untuk lokal manual atau cron.
- Resume memakai checkpoint `backend/checkpoints/refresh_komikcast_cover_urls.json`.
- Per comic commit, delay anti-blocking, cooldown berkala, dan backoff saat error.
- Dry-run tidak menyimpan DB dan tidak menulis checkpoint.

Fitur
- Logger real-time dengan warna yang bagus
- Graceful shutdown dengan Ctrl+C
- Resume dari checkpoint
- Handle error gracefully
- Strategi Antiblocking (backoff,delay,cooldown,proxy,delay per cover)
- Summary statistics


Usage:
    cd backend
    python -m scraper.refresh_komikcast_cover_urls
    python -m scraper.refresh_komikcast_cover_urls --limit 100
    python -m scraper.refresh_komikcast_cover_urls --dry-run --limit 20
    python -m scraper.refresh_komikcast_cover_urls --verify-image --reset
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.services.image_service import (
    fetch_komikcast_cover_url_for_slug,
    get_komikcast_cover_refresh_candidates,
    get_proxy_headers,
    update_komikcast_cover_url_for_slug,
)
from scraper.time_utils import now_wib
from scraper.utils import (
    GracefulShutdown,
    RealtimeConsoleHandler,
    backoff_delay,
    configure_external_loggers as _configure_external_loggers_base,
    configure_logging as _configure_logging_base,
    format_elapsed_duration,
    random_delay,
    resolve_log_path as _resolve_log_path_base,
)

logger = logging.getLogger("refresh-komikcast-cover-urls")

SOURCE_NAME = "komikcast"
DEFAULT_LOG_FILE = Path("refresh_komikcast_cover_urls.log")
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "checkpoints"
CHECKPOINT_FILE = CHECKPOINT_DIR / "refresh_komikcast_cover_urls.json"

DEFAULT_LIMIT = 0
DEFAULT_BATCH_SIZE = 50
DELAY_COVER_MIN = 1.5
DELAY_COVER_MAX = 4.0
COOLDOWN_EVERY_N_COVERS = 20
COOLDOWN_MIN = 8.0
COOLDOWN_MAX = 18.0
BACKOFF_MAX = 120.0
MAX_CONSECUTIVE_ERRORS = 5

_shutdown = GracefulShutdown()
_shutdown.install()


@dataclass(slots=True)
class CoverUrlCandidate:
    id: int
    slug: str
    title: str
    cover_image_url: str | None


@dataclass
class RefreshStats:
    total_scanned: int = 0
    total_resolved: int = 0
    total_updated: int = 0
    total_unchanged: int = 0
    total_skipped: int = 0
    total_errors: int = 0
    processed_since_cooldown: int = 0


def resolve_log_path(log_file: str | None) -> Path:
    filename = log_file or str(DEFAULT_LOG_FILE)
    return _resolve_log_path_base(filename)


def configure_logging(log_file: str | None = None) -> None:
    """Konfigurasi logger root konsisten dengan script sync scraper lain."""
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    _configure_logging_base(
        log_file or str(DEFAULT_LOG_FILE),
        default_filename=str(DEFAULT_LOG_FILE),
        stdout_handler=RealtimeConsoleHandler(sys.stdout),
    )
    _configure_external_loggers_base()


def _default_stats() -> dict:
    return {
        "total_scanned": 0,
        "total_resolved": 0,
        "total_updated": 0,
        "total_unchanged": 0,
        "total_skipped": 0,
        "total_errors": 0,
        "processed_since_cooldown": 0,
    }


def _default_progress() -> dict:
    return {
        "source": SOURCE_NAME,
        "limit": 0,
        "dry_run": False,
        "verify_image": False,
        "current_comic_id": 0,
        "current_comic_position": 0,
        "current_comic_total": 0,
        "current_slug": None,
        "current_title": None,
        "state": "idle",
        "note": None,
    }


def _default_checkpoint() -> dict:
    return {
        "last_processed_comic_id": 0,
        "updated_at": None,
        "stats": _default_stats(),
        "progress": _default_progress(),
    }


def _normalize_checkpoint(data: dict | None) -> dict:
    checkpoint = data or {}
    checkpoint.setdefault("last_processed_comic_id", 0)
    checkpoint.setdefault("updated_at", None)

    stats = checkpoint.setdefault("stats", _default_stats())
    for key, value in _default_stats().items():
        stats.setdefault(key, value)

    progress = checkpoint.setdefault("progress", _default_progress())
    for key, value in _default_progress().items():
        progress.setdefault(key, value)

    if (
        progress["current_comic_id"] == 0
        and checkpoint["last_processed_comic_id"] > 0
    ):
        progress["current_comic_id"] = checkpoint["last_processed_comic_id"]

    return checkpoint


def update_progress(
    checkpoint: dict,
    *,
    limit: int | None = None,
    dry_run: bool | None = None,
    verify_image: bool | None = None,
    current_comic_id: int | None = None,
    current_comic_position: int | None = None,
    current_comic_total: int | None = None,
    current_slug: str | None = None,
    current_title: str | None = None,
    state: str | None = None,
    note: str | None = None,
) -> dict:
    progress = checkpoint.setdefault("progress", _default_progress())
    if limit is not None:
        progress["limit"] = limit
    if dry_run is not None:
        progress["dry_run"] = dry_run
    if verify_image is not None:
        progress["verify_image"] = verify_image
    if current_comic_id is not None:
        progress["current_comic_id"] = current_comic_id
    if current_comic_position is not None:
        progress["current_comic_position"] = current_comic_position
    if current_comic_total is not None:
        progress["current_comic_total"] = current_comic_total
    if current_slug is not None:
        progress["current_slug"] = current_slug
    if current_title is not None:
        progress["current_title"] = current_title
    if state is not None:
        progress["state"] = state
    if note is not None:
        progress["note"] = note
    return progress


def load_checkpoint() -> dict:
    if not CHECKPOINT_FILE.exists():
        return _default_checkpoint()
    try:
        with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
            checkpoint = _normalize_checkpoint(json.load(f))
        logger.info("📂 Checkpoint ditemukan: %s", CHECKPOINT_FILE)
        return checkpoint
    except Exception as exc:
        logger.warning("⚠️ Checkpoint rusak, mulai baru: %s", exc)
        return _default_checkpoint()


def save_checkpoint(checkpoint: dict) -> None:
    checkpoint["updated_at"] = now_wib().isoformat()
    CHECKPOINT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CHECKPOINT_FILE, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)


def persist_checkpoint(checkpoint: dict, *, enabled: bool) -> None:
    if enabled:
        save_checkpoint(checkpoint)


def reset_checkpoint() -> None:
    if CHECKPOINT_FILE.exists():
        CHECKPOINT_FILE.unlink()
        logger.info("🗑️ Checkpoint dihapus: %s", CHECKPOINT_FILE)


async def fetch_candidates(*, limit: int, after_id: int) -> list[CoverUrlCandidate]:
    async with async_session() as session:
        rows = await get_komikcast_cover_refresh_candidates(
            session,
            limit=limit,
            after_id=after_id,
        )
    return [
        CoverUrlCandidate(
            id=comic_id,
            slug=slug,
            title=title,
            cover_image_url=cover_image_url,
        )
        for comic_id, slug, title, cover_image_url in rows
    ]


async def fresh_url_is_reachable(
    client: httpx.AsyncClient,
    cover_url: str,
) -> bool:
    try:
        response = await client.head(cover_url, headers=get_proxy_headers(cover_url))
    except httpx.HTTPError as exc:
        logger.debug("Verify cover URL gagal: %s", exc)
        return False
    return response.status_code == 200


async def process_candidate(
    client: httpx.AsyncClient,
    candidate: CoverUrlCandidate,
    *,
    dry_run: bool,
    verify_image: bool,
) -> str:
    fresh_url = await fetch_komikcast_cover_url_for_slug(client, candidate.slug)
    if not fresh_url:
        logger.warning("  ⚠️ coverImage kosong/gagal: %s", candidate.slug)
        return "failed"

    if verify_image and not await fresh_url_is_reachable(client, fresh_url):
        logger.warning("  ⚠️ URL fresh tidak reachable: %s", candidate.slug)
        return "skipped"

    current_url = (candidate.cover_image_url or "").strip()
    if fresh_url == current_url:
        logger.info("  = cover URL sudah fresh: %s", candidate.slug)
        return "unchanged"

    if dry_run:
        logger.info("  🧪 dry-run update: %s", candidate.slug)
        return "updated"

    async with async_session() as session:
        changed = await update_komikcast_cover_url_for_slug(
            session,
            slug=candidate.slug,
            cover_url=fresh_url,
        )

    logger.info(
        "  %s cover URL %s: %s",
        "✅ update" if changed else "=",
        candidate.id,
        candidate.slug,
    )
    return "updated" if changed else "unchanged"


async def delay_between_covers(args: argparse.Namespace) -> None:
    if args.delay is not None:
        if args.delay > 0:
            await random_delay(args.delay, args.delay, "antar-cover")
        return
    await random_delay(args.delay_min, args.delay_max, "antar-cover")


def _stats_payload(stats: RefreshStats) -> dict:
    return {
        "total_scanned": stats.total_scanned,
        "total_resolved": stats.total_resolved,
        "total_updated": stats.total_updated,
        "total_unchanged": stats.total_unchanged,
        "total_skipped": stats.total_skipped,
        "total_errors": stats.total_errors,
        "processed_since_cooldown": stats.processed_since_cooldown,
    }


async def run(args: argparse.Namespace) -> None:
    start_time = time.time()
    started_at = now_wib()
    checkpoint_enabled = not args.dry_run

    if args.reset and checkpoint_enabled:
        reset_checkpoint()

    checkpoint = load_checkpoint() if checkpoint_enabled else _default_checkpoint()
    stats = RefreshStats(**checkpoint.get("stats", {}))
    after_id = (
        int(checkpoint.get("last_processed_comic_id", 0) or 0)
        if checkpoint_enabled
        else 0
    )
    remaining = max(args.limit, 0)

    update_progress(
        checkpoint,
        limit=args.limit,
        dry_run=args.dry_run,
        verify_image=args.verify_image,
        state="starting",
        note="Refresh Komikcast cover URLs dimulai",
    )
    persist_checkpoint(checkpoint, enabled=checkpoint_enabled)

    logger.info("═" * 60)
    logger.info("🚀 Refresh Komikcast Cover URLs dimulai — %s", started_at.isoformat())
    logger.info("   Source      : %s", SOURCE_NAME)
    logger.info("   Limit       : %s", args.limit if args.limit > 0 else "tanpa limit")
    logger.info("   Batch size  : %s", args.batch_size)
    logger.info("   Verify image: %s", args.verify_image)
    logger.info("   Dry-run     : %s", args.dry_run)
    logger.info("   Timeout     : %.1fs", args.timeout)
    logger.info(
        "   Delay       : %s",
        f"{args.delay:.1f}s" if args.delay is not None else f"{args.delay_min:.1f}-{args.delay_max:.1f}s",
    )
    logger.info("   Reset       : %s", args.reset)
    logger.info("   Resume >ID  : %s", after_id)
    logger.info("   Checkpoint  : %s", CHECKPOINT_FILE if checkpoint_enabled else "disabled (dry-run)")
    logger.info("   Log file    : %s", resolve_log_path(args.log_file))
    logger.info("═" * 60)

    consecutive_errors = 0
    processed_this_run = 0

    async with httpx.AsyncClient(
        follow_redirects=True,
        timeout=args.timeout,
    ) as client:
        while not _shutdown.requested:
            current_limit = max(args.batch_size, 1)
            if remaining > 0:
                current_limit = min(current_limit, remaining)
                if current_limit <= 0:
                    break

            candidates = await fetch_candidates(limit=current_limit, after_id=after_id)
            if not candidates:
                logger.info("Tidak ada kandidat setelah comic id %s.", after_id)
                break

            logger.info("Batch kandidat: %s item setelah id %s", len(candidates), after_id)
            for index, candidate in enumerate(candidates, start=1):
                if _shutdown.requested:
                    logger.warning("🛑 Shutdown diminta, berhenti setelah checkpoint terakhir.")
                    break

                processed_this_run += 1
                stats.total_scanned += 1
                update_progress(
                    checkpoint,
                    current_comic_id=candidate.id,
                    current_comic_position=processed_this_run,
                    current_comic_total=args.limit if args.limit > 0 else 0,
                    current_slug=candidate.slug,
                    current_title=candidate.title,
                    state="processing-cover-url",
                    note=f"Memproses {candidate.slug}",
                )
                persist_checkpoint(checkpoint, enabled=checkpoint_enabled)

                logger.info(
                    "[%s%s] #%s %s",
                    processed_this_run,
                    f"/{args.limit}" if args.limit > 0 else "",
                    candidate.id,
                    candidate.slug,
                )

                try:
                    status = await process_candidate(
                        client,
                        candidate,
                        dry_run=args.dry_run,
                        verify_image=args.verify_image,
                    )
                    if status == "updated":
                        stats.total_resolved += 1
                        stats.total_updated += 1
                        stats.processed_since_cooldown += 1
                    elif status == "unchanged":
                        stats.total_resolved += 1
                        stats.total_unchanged += 1
                    elif status == "skipped":
                        stats.total_resolved += 1
                        stats.total_skipped += 1
                        consecutive_errors += 1
                    else:
                        stats.total_errors += 1
                        consecutive_errors += 1

                    if status in ("updated", "unchanged"):
                        consecutive_errors = 0

                    update_progress(
                        checkpoint,
                        state=f"cover-url-{status}",
                        note=f"Cover URL {candidate.id}: {status}",
                    )
                except Exception as exc:
                    stats.total_errors += 1
                    consecutive_errors += 1
                    logger.exception("  error refresh %s: %s", candidate.slug, exc)
                    update_progress(
                        checkpoint,
                        state="cover-url-error",
                        note=f"Error cover URL {candidate.id}: {exc}",
                    )

                after_id = candidate.id
                checkpoint["last_processed_comic_id"] = candidate.id
                checkpoint["stats"] = _stats_payload(stats)
                persist_checkpoint(checkpoint, enabled=checkpoint_enabled)

                if remaining > 0:
                    remaining -= 1

                if consecutive_errors:
                    await backoff_delay(
                        min(consecutive_errors - 1, MAX_CONSECUTIVE_ERRORS - 1),
                        "refresh cover URL komikcast",
                        maximum=BACKOFF_MAX,
                    )
                    if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                        logger.warning(
                            "  ⛔ %s error berturut-turut. Cooldown sebelum lanjut.",
                            MAX_CONSECUTIVE_ERRORS,
                        )
                        await random_delay(
                            COOLDOWN_MIN,
                            COOLDOWN_MAX,
                            "cooldown error cover URL",
                        )
                        consecutive_errors = 0

                if stats.processed_since_cooldown >= COOLDOWN_EVERY_N_COVERS:
                    stats.processed_since_cooldown = 0
                    logger.info("  🧊 Cooldown berkala cover URL...")
                    await random_delay(COOLDOWN_MIN, COOLDOWN_MAX, "cooldown cover URL")

                if remaining == 0 and args.limit > 0:
                    break

                await delay_between_covers(args)

            if remaining == 0 and args.limit > 0:
                break

    if _shutdown.requested:
        update_progress(checkpoint, state="interrupted", note="Dihentikan manual")
    else:
        update_progress(checkpoint, state="complete", note="Refresh cover URL selesai")
    checkpoint["stats"] = _stats_payload(stats)
    persist_checkpoint(checkpoint, enabled=checkpoint_enabled)

    elapsed = time.time() - start_time
    finished_at = now_wib()
    logger.info("═" * 60)
    logger.info("🏁 Refresh Komikcast Cover URLs selesai!")
    logger.info("   Mulai      : %s", started_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Selesai    : %s", finished_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Waktu      : %s", format_elapsed_duration(elapsed))
    logger.info("   Source     : %s", SOURCE_NAME)
    logger.info("   Scanned    : %s", stats.total_scanned)
    logger.info("   Resolved   : %s", stats.total_resolved)
    logger.info("   Updated    : %s", stats.total_updated)
    logger.info("   Unchanged  : %s", stats.total_unchanged)
    logger.info("   Skipped    : %s", stats.total_skipped)
    logger.info("   Errors     : %s", stats.total_errors)
    logger.info("   Checkpoint : %s", CHECKPOINT_FILE if checkpoint_enabled else "disabled (dry-run)")
    logger.info("═" * 60)


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh comics.cover_image_url untuk signed cover URL Komikcast.",
    )
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="0 berarti tanpa limit")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument(
        "--delay",
        type=float,
        default=None,
        help="Delay tetap antar cover. Jika tidak diisi, pakai delay acak.",
    )
    parser.add_argument("--delay-min", type=float, default=DELAY_COVER_MIN)
    parser.add_argument("--delay-max", type=float, default=DELAY_COVER_MAX)
    parser.add_argument(
        "--log-file",
        default=None,
        help="Path file log. Jika relatif, disimpan di backend/logs/.",
    )
    parser.add_argument("--verify-image", action="store_true")
    parser.add_argument("--reset", action="store_true", help="Hapus checkpoint sebelum mulai")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    if args.limit < 0:
        parser.error("--limit tidak boleh negatif")
    if args.batch_size <= 0:
        parser.error("--batch-size harus lebih besar dari 0")
    if args.timeout <= 0:
        parser.error("--timeout harus lebih besar dari 0")
    if args.delay is not None and args.delay < 0:
        parser.error("--delay tidak boleh negatif")
    if args.delay_min < 0 or args.delay_max < 0:
        parser.error("--delay-min/--delay-max tidak boleh negatif")
    if args.delay_min > args.delay_max:
        parser.error("--delay-min tidak boleh lebih besar dari --delay-max")
    return args


def main() -> None:
    args = parse_args()
    configure_logging(args.log_file)
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
