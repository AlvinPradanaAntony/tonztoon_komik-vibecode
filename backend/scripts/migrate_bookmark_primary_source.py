"""Pindahkan source utama bookmark lintas source yang sudah terhubung.

Script ini hanya memakai relasi yang sudah tersimpan pada
``user_bookmark_links``. Ia tidak mencari kandidat baru. Saat source tujuan
ada sebagai alternatif, komik tersebut menjadi bookmark utama dan source utama
lama dipertahankan sebagai alternatif. Jika tidak ada alternatif pada source
tujuan, bookmark dibiarkan tanpa perubahan.

Default-nya dry-run. Tambahkan ``--apply`` setelah meninjau hasilnya.

Usage (dari folder backend/):
    python -m scripts.migrate_bookmark_primary_source
    python -m scripts.migrate_bookmark_primary_source --user-id <UUID>
    python -m scripts.migrate_bookmark_primary_source --user-id <UUID> --target-source shinigami
    python -m scripts.migrate_bookmark_primary_source --user-id <UUID> --target-source shinigami --apply
    python -m scripts.migrate_bookmark_primary_source --user-id <UUID> --target-source shinigami --apply --yes
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine, create_async_engine

# Pastikan backend/ ada di sys.path saat script dipanggil sebagai module.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings
from scraper.sources.registry import SOURCE_LABELS, get_supported_source_names
from scraper.time_utils import now_wib
from scraper.utils import (
    CliLiveProgress,
    RealtimeConsoleHandler,
    configure_external_loggers,
    configure_logging,
    format_elapsed_duration,
)


DEFAULT_LOG_FILE = "migrate_bookmark_primary_source.log"
DEFAULT_DRY_RUN_LIST_LIMIT = 200
logger = logging.getLogger("migrate-bookmark-primary-source")


@dataclass(frozen=True)
class BookmarkRecord:
    bookmark_id: int
    comic_id: int
    source_name: str
    title: str
    slug: str


@dataclass(frozen=True)
class BookmarkLinkRecord:
    link_id: int
    bookmark_id: int
    comic_id: int
    source_name: str
    title: str
    slug: str
    confidence: float


@dataclass(frozen=True)
class MigrationAction:
    bookmark: BookmarkRecord
    target: BookmarkLinkRecord


@dataclass(frozen=True)
class MigrationSkip:
    bookmark: BookmarkRecord
    reason: str


@dataclass(frozen=True)
class MigrationPlan:
    actions: list[MigrationAction]
    skips: list[MigrationSkip]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Migrasikan source utama bookmark ke source alternatif yang sudah "
            "terhubung. Default: dry-run."
        )
    )
    parser.add_argument(
        "--user-id",
        help="UUID akun target. Jika tidak diisi, script akan meminta input.",
    )
    parser.add_argument(
        "--target-source",
        help="Source utama tujuan. Jika tidak diisi, script akan meminta pilihan.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Jalankan migrasi. Tanpa flag ini script hanya melakukan dry-run.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Lewati konfirmasi interaktif saat memakai --apply.",
    )
    parser.add_argument(
        "--dry-run-list-limit",
        type=int,
        default=DEFAULT_DRY_RUN_LIST_LIMIT,
        help=(
            "Maksimum aksi/skip yang dirinci saat dry-run. "
            "0 berarti tampilkan semua. Default: 200."
        ),
    )
    parser.add_argument(
        "--log-file",
        help="Path file log. Jika relatif, disimpan di backend/logs/.",
    )
    args = parser.parse_args(argv)
    if args.dry_run_list_limit < 0:
        parser.error("--dry-run-list-limit harus >= 0")
    if args.user_id:
        args.user_id = args.user_id.strip()
    if args.target_source:
        args.target_source = args.target_source.strip().lower()
    return args


def create_engine() -> AsyncEngine:
    return create_async_engine(
        settings.DATABASE_URL,
        connect_args={
            "statement_cache_size": 0,
            "prepared_statement_cache_size": 0,
        },
    )


def parse_user_id(value: str) -> UUID:
    try:
        return UUID(value)
    except ValueError as exc:
        raise ValueError("UUID target tidak valid.") from exc


def prompt_user_id(value: str | None) -> UUID:
    if value:
        return parse_user_id(value)
    if not sys.stdin.isatty():
        raise RuntimeError("Isi --user-id saat menjalankan script tanpa terminal interaktif.")

    while True:
        raw = input("Masukkan UUID akun target: ").strip()
        try:
            return parse_user_id(raw)
        except ValueError as exc:
            logger.warning("%s", exc)


def available_sources() -> list[str]:
    return get_supported_source_names()


def prompt_target_source(value: str | None, sources: list[str]) -> str:
    if value:
        if value in sources:
            return value
        choices = ", ".join(sources)
        raise ValueError(f"--target-source harus salah satu dari: {choices}")

    if not sys.stdin.isatty():
        raise RuntimeError(
            "Isi --target-source saat menjalankan script tanpa terminal interaktif."
        )

    logger.info("Pilih source utama tujuan:")
    for index, source_name in enumerate(sources, start=1):
        logger.info("  %s. %s (%s)", index, SOURCE_LABELS.get(source_name, source_name), source_name)

    while True:
        raw = input("Nomor atau nama source tujuan: ").strip().lower()
        if raw.isdigit() and 1 <= int(raw) <= len(sources):
            return sources[int(raw) - 1]
        if raw in sources:
            return raw
        logger.warning("Pilihan tidak valid. Masukkan nomor 1-%s atau nama source.", len(sources))


async def with_cli_loader(awaitable, label: str):
    """Tampilkan spinner saat query awal berjalan, juga pada terminal non-TTY."""
    if not sys.stdout.isatty():
        logger.info("%s...", label)
        result = await awaitable
        logger.info("%s selesai.", label)
        return result

    progress = CliLiveProgress(label=label, total_steps=1)
    progress.start()
    try:
        result = await awaitable
        progress.advance("selesai")
        return result
    finally:
        await progress.stop()


async def load_bookmarks(
    conn: AsyncConnection,
    user_id: UUID,
) -> list[BookmarkRecord]:
    result = await conn.execute(
        text(
            """
            SELECT
                bookmark.id AS bookmark_id,
                comic.id AS comic_id,
                comic.source_name,
                comic.title,
                comic.slug
            FROM user_bookmarks AS bookmark
            JOIN comics AS comic ON comic.id = bookmark.comic_id
            WHERE bookmark.user_id = :user_id
            ORDER BY bookmark.id
            """
        ),
        {"user_id": user_id},
    )
    return [
        BookmarkRecord(
            bookmark_id=int(row["bookmark_id"]),
            comic_id=int(row["comic_id"]),
            source_name=str(row["source_name"]),
            title=str(row["title"]),
            slug=str(row["slug"]),
        )
        for row in result.mappings().all()
    ]


async def load_bookmark_links(
    conn: AsyncConnection,
    user_id: UUID,
) -> list[BookmarkLinkRecord]:
    result = await conn.execute(
        text(
            """
            SELECT
                link.id AS link_id,
                link.bookmark_id,
                comic.id AS comic_id,
                comic.source_name,
                comic.title,
                comic.slug,
                link.confidence
            FROM user_bookmark_links AS link
            JOIN user_bookmarks AS bookmark
                ON bookmark.id = link.bookmark_id
                AND bookmark.user_id = :user_id
            JOIN comics AS comic ON comic.id = link.comic_id
            WHERE link.user_id = :user_id
            ORDER BY link.bookmark_id, link.id
            """
        ),
        {"user_id": user_id},
    )
    return [
        BookmarkLinkRecord(
            link_id=int(row["link_id"]),
            bookmark_id=int(row["bookmark_id"]),
            comic_id=int(row["comic_id"]),
            source_name=str(row["source_name"]),
            title=str(row["title"]),
            slug=str(row["slug"]),
            confidence=float(row["confidence"]),
        )
        for row in result.mappings().all()
    ]


def build_migration_plan(
    bookmarks: list[BookmarkRecord],
    links: list[BookmarkLinkRecord],
    target_source: str,
) -> MigrationPlan:
    """Buat rencana aman tanpa mengubah database."""
    links_by_bookmark: dict[int, list[BookmarkLinkRecord]] = defaultdict(list)
    link_owner_by_comic: dict[int, int] = {}
    for link in links:
        links_by_bookmark[link.bookmark_id].append(link)
        link_owner_by_comic[link.comic_id] = link.bookmark_id

    direct_owner_by_comic = {bookmark.comic_id: bookmark.bookmark_id for bookmark in bookmarks}
    actions: list[MigrationAction] = []
    skips: list[MigrationSkip] = []

    for bookmark in bookmarks:
        if bookmark.source_name == target_source:
            skips.append(MigrationSkip(bookmark, "sudah memakai source tujuan"))
            continue

        target_links = [
            link
            for link in links_by_bookmark.get(bookmark.bookmark_id, [])
            if link.source_name == target_source
        ]
        if not target_links:
            skips.append(
                MigrationSkip(
                    bookmark,
                    "tidak memiliki alternatif pada source tujuan",
                )
            )
            continue
        if len(target_links) > 1:
            skips.append(
                MigrationSkip(
                    bookmark,
                    "memiliki lebih dari satu alternatif pada source tujuan",
                )
            )
            continue

        target = target_links[0]
        direct_owner = direct_owner_by_comic.get(target.comic_id)
        if direct_owner is not None and direct_owner != bookmark.bookmark_id:
            skips.append(
                MigrationSkip(
                    bookmark,
                    "komik tujuan sudah menjadi bookmark utama lain",
                )
            )
            continue

        old_primary_link_owner = link_owner_by_comic.get(bookmark.comic_id)
        if old_primary_link_owner is not None and old_primary_link_owner != bookmark.bookmark_id:
            skips.append(
                MigrationSkip(
                    bookmark,
                    "komik utama lama sudah menjadi alternatif bookmark lain",
                )
            )
            continue

        actions.append(MigrationAction(bookmark=bookmark, target=target))

    return MigrationPlan(actions=actions, skips=skips)


def log_source_summary(
    bookmarks: list[BookmarkRecord],
    links: list[BookmarkLinkRecord],
) -> None:
    primary_counts = Counter(bookmark.source_name for bookmark in bookmarks)
    alternative_counts = Counter(link.source_name for link in links)

    logger.info("═" * 60)
    logger.info("📊 Ringkasan bookmark akun")
    logger.info("   Bookmark utama    : %s", len(bookmarks))
    logger.info("   Relasi alternatif : %s", len(links))
    logger.info("   Source utama:")
    if primary_counts:
        for source_name, count in sorted(primary_counts.items()):
            logger.info("     %-14s : %s bookmark", source_name, count)
    else:
        logger.info("     (tidak ada bookmark utama)")
    logger.info("   Source alternatif:")
    if alternative_counts:
        for source_name, count in sorted(alternative_counts.items()):
            logger.info("     %-14s : %s relasi", source_name, count)
    else:
        logger.info("     (tidak ada relasi alternatif)")
    logger.info("═" * 60)


def log_plan_summary(plan: MigrationPlan, target_source: str) -> None:
    skip_counts = Counter(skip.reason for skip in plan.skips)
    logger.info("═" * 60)
    logger.info("🧭 Rencana migrasi ke source: %s", target_source)
    logger.info("   Akan dimigrasikan : %s bookmark", len(plan.actions))
    logger.info("   Dilewati          : %s bookmark", len(plan.skips))
    for reason, count in sorted(skip_counts.items()):
        logger.info("     %-50s : %s", reason, count)
    logger.info("═" * 60)


def _log_action(prefix: str, action: MigrationAction) -> None:
    logger.info(
        "%s 🔄 bookmark #%s: [%s] %s → [%s] %s",
        prefix,
        action.bookmark.bookmark_id,
        action.bookmark.source_name,
        action.bookmark.title,
        action.target.source_name,
        action.target.title,
    )


def log_dry_run_details(plan: MigrationPlan, limit: int) -> None:
    items: list[tuple[str, MigrationAction | MigrationSkip]] = [
        ("MIGRATE", action) for action in plan.actions
    ] + [("SKIP", skip) for skip in plan.skips]
    shown = items if limit == 0 else items[:limit]

    logger.info("═" * 60)
    logger.info("🔍 Detail dry-run (%s dari %s entri):", len(shown), len(items))
    for kind, item in shown:
        if kind == "MIGRATE":
            _log_action("DRY-RUN", item)
        else:
            logger.info(
                "⏭️ SKIP bookmark #%s: [%s] %s (%s)",
                item.bookmark.bookmark_id,
                item.bookmark.source_name,
                item.bookmark.title,
                item.reason,
            )
    if len(shown) < len(items):
        logger.info(
            "ℹ️ Detail dipotong. Gunakan --dry-run-list-limit 0 untuk menampilkan semua."
        )
    logger.info("═" * 60)


def confirm_apply(args: argparse.Namespace, *, user_id: UUID, target_source: str) -> None:
    if args.yes:
        return
    if not sys.stdin.isatty():
        raise RuntimeError("Tambahkan --yes untuk memakai --apply tanpa terminal interaktif.")
    confirmation = input(
        f"Ketik MIGRATE untuk memindahkan bookmark {user_id} ke {target_source}: "
    ).strip()
    if confirmation != "MIGRATE":
        raise RuntimeError("Migrasi dibatalkan; konfirmasi tidak cocok.")


def log_completion_summary(
    *,
    started_at: datetime,
    target_source: str,
    elapsed: float,
    migrated: int,
    skipped: int,
    dry_run: bool,
) -> None:
    """Summary penutup dengan format yang sama seperti pipeline scraper."""
    finished_at = now_wib()
    mode_label = "DRY-RUN" if dry_run else "APPLY"
    status_label = "🧪 simulasi selesai" if dry_run else "✅ berhasil"
    logger.info("═" * 60)
    logger.info(
        "%s %s Source Utama Bookmark selesai!",
        "🔍" if dry_run else "🏁",
        mode_label,
    )
    logger.info("   Mulai          : %s", started_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Selesai        : %s", finished_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Waktu          : %s", format_elapsed_duration(elapsed))
    logger.info("   Source tujuan  : %s", target_source)
    logger.info("   Kandidat       : %s bookmark", migrated + skipped)
    logger.info("   Dimigrasikan   : %s bookmark", migrated)
    logger.info("   Dilewati       : %s bookmark", skipped)
    logger.info("   Status         : %s", status_label)
    logger.info("   Catatan        : bookmark tanpa alternatif tujuan tetap tidak berubah")
    logger.info("═" * 60)


async def apply_migration(
    conn: AsyncConnection,
    user_id: UUID,
    plan: MigrationPlan,
) -> int:
    """Jalankan semua aksi dalam transaksi caller."""
    progress = CliLiveProgress(label="Memigrasikan bookmark", total_steps=len(plan.actions))
    progress.start()
    try:
        for index, action in enumerate(plan.actions, start=1):
            _log_action(f"PROSES {index}/{len(plan.actions)}", action)
            delete_result = await conn.execute(
                text(
                    """
                    DELETE FROM user_bookmark_links
                    WHERE id = :link_id
                      AND user_id = :user_id
                      AND bookmark_id = :bookmark_id
                    RETURNING id
                    """
                ),
                {
                    "link_id": action.target.link_id,
                    "user_id": user_id,
                    "bookmark_id": action.bookmark.bookmark_id,
                },
            )
            if delete_result.scalar_one_or_none() is None:
                raise RuntimeError(
                    f"Relasi target bookmark #{action.bookmark.bookmark_id} tidak lagi tersedia."
                )

            update_result = await conn.execute(
                text(
                    """
                    UPDATE user_bookmarks
                    SET comic_id = :target_comic_id,
                        updated_at = NOW()
                    WHERE id = :bookmark_id
                      AND user_id = :user_id
                    RETURNING id
                    """
                ),
                {
                    "target_comic_id": action.target.comic_id,
                    "bookmark_id": action.bookmark.bookmark_id,
                    "user_id": user_id,
                },
            )
            if update_result.scalar_one_or_none() is None:
                raise RuntimeError(f"Bookmark #{action.bookmark.bookmark_id} tidak lagi tersedia.")

            await conn.execute(
                text(
                    """
                    INSERT INTO user_bookmark_links (
                        user_id,
                        bookmark_id,
                        comic_id,
                        confidence
                    ) VALUES (
                        :user_id,
                        :bookmark_id,
                        :old_comic_id,
                        :confidence
                    )
                    """
                ),
                {
                    "user_id": user_id,
                    "bookmark_id": action.bookmark.bookmark_id,
                    "old_comic_id": action.bookmark.comic_id,
                    "confidence": 1.0,
                },
            )
            progress.advance(f"bookmark #{action.bookmark.bookmark_id}")
            logger.info("  ✅ Selesai bookmark #%s.", action.bookmark.bookmark_id)
    finally:
        await progress.stop()
    return len(plan.actions)


async def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    started_at = now_wib()
    start_time = time.monotonic()
    configure_logging(
        args.log_file,
        default_filename=DEFAULT_LOG_FILE,
        stdout_handler=RealtimeConsoleHandler(sys.stdout),
    )
    configure_external_loggers()
    logger.info("═" * 60)
    logger.info("🚀 Migrasi Source Utama Bookmark dimulai — %s", started_at.isoformat())
    logger.info("   Mode            : %s", "APPLY" if args.apply else "DRY-RUN")
    logger.info("   UUID target     : %s", args.user_id or "input interaktif")
    logger.info("   Source tujuan   : %s", args.target_source or "pilihan interaktif")
    logger.info(
        "   Kebijakan      : alternatif source tujuan wajib sudah tersedia; "
        "data lain tetap."
    )
    logger.info("═" * 60)

    user_id = prompt_user_id(args.user_id)
    engine = create_engine()
    try:
        async with engine.connect() as conn:
            bookmarks, links = await with_cli_loader(
                asyncio.gather(
                    load_bookmarks(conn, user_id),
                    load_bookmark_links(conn, user_id),
                ),
                "Memuat bookmark dan relasi source akun",
            )

        log_source_summary(bookmarks, links)
        if not bookmarks:
            logger.info("ℹ️ Tidak ada bookmark untuk dimigrasikan. Selesai.")
            return

        target_source = prompt_target_source(args.target_source, available_sources())
        logger.info("🎯 Source utama tujuan dipilih: %s", target_source)
        plan = build_migration_plan(bookmarks, links, target_source)
        log_plan_summary(plan, target_source)

        if not args.apply:
            log_dry_run_details(plan, args.dry_run_list_limit)
            log_completion_summary(
                started_at=started_at,
                target_source=target_source,
                elapsed=time.monotonic() - start_time,
                migrated=len(plan.actions),
                skipped=len(plan.skips),
                dry_run=True,
            )
            logger.info("ℹ️ Tambahkan --apply untuk menjalankan migrasi.")
            return

        if not plan.actions:
            logger.info("ℹ️ Tidak ada bookmark yang perlu dimigrasikan. Selesai.")
            return

        confirm_apply(args, user_id=user_id, target_source=target_source)
        async with engine.begin() as conn:
            migrated = await apply_migration(conn, user_id, plan)
        log_completion_summary(
            started_at=started_at,
            target_source=target_source,
            elapsed=time.monotonic() - start_time,
            migrated=migrated,
            skipped=len(plan.skips),
            dry_run=False,
        )
    finally:
        await engine.dispose()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (RuntimeError, ValueError) as exc:
        logger.error("%s", exc)
        raise SystemExit(2) from exc
