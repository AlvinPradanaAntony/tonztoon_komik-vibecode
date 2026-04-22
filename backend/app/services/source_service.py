"""
Service layer untuk statistik source yang disimpan di database.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import SourceStat
from scraper.sources.registry import create_scraper, get_supported_source_names

logger = logging.getLogger("app.services.source_service")

_SOURCE_COUNT_FETCH_TIMEOUTS: dict[str, float] = {
    "komiku_asia": 120.0,
}
_DEFAULT_SOURCE_COUNT_FETCH_TIMEOUT = 30.0


async def get_source_stats_map(
    db: AsyncSession,
    source_names: list[str] | None = None,
) -> dict[str, SourceStat]:
    """Ambil baris source_stats dari database, dikelompokkan per source_name."""
    normalized_source_names = source_names or get_supported_source_names()
    result = await db.execute(
        select(SourceStat).where(SourceStat.source_name.in_(normalized_source_names))
    )
    rows = result.scalars().all()
    return {row.source_name: row for row in rows}


async def refresh_source_stat(
    db: AsyncSession,
    source_name: str,
) -> SourceStat:
    """Refresh satu source_stat dari scraper source terkait dan simpan ke DB."""
    now = datetime.now(UTC)
    source_stat = await db.get(SourceStat, source_name)
    if source_stat is None:
        source_stat = SourceStat(source_name=source_name)
        db.add(source_stat)

    source_stat.last_attempted_at = now

    scraper = create_scraper(source_name)
    try:
        timeout_seconds = _SOURCE_COUNT_FETCH_TIMEOUTS.get(
            source_name,
            _DEFAULT_SOURCE_COUNT_FETCH_TIMEOUT,
        )
        source_count = await asyncio.wait_for(
            scraper.get_source_comic_count(),
            timeout=timeout_seconds,
        )
        source_stat.source_comic_count = source_count
        source_stat.last_refreshed_at = now
        source_stat.last_error = None
    except Exception as exc:
        logger.warning(
            "Gagal refresh source_stats untuk %s: %s: %s",
            source_name,
            type(exc).__name__,
            exc,
        )
        source_stat.last_error = f"{type(exc).__name__}: {exc}"
    finally:
        await scraper.close()

    await db.commit()
    await db.refresh(source_stat)
    return source_stat


async def refresh_source_stats(
    db: AsyncSession,
    source_names: list[str] | None = None,
) -> list[SourceStat]:
    """Refresh source_stats untuk seluruh source atau subset tertentu."""
    normalized_source_names = source_names or get_supported_source_names()
    refreshed_rows: list[SourceStat] = []

    for source_name in normalized_source_names:
        refreshed_rows.append(await refresh_source_stat(db, source_name))

    return refreshed_rows
