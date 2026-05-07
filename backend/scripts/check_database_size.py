"""
Log current PostgreSQL/Supabase database size.

Script read-only untuk melihat ukuran database saat ini, schema terbesar,
tabel terbesar, index terbesar, dan kontribusi khusus `chapters.images`.

Usage (dari folder backend/):
    python -m scripts.check_database_size
    python -m scripts.check_database_size --top 20
    python -m scripts.check_database_size --schema public
    python -m scripts.check_database_size --log-file db_size.log
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

# Pastikan backend/ ada di sys.path agar bisa import app.* dan scraper.*.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings
from scraper.utils import configure_logging


DEFAULT_LOG_FILE = "check_database_size.log"
logger = logging.getLogger("check-database-size")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Tampilkan ukuran database PostgreSQL/Supabase via logger."
    )
    parser.add_argument(
        "--top",
        type=int,
        default=15,
        help="Jumlah tabel/index terbesar yang ditampilkan. Default: 15.",
    )
    parser.add_argument(
        "--schema",
        help="Opsional: batasi daftar tabel/index ke schema tertentu, misalnya public.",
    )
    parser.add_argument(
        "--log-file",
        help="Path file log. Jika relatif, disimpan di backend/logs/.",
    )
    args = parser.parse_args(argv)
    if args.top < 1:
        parser.error("--top harus >= 1")
    if args.schema:
        args.schema = args.schema.strip()
    return args


def create_engine() -> AsyncEngine:
    return create_async_engine(
        settings.DATABASE_URL,
        connect_args={
            "statement_cache_size": 0,
            "prepared_statement_cache_size": 0,
        },
    )


def format_bytes(value: int) -> str:
    units = ("B", "KB", "MB", "GB", "TB")
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.2f} {unit}"
        amount /= 1024
    return f"{amount:.2f} TB"


def pct(part: int, whole: int) -> str:
    if whole <= 0:
        return "0.00%"
    return f"{(part / whole) * 100:.2f}%"


def params(args: argparse.Namespace) -> dict[str, Any]:
    result: dict[str, Any] = {"top": args.top}
    if args.schema:
        result["schema"] = args.schema
    return result


def schema_filter_sql(args: argparse.Namespace, alias: str = "schemaname") -> str:
    if args.schema:
        return f"AND {alias} = :schema"
    return ""


async def get_database_size(conn) -> dict[str, Any]:
    result = await conn.execute(
        text(
            """
            SELECT
                current_database() AS database_name,
                pg_database_size(current_database())::bigint AS size_bytes
            """
        )
    )
    return dict(result.mappings().one())


async def get_schema_sizes(conn) -> list[dict[str, Any]]:
    result = await conn.execute(
        text(
            """
            SELECT
                n.nspname AS schema_name,
                COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint AS total_bytes
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r', 'p', 'm')
              AND n.nspname <> 'information_schema'
              AND n.nspname NOT LIKE 'pg_%'
            GROUP BY n.nspname
            ORDER BY total_bytes DESC
            """
        )
    )
    return [dict(row) for row in result.mappings().all()]


async def get_table_sizes(conn, args: argparse.Namespace) -> list[dict[str, Any]]:
    result = await conn.execute(
        text(
            f"""
            SELECT
                schemaname AS schema_name,
                relname AS table_name,
                n_live_tup::bigint AS estimated_rows,
                pg_total_relation_size(relid)::bigint AS total_bytes,
                pg_relation_size(relid)::bigint AS table_bytes,
                pg_indexes_size(relid)::bigint AS index_bytes,
                GREATEST(
                    pg_total_relation_size(relid)
                    - pg_relation_size(relid)
                    - pg_indexes_size(relid),
                    0
                )::bigint AS toast_bytes
            FROM pg_stat_user_tables
            WHERE 1 = 1
              {schema_filter_sql(args)}
            ORDER BY total_bytes DESC
            LIMIT :top
            """
        ),
        params(args),
    )
    return [dict(row) for row in result.mappings().all()]


async def get_index_sizes(conn, args: argparse.Namespace) -> list[dict[str, Any]]:
    result = await conn.execute(
        text(
            f"""
            SELECT
                schemaname AS schema_name,
                relname AS table_name,
                indexrelname AS index_name,
                pg_relation_size(indexrelid)::bigint AS index_bytes,
                idx_scan::bigint AS scans
            FROM pg_stat_user_indexes
            WHERE 1 = 1
              {schema_filter_sql(args)}
            ORDER BY index_bytes DESC
            LIMIT :top
            """
        ),
        params(args),
    )
    return [dict(row) for row in result.mappings().all()]


async def get_chapter_images_summary(conn) -> dict[str, Any]:
    result = await conn.execute(
        text(
            """
            SELECT
                COUNT(*)::bigint AS chapter_count,
                COUNT(*) FILTER (WHERE images IS NULL)::bigint AS images_null_count,
                COUNT(*) FILTER (
                    WHERE images IS NOT NULL
                      AND jsonb_typeof(images) = 'array'
                      AND jsonb_array_length(images) = 0
                )::bigint AS images_empty_count,
                COUNT(*) FILTER (
                    WHERE images IS NOT NULL
                      AND (
                        jsonb_typeof(images) <> 'array'
                        OR jsonb_array_length(images) > 0
                      )
                )::bigint AS images_filled_count,
                COALESCE(SUM(pg_column_size(images)), 0)::bigint AS images_json_bytes,
                COALESCE(
                    SUM(
                        CASE
                            WHEN images IS NOT NULL
                              AND jsonb_typeof(images) = 'array'
                            THEN jsonb_array_length(images)
                            ELSE 0
                        END
                    ),
                    0
                )::bigint AS image_item_count
            FROM public.chapters
            """
        )
    )
    return dict(result.mappings().one())


def log_schema_sizes(schema_sizes: list[dict[str, Any]], database_bytes: int) -> None:
    logger.info("Schema sizes:")
    if not schema_sizes:
        logger.info("  Tidak ada schema user yang terbaca.")
        return
    for row in schema_sizes:
        total_bytes = int(row["total_bytes"] or 0)
        logger.info(
            "  %-24s %12s (%s dari database)",
            row["schema_name"],
            format_bytes(total_bytes),
            pct(total_bytes, database_bytes),
        )


def log_table_sizes(table_sizes: list[dict[str, Any]], database_bytes: int) -> None:
    logger.info("Top table sizes:")
    if not table_sizes:
        logger.info("  Tidak ada tabel user yang terbaca.")
        return
    for row in table_sizes:
        total_bytes = int(row["total_bytes"] or 0)
        logger.info(
            "  %-32s rows=%-10s total=%10s table=%10s index=%10s toast=%10s (%s)",
            f"{row['schema_name']}.{row['table_name']}",
            row["estimated_rows"],
            format_bytes(total_bytes),
            format_bytes(int(row["table_bytes"] or 0)),
            format_bytes(int(row["index_bytes"] or 0)),
            format_bytes(int(row["toast_bytes"] or 0)),
            pct(total_bytes, database_bytes),
        )


def log_index_sizes(index_sizes: list[dict[str, Any]], database_bytes: int) -> None:
    logger.info("Top index sizes:")
    if not index_sizes:
        logger.info("  Tidak ada index user yang terbaca.")
        return
    for row in index_sizes:
        index_bytes = int(row["index_bytes"] or 0)
        logger.info(
            "  %-48s on %-28s size=%10s scans=%s (%s)",
            f"{row['schema_name']}.{row['index_name']}",
            row["table_name"],
            format_bytes(index_bytes),
            row["scans"],
            pct(index_bytes, database_bytes),
        )


def log_chapter_images_summary(summary: dict[str, Any], database_bytes: int) -> None:
    images_json_bytes = int(summary["images_json_bytes"] or 0)
    logger.info("Chapter images summary:")
    logger.info("  Chapter total       : %s", summary["chapter_count"])
    logger.info("  images NULL         : %s", summary["images_null_count"])
    logger.info("  images []           : %s", summary["images_empty_count"])
    logger.info("  images filled       : %s", summary["images_filled_count"])
    logger.info("  image item count    : %s", summary["image_item_count"])
    logger.info(
        "  images JSONB column : %s (%s dari database)",
        format_bytes(images_json_bytes),
        pct(images_json_bytes, database_bytes),
    )


async def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    configure_logging(args.log_file, default_filename=DEFAULT_LOG_FILE)

    engine = create_engine()
    try:
        async with engine.begin() as conn:
            database = await get_database_size(conn)
            database_bytes = int(database["size_bytes"] or 0)
            schema_sizes = await get_schema_sizes(conn)
            table_sizes = await get_table_sizes(conn, args)
            index_sizes = await get_index_sizes(conn, args)
            chapter_images = await get_chapter_images_summary(conn)

        logger.info("=" * 72)
        logger.info("Database size report")
        logger.info("=" * 72)
        logger.info(
            "Database: %s | total size: %s",
            database["database_name"],
            format_bytes(database_bytes),
        )
        if args.schema:
            logger.info("Schema filter for top table/index lists: %s", args.schema)
        logger.info("-" * 72)
        log_schema_sizes(schema_sizes, database_bytes)
        logger.info("-" * 72)
        log_table_sizes(table_sizes, database_bytes)
        logger.info("-" * 72)
        log_index_sizes(index_sizes, database_bytes)
        logger.info("-" * 72)
        log_chapter_images_summary(chapter_images, database_bytes)
        logger.info("=" * 72)
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
