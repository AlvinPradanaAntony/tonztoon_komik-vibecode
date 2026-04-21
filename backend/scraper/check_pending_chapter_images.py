"""
Tonztoon Komik — Pending Chapter Images Preflight Check

Script kecil untuk menghitung backlog chapter yang images-nya masih kosong.
Dipakai terutama oleh GitHub Actions agar workflow images backfill bisa
langsung exit/no-op tanpa menginstal browser dan menjalankan scraper penuh
jika backlog sudah habis.

Usage:
    cd backend
    python -m scraper.check_pending_chapter_images
    python -m scraper.check_pending_chapter_images --source komikcast
"""

import asyncio
import json
import sys
from pathlib import Path

from sqlalchemy import case, func, or_, select
from sqlalchemy.dialects.postgresql import JSONPATH
from sqlalchemy.sql import cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Chapter, Comic
from scraper.sources.registry import get_supported_source_names

SUPPORTED_SOURCES = tuple(get_supported_source_names())
INVALID_IMAGES_JSONPATH = cast(
    '$[*] ? (!exists(@.page) || !exists(@.url) || @.url == "")',
    JSONPATH,
)


def parse_args(argv: list[str]) -> dict:
    args = {
        "source": None,
        "github_output": None,
        "json_only": False,
    }
    i = 0
    while i < len(argv):
        if argv[i] == "--source" and i + 1 < len(argv):
            args["source"] = argv[i + 1].strip().lower()
            i += 2
        elif argv[i] == "--github-output" and i + 1 < len(argv):
            args["github_output"] = argv[i + 1]
            i += 2
        elif argv[i] == "--json-only":
            args["json_only"] = True
            i += 1
        else:
            i += 1

    if args["source"] and args["source"] not in SUPPORTED_SOURCES:
        raise ValueError(
            f"--source tidak valid. Gunakan salah satu dari: {', '.join(SUPPORTED_SOURCES)}"
        )
    return args


async def collect_pending_stats(source_name: str | None = None) -> dict:
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

    async with async_session() as session:
        total_stmt = (
            select(func.count())
            .select_from(Chapter)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(invalid_images)
        )
        if source_name:
            total_stmt = total_stmt.where(Comic.source_name == source_name)
        total_result = await session.execute(total_stmt)
        pending_count = int(total_result.scalar_one() or 0)

        by_source_stmt = (
            select(Comic.source_name, func.count())
            .select_from(Chapter)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(invalid_images)
            .group_by(Comic.source_name)
            .order_by(Comic.source_name.asc())
        )
        if source_name:
            by_source_stmt = by_source_stmt.where(Comic.source_name == source_name)
        rows = (await session.execute(by_source_stmt)).all()

    pending_by_source = {row[0]: int(row[1]) for row in rows}
    return {
        "source": source_name,
        "pending_count": pending_count,
        "has_pending": pending_count > 0,
        "pending_by_source": pending_by_source,
    }


def write_github_output(path: str, stats: dict) -> None:
    pending_by_source_json = json.dumps(stats["pending_by_source"], ensure_ascii=False, separators=(",", ":"))
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"has_pending={'true' if stats['has_pending'] else 'false'}\n")
        f.write(f"pending_count={stats['pending_count']}\n")
        f.write(f"pending_by_source={pending_by_source_json}\n")


async def main(argv: list[str] | None = None) -> None:
    args = parse_args(list(sys.argv[1:] if argv is None else argv))
    stats = await collect_pending_stats(args["source"])

    if args["github_output"]:
        write_github_output(args["github_output"], stats)

    if args["json_only"]:
        print(json.dumps(stats, ensure_ascii=False))
        return

    print(f"Pending chapter images: {stats['pending_count']}")
    if stats["pending_by_source"]:
        print("By source:")
        for source_name, count in stats["pending_by_source"].items():
            print(f"- {source_name}: {count}")
    else:
        print("By source: {}")


if __name__ == "__main__":
    asyncio.run(main())
