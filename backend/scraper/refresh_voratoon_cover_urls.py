"""
Tonztoon Komik — Refresh Voratoon Cover URLs

Voratoon cover images are short-lived signed MinIO/S3 URLs (`X-Amz-Expires=86400`).
This script refreshes `comics.cover_image_url` for source `voratoon` by resolving the
latest `coverImage` from the Voratoon JSON API (`https://api.voratoon.com`).

Usage:
    cd backend
    python -m scraper.refresh_voratoon_cover_urls
    python -m scraper.refresh_voratoon_cover_urls --limit 100
    python -m scraper.refresh_voratoon_cover_urls --dry-run --limit 20
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import httpx
from sqlalchemy import select, update

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Comic
from scraper.sources.voratoon_api import (
    VORATOON_API_BASE_URL,
    VORATOON_BASE_URL,
    build_voratoon_api_headers,
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

logger = logging.getLogger("refresh-voratoon-cover-urls")

SOURCE_NAME = "voratoon"
DEFAULT_LOG_FILE = Path("refresh_voratoon_cover_urls.log")

DEFAULT_LIMIT = 0
DEFAULT_BATCH_SIZE = 50
DELAY_COVER_MIN = 0.5
DELAY_COVER_MAX = 1.5
COOLDOWN_EVERY_N_COVERS = 30
COOLDOWN_MIN = 3.0
COOLDOWN_MAX = 8.0
BACKOFF_MAX = 60.0
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


async def fetch_voratoon_cover_url_for_slug(
    client: httpx.AsyncClient,
    slug: str,
) -> str | None:
    api_url = f"{VORATOON_API_BASE_URL}/series/{slug}?includeMeta=true"
    headers = build_voratoon_api_headers(f"{VORATOON_BASE_URL}/series/{slug}")

    response = await client.get(api_url, headers=headers)
    if response.status_code != 200:
        logger.warning(
            "Voratoon API error status=%s slug=%s",
            response.status_code,
            slug,
        )
        return None

    payload = response.json()
    item = payload.get("data") or {}
    item_data = item.get("data") or {}

    raw_cover = item_data.get("coverImage") or item_data.get("cover")
    if not raw_cover or not isinstance(raw_cover, str):
        return None

    return raw_cover.strip()


async def get_voratoon_cover_refresh_candidates(
    limit: int = 0,
) -> list[CoverUrlCandidate]:
    async with async_session() as session:
        stmt = (
            select(Comic.id, Comic.slug, Comic.title, Comic.cover_image_url)
            .where(Comic.source_name == SOURCE_NAME)
            .order_by(Comic.id.asc())
        )
        if limit > 0:
            stmt = stmt.limit(limit)

        result = await session.execute(stmt)
        return [
            CoverUrlCandidate(
                id=row.id,
                slug=row.slug,
                title=row.title,
                cover_image_url=row.cover_image_url,
            )
            for row in result.all()
        ]


async def update_voratoon_cover_url_for_slug(
    comic_id: int,
    fresh_cover_url: str,
) -> bool:
    async with async_session() as session:
        stmt = (
            update(Comic)
            .where(Comic.id == comic_id, Comic.source_name == SOURCE_NAME)
            .values(cover_image_url=fresh_cover_url)
        )
        result = await session.execute(stmt)
        await session.commit()
        return result.rowcount > 0


async def process_candidates(
    candidates: Iterable[CoverUrlCandidate],
    *,
    dry_run: bool = False,
    anti_blocking: bool = True,
) -> RefreshStats:
    stats = RefreshStats()
    consecutive_errors = 0
    start_time = time.monotonic()

    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        for candidate in candidates:
            if _shutdown.interrupted:
                logger.warning("Terminating loop due to interrupt signal...")
                break

            stats.total_scanned += 1
            try:
                fresh_url = await fetch_voratoon_cover_url_for_slug(client, candidate.slug)
                if not fresh_url:
                    stats.total_skipped += 1
                    consecutive_errors = 0
                    continue

                stats.total_resolved += 1

                if candidate.cover_image_url == fresh_url:
                    stats.total_unchanged += 1
                else:
                    if not dry_run:
                        await update_voratoon_cover_url_for_slug(candidate.id, fresh_url)
                    stats.total_updated += 1
                    logger.info(
                        "[%s] Updated cover for '%s' (%s)",
                        "DRY-RUN" if dry_run else "UPDATED",
                        candidate.title,
                        candidate.slug,
                    )

                consecutive_errors = 0
                stats.processed_since_cooldown += 1

                if anti_blocking:
                    await random_delay(DELAY_COVER_MIN, DELAY_COVER_MAX)

                if (
                    anti_blocking
                    and stats.processed_since_cooldown >= COOLDOWN_EVERY_N_COVERS
                ):
                    logger.info("Cooldown period after %s covers...", COOLDOWN_EVERY_N_COVERS)
                    await random_delay(COOLDOWN_MIN, COOLDOWN_MAX)
                    stats.processed_since_cooldown = 0

            except Exception as exc:
                stats.total_errors += 1
                consecutive_errors += 1
                logger.error(
                    "Error processing '%s' (%s): %s",
                    candidate.title,
                    candidate.slug,
                    exc,
                )
                if anti_blocking:
                    await backoff_delay(consecutive_errors, max_delay=BACKOFF_MAX)

    elapsed = format_elapsed_duration(time.monotonic() - start_time)
    logger.info(
        "Cover refresh finished in %s. Scanned: %s, Updated: %s, Unchanged: %s, Errors: %s",
        elapsed,
        stats.total_scanned,
        stats.total_updated,
        stats.total_unchanged,
        stats.total_errors,
    )
    return stats


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh Voratoon cover URLs in database.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="Limit number of comics to process")
    parser.add_argument("--dry-run", action="store_true", help="Perform dry run without saving DB changes")
    parser.add_argument("--no-anti-blocking", action="store_true", help="Disable anti-blocking delays")
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    _configure_logging_base(str(DEFAULT_LOG_FILE), stdout_handler=RealtimeConsoleHandler(sys.stdout))

    logger.info("Starting Voratoon cover refresh script...")
    candidates = await get_voratoon_cover_refresh_candidates(limit=args.limit)
    logger.info("Found %s Voratoon comic candidates to process", len(candidates))

    await process_candidates(
        candidates,
        dry_run=args.dry_run,
        anti_blocking=not args.no_anti-blocking,
    )


if __name__ == "__main__":
    asyncio.run(main())
