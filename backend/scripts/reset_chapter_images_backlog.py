"""
Reset chapter images back to backlog state.

Script ini mengosongkan `chapters.images` yang sudah berisi data gambar agar
chapter kembali dianggap backlog oleh `scraper.sync_chapter_images`.

Default-nya hanya dry-run. Tambahkan `--apply` untuk benar-benar update DB.

Usage (dari folder backend/):
    python -m scripts.reset_chapter_images_backlog
    python -m scripts.reset_chapter_images_backlog --apply
    python -m scripts.reset_chapter_images_backlog --apply --target null
    python -m scripts.reset_chapter_images_backlog --apply --target empty
    python -m scripts.reset_chapter_images_backlog --source komikcast --limit 500 --apply
    python -m scripts.reset_chapter_images_backlog --apply --batch-size 1000
    python -m scripts.reset_chapter_images_backlog --source komiku --mode random --limit 1000 --apply
    python -m scripts.reset_chapter_images_backlog --source komiku --mode random --limit 1000 --random-seed komiku-cleanup
    python -m scripts.reset_chapter_images_backlog --mode older-than-latest --keep-latest 100 --apply
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
import time
from pathlib import Path
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

# Pastikan backend/ ada di sys.path agar bisa import app.* saat dipanggil
# sebagai module dari folder backend.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings
from scraper.utils import configure_logging


TARGET_NULL = "null"
TARGET_EMPTY = "empty"
MODE_ORDERED = "ordered"
MODE_RANDOM = "random"
MODE_OLDER_THAN_LATEST = "older-than-latest"
DEFAULT_LOG_FILE = "reset_chapter_images_backlog.log"

logger = logging.getLogger("reset-chapter-images-backlog")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Reset chapters.images menjadi NULL atau [] agar kembali backlog."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Jalankan UPDATE. Tanpa flag ini script hanya menampilkan dry-run.",
    )
    parser.add_argument(
        "--target",
        choices=(TARGET_NULL, TARGET_EMPTY),
        default=TARGET_NULL,
        help="Nilai tujuan untuk chapters.images: null atau empty ([]). Default: null.",
    )
    parser.add_argument(
        "--source",
        help="Opsional: batasi ke comics.source_name tertentu, misalnya komikcast.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Opsional: total maksimum chapter yang di-reset. 0 berarti semua.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="Jumlah chapter per transaksi saat --apply. Default: 1000.",
    )
    parser.add_argument(
        "--mode",
        choices=(MODE_ORDERED, MODE_RANDOM, MODE_OLDER_THAN_LATEST),
        default=MODE_ORDERED,
        help=(
            "Strategi pemilihan chapter: ordered, random, atau older-than-latest. "
            "Default: ordered."
        ),
    )
    parser.add_argument(
        "--random-seed",
        help=(
            "Untuk --mode random: buat urutan acak deterministik. "
            "Pakai seed yang sama saat dry-run dan --apply agar target sama."
        ),
    )
    parser.add_argument(
        "--keep-latest",
        type=int,
        default=100,
        help=(
            "Untuk --mode older-than-latest: jumlah chapter terbaru per komik "
            "yang dipertahankan. Default: 100."
        ),
    )
    parser.add_argument(
        "--min-comic-chapters",
        type=int,
        default=100,
        help=(
            "Untuk --mode older-than-latest: hanya proses komik dengan total "
            "chapter lebih dari nilai ini. Default: 100."
        ),
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=None,
        help=(
            "Alias lama untuk --dry-run-list-limit. "
            "Dipertahankan agar command lama tidak rusak."
        ),
    )
    parser.add_argument(
        "--dry-run-list-limit",
        type=int,
        default=200,
        help=(
            "Saat dry-run tanpa --limit, maksimal target yang ditampilkan. "
            "0 berarti tampilkan semua target. Default: 200."
        ),
    )
    parser.add_argument(
        "--log-file",
        help="Path file log. Jika relatif, disimpan di backend/logs/.",
    )
    args = parser.parse_args(argv)
    if args.limit < 0:
        parser.error("--limit harus >= 0")
    if args.sample is not None:
        if args.sample < 0:
            parser.error("--sample harus >= 0")
        args.dry_run_list_limit = args.sample
    if args.dry_run_list_limit < 0:
        parser.error("--dry-run-list-limit harus >= 0")
    if args.batch_size < 1:
        parser.error("--batch-size harus >= 1")
    if args.keep_latest < 0:
        parser.error("--keep-latest harus >= 0")
    if args.min_comic_chapters < 0:
        parser.error("--min-comic-chapters harus >= 0")
    if args.source:
        args.source = args.source.strip()
    if args.random_seed:
        args.random_seed = args.random_seed.strip()
    return args


def _source_filter_sql(source_name: str | None) -> str:
    if not source_name:
        return ""
    return "AND co.source_name = :source_name"


def _params(args: argparse.Namespace) -> dict[str, Any]:
    params: dict[str, Any] = {}
    if args.source:
        params["source_name"] = args.source
    if args.limit > 0:
        params["limit"] = args.limit
    params["keep_latest"] = args.keep_latest
    params["min_comic_chapters"] = args.min_comic_chapters
    if args.random_seed:
        params["random_seed"] = args.random_seed
    return params


def create_engine() -> AsyncEngine:
    return create_async_engine(
        settings.DATABASE_URL,
        connect_args={
            "statement_cache_size": 0,
            "prepared_statement_cache_size": 0,
        },
    )


async def with_cli_loader(awaitable, label: str):
    task = asyncio.create_task(awaitable)
    if not sys.stdout.isatty():
        logger.info("%s...", label)
        result = await task
        logger.info("%s selesai.", label)
        return result

    frames = ("|", "/", "-", "\\")
    started_at = time.monotonic()
    frame_index = 0
    try:
        while not task.done():
            elapsed = int(time.monotonic() - started_at)
            sys.stdout.write(f"\r{frames[frame_index % len(frames)]} {label} ({elapsed}s)")
            sys.stdout.flush()
            frame_index += 1
            await asyncio.sleep(0.15)
        sys.stdout.write("\r" + " " * (len(label) + 20) + "\r")
        sys.stdout.flush()
        return await task
    except Exception:
        sys.stdout.write("\r" + " " * (len(label) + 20) + "\r")
        sys.stdout.flush()
        raise


async def get_current_database_summary(conn) -> dict[str, Any]:
    result = await conn.execute(
        text(
            """
            SELECT
                current_database() AS database_name,
                pg_database_size(current_database())::bigint AS database_bytes,
                pg_total_relation_size('public.chapters'::regclass)::bigint
                    AS chapters_total_bytes,
                pg_relation_size('public.chapters'::regclass)::bigint
                    AS chapters_table_bytes,
                pg_indexes_size('public.chapters'::regclass)::bigint
                    AS chapters_index_bytes,
                GREATEST(
                    pg_total_relation_size('public.chapters'::regclass)
                    - pg_relation_size('public.chapters'::regclass)
                    - pg_indexes_size('public.chapters'::regclass),
                    0
                )::bigint AS chapters_toast_bytes,
                COUNT(ch.*)::bigint AS chapter_count,
                COUNT(ch.*) FILTER (WHERE ch.images IS NULL)::bigint
                    AS images_null_count,
                COUNT(ch.*) FILTER (
                    WHERE ch.images IS NOT NULL
                      AND jsonb_typeof(ch.images) = 'array'
                      AND jsonb_array_length(ch.images) = 0
                )::bigint AS images_empty_count,
                COUNT(ch.*) FILTER (
                    WHERE ch.images IS NOT NULL
                      AND (
                        jsonb_typeof(ch.images) <> 'array'
                        OR jsonb_array_length(ch.images) > 0
                      )
                )::bigint AS images_filled_count,
                COALESCE(SUM(pg_column_size(ch.images)), 0)::bigint
                    AS images_json_bytes,
                COALESCE(
                    SUM(
                        CASE
                            WHEN ch.images IS NOT NULL
                              AND jsonb_typeof(ch.images) = 'array'
                            THEN jsonb_array_length(ch.images)
                            ELSE 0
                        END
                    ),
                    0
                )::bigint AS image_item_count
            FROM public.chapters ch
            """
        )
    )
    return dict(result.mappings().one())


def _filled_images_filter_sql(alias: str = "ch") -> str:
    return f"""
    {alias}.images IS NOT NULL
    AND (
        jsonb_typeof({alias}.images) <> 'array'
        OR jsonb_array_length({alias}.images) > 0
    )
    """


def _candidate_cte_sql(args: argparse.Namespace) -> str:
    source_filter = _source_filter_sql(args.source)
    filled_filter = _filled_images_filter_sql("ch")

    if args.mode == MODE_OLDER_THAN_LATEST:
        return f"""
        WITH ranked_chapters AS (
            SELECT
                ch.id,
                ch.images,
                ROW_NUMBER() OVER (
                    PARTITION BY ch.comic_id
                    ORDER BY ch.chapter_number DESC, ch.id DESC
                ) AS chapter_rank,
                COUNT(*) OVER (PARTITION BY ch.comic_id) AS comic_chapter_count
            FROM chapters ch
            JOIN comics co ON co.id = ch.comic_id
            WHERE 1 = 1
              {source_filter}
        ),
        candidate_chapters AS (
            SELECT
                id,
                images,
                chapter_rank,
                comic_chapter_count
            FROM ranked_chapters
            WHERE images IS NOT NULL
              AND (
                jsonb_typeof(images) <> 'array'
                OR jsonb_array_length(images) > 0
              )
              AND comic_chapter_count > :min_comic_chapters
              AND chapter_rank > :keep_latest
        )
        """

    return f"""
    WITH candidate_chapters AS (
        SELECT
            ch.id,
            ch.images,
            NULL::bigint AS chapter_rank,
            NULL::bigint AS comic_chapter_count
        FROM chapters ch
        JOIN comics co ON co.id = ch.comic_id
        WHERE {filled_filter}
          {source_filter}
    )
    """


def _selection_order_sql(args: argparse.Namespace, *, alias: str | None = None) -> str:
    id_column = f"{alias}.id" if alias else "id"
    if args.mode == MODE_RANDOM:
        if args.random_seed:
            return f"ORDER BY md5({id_column}::text || ':' || :random_seed)"
        return "ORDER BY random()"
    return f"ORDER BY {id_column}"


async def summarize(conn, args: argparse.Namespace) -> dict[str, int]:
    result = await conn.execute(
        text(
            f"""
            {_candidate_cte_sql(args)}
            SELECT
                COUNT(*)::bigint AS chapter_count,
                COALESCE(SUM(pg_column_size(images)), 0)::bigint AS image_json_bytes,
                COALESCE(
                    SUM(
                        CASE
                            WHEN jsonb_typeof(images) = 'array'
                            THEN jsonb_array_length(images)
                            ELSE 0
                        END
                    ),
                    0
                )::bigint AS image_item_count
            FROM candidate_chapters
            """
        ),
        _params(args),
    )
    row = result.mappings().one()
    return {
        "chapter_count": int(row["chapter_count"] or 0),
        "image_json_bytes": int(row["image_json_bytes"] or 0),
        "image_item_count": int(row["image_item_count"] or 0),
    }


def _dry_run_target_limit(args: argparse.Namespace, candidate_count: int) -> int:
    if args.limit > 0:
        return min(args.limit, candidate_count)
    if args.dry_run_list_limit == 0:
        return candidate_count
    return min(args.dry_run_list_limit, candidate_count)


async def load_dry_run_targets(
    conn,
    args: argparse.Namespace,
    *,
    candidate_count: int,
) -> list[dict[str, Any]]:
    target_limit = _dry_run_target_limit(args, candidate_count)
    if target_limit <= 0:
        return []

    candidate_cte = _candidate_cte_sql(args)
    result = await conn.execute(
        text(
            f"""
            {candidate_cte}
            SELECT
                ch.id,
                co.source_name,
                co.title AS comic_title,
                ch.chapter_number,
                CASE
                    WHEN jsonb_typeof(ch.images) = 'array'
                    THEN jsonb_array_length(ch.images)
                    ELSE 0
                END AS image_count,
                candidate.chapter_rank,
                candidate.comic_chapter_count
            FROM chapters ch
            JOIN comics co ON co.id = ch.comic_id
            JOIN candidate_chapters candidate ON candidate.id = ch.id
            {_selection_order_sql(args, alias="candidate")}
            LIMIT :target_limit
            """
        ),
        {**_params(args), "target_limit": target_limit},
    )
    rows = result.mappings().all()
    return [dict(row) for row in rows]


def log_dry_run_targets(
    rows: list[dict[str, Any]],
    args: argparse.Namespace,
    *,
    candidate_count: int,
) -> int:
    if not rows:
        return 0

    target_limit = _dry_run_target_limit(args, candidate_count)
    logger.info("Daftar target dry-run yang akan di-reset:")
    if args.limit == 0 and target_limit < candidate_count:
        logger.info(
            "  Menampilkan %s dari %s target. Gunakan --limit atau "
            "--dry-run-list-limit 0 untuk menampilkan semua.",
            target_limit,
            candidate_count,
        )
    if args.mode == MODE_RANDOM and not args.random_seed:
        logger.info(
            "  Catatan: mode random tanpa --random-seed akan memilih ulang "
            "target saat command --apply dijalankan."
        )

    for index, row in enumerate(rows, start=1):
        extra = ""
        if row["chapter_rank"] is not None and row["comic_chapter_count"] is not None:
            extra = (
                f" | rank terbaru #{row['chapter_rank']}"
                f"/{row['comic_chapter_count']}"
            )
        logger.info(
            "  %5s. [%s] %s | %s | Ch %s | %s images%s",
            index,
            row["id"],
            row["source_name"],
            row["comic_title"],
            row["chapter_number"],
            row["image_count"],
            extra,
        )

    return len(rows)


async def reset_images_batch(conn, args: argparse.Namespace, batch_limit: int) -> int:
    target_sql = "NULL" if args.target == TARGET_NULL else "'[]'::jsonb"

    result = await conn.execute(
        text(
            f"""
            {_candidate_cte_sql(args)},
            selected_chapters AS (
                SELECT id
                FROM candidate_chapters
                {_selection_order_sql(args)}
                LIMIT :batch_limit
            ),
            updated_chapters AS (
                UPDATE chapters ch
                SET images = {target_sql}
                FROM selected_chapters target
                WHERE ch.id = target.id
                RETURNING ch.id
            )
            SELECT COUNT(*)::int AS updated_count
            FROM updated_chapters
            """
        ),
        {**_params(args), "batch_limit": batch_limit},
    )
    return int(result.scalar_one() or 0)


async def apply_reset(engine, args: argparse.Namespace) -> int:
    total_updated = 0
    batch_number = 0

    while True:
        if args.limit > 0:
            remaining = args.limit - total_updated
            if remaining <= 0:
                break
            batch_limit = min(args.batch_size, remaining)
        else:
            batch_limit = args.batch_size

        batch_number += 1
        async with engine.begin() as conn:
            updated = await with_cli_loader(
                reset_images_batch(conn, args, batch_limit),
                f"Menjalankan batch {batch_number} (maks {batch_limit} chapter)",
            )

        if updated == 0:
            break

        total_updated += updated
        logger.info(
            "Batch %s: %s chapter di-reset (total %s).",
            batch_number,
            updated,
            total_updated,
        )

        if updated < batch_limit:
            break

    return total_updated


def format_bytes(value: int) -> str:
    units = ("B", "KB", "MB", "GB")
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.2f} {unit}"
        amount /= 1024
    return f"{amount:.2f} GB"


def pct(part: int, whole: int) -> str:
    if whole <= 0:
        return "0.00%"
    return f"{(part / whole) * 100:.2f}%"


def log_database_summary(summary: dict[str, Any]) -> None:
    database_bytes = int(summary["database_bytes"] or 0)
    chapters_total_bytes = int(summary["chapters_total_bytes"] or 0)
    images_json_bytes = int(summary["images_json_bytes"] or 0)

    logger.info("=" * 72)
    logger.info("Ringkasan database saat ini")
    logger.info("=" * 72)
    logger.info(
        "Database           : %s | %s",
        summary["database_name"],
        format_bytes(database_bytes),
    )
    logger.info(
        "public.chapters    : %s (%s dari database)",
        format_bytes(chapters_total_bytes),
        pct(chapters_total_bytes, database_bytes),
    )
    logger.info(
        "  table/index/toast : %s / %s / %s",
        format_bytes(int(summary["chapters_table_bytes"] or 0)),
        format_bytes(int(summary["chapters_index_bytes"] or 0)),
        format_bytes(int(summary["chapters_toast_bytes"] or 0)),
    )
    logger.info("Chapter total      : %s", summary["chapter_count"])
    logger.info("images NULL        : %s", summary["images_null_count"])
    logger.info("images []          : %s", summary["images_empty_count"])
    logger.info("images filled      : %s", summary["images_filled_count"])
    logger.info("image item count   : %s", summary["image_item_count"])
    logger.info(
        "images JSONB column: %s (%s dari database)",
        format_bytes(images_json_bytes),
        pct(images_json_bytes, database_bytes),
    )


def log_script_summary(
    *,
    args: argparse.Namespace,
    target_label: str,
    scope_label: str,
    limit_label: str,
    policy_label: str,
    candidate_summary: dict[str, int],
) -> None:
    logger.info("=" * 72)
    logger.info("Reset chapters.images ke backlog")
    logger.info("=" * 72)
    logger.info("Mode        : %s", "APPLY" if args.apply else "DRY-RUN")
    logger.info("Target      : %s", target_label)
    logger.info("Scope       : %s", scope_label)
    logger.info("Policy      : %s", policy_label)
    logger.info("Limit       : %s", limit_label)
    logger.info("Batch size  : %s", args.batch_size)
    logger.info("Candidate   : %s chapter", candidate_summary["chapter_count"])
    logger.info("Image item  : %s", candidate_summary["image_item_count"])
    logger.info("JSON size   : %s", format_bytes(candidate_summary["image_json_bytes"]))


async def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    configure_logging(args.log_file, default_filename=DEFAULT_LOG_FILE)

    target_label = "NULL" if args.target == TARGET_NULL else "[]"
    scope_label = args.source or "semua source"
    if args.limit == 0:
        limit_label = "semua yang cocok"
    elif args.mode == MODE_RANDOM:
        limit_label = f"{args.limit} chapter acak"
    else:
        limit_label = f"{args.limit} chapter pertama dari policy"
    policy_label = args.mode
    if args.mode == MODE_OLDER_THAN_LATEST:
        policy_label = (
            f"{args.mode} "
            f"(komik > {args.min_comic_chapters} chapter, keep latest {args.keep_latest})"
        )

    engine = create_engine()
    try:
        async with engine.begin() as conn:
            database_summary = await with_cli_loader(
                get_current_database_summary(conn),
                "Menghitung ringkasan database saat ini",
            )
            log_database_summary(database_summary)

            summary = await with_cli_loader(
                summarize(conn, args),
                "Menghitung kandidat chapter yang akan di-reset",
            )
            log_script_summary(
                args=args,
                target_label=target_label,
                scope_label=scope_label,
                limit_label=limit_label,
                policy_label=policy_label,
                candidate_summary=summary,
            )

            if not args.apply:
                rows = await with_cli_loader(
                    load_dry_run_targets(
                        conn,
                        args,
                        candidate_count=summary["chapter_count"],
                    ),
                    "Memuat daftar target dry-run",
                )
                listed_count = log_dry_run_targets(
                    rows,
                    args,
                    candidate_count=summary["chapter_count"],
                )
                logger.info("Dry-run target ditampilkan: %s chapter.", listed_count)
                logger.info("Dry-run selesai. Tambahkan --apply untuk menjalankan update.")
                return

        updated = await apply_reset(engine, args)
        logger.info("Selesai. %s chapter di-reset ke %s.", updated, target_label)
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
