"""
Refresh source_stats yang disimpan di database.

Usage:
    python -m scraper.refresh_source_stats
    python -m scraper.refresh_source_stats --source komiku_asia
"""

from __future__ import annotations

import asyncio
import sys

from app.database import async_session
from app.services.source_service import refresh_source_stats


def _parse_args(argv: list[str]) -> dict[str, list[str] | None]:
    source_names: list[str] | None = None
    i = 0
    while i < len(argv):
        if argv[i] == "--source" and i + 1 < len(argv):
            source_names = [item.strip() for item in argv[i + 1].split(",") if item.strip()]
            i += 2
            continue
        i += 1
    return {"source_names": source_names}


async def main(argv: list[str]) -> None:
    args = _parse_args(argv)
    async with async_session() as db:
        refreshed_rows = await refresh_source_stats(
            db,
            source_names=args["source_names"],
        )

    for row in refreshed_rows:
        print(
            f"{row.source_name}: count={row.source_comic_count} "
            f"last_refreshed_at={row.last_refreshed_at} "
            f"last_error={row.last_error}"
        )


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
