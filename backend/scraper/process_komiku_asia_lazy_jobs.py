"""
Drain lazy chapter image jobs Komiku Asia melalui browser worker sequential.

Usage:
    python -m scraper.process_komiku_asia_lazy_jobs
    python -m scraper.process_komiku_asia_lazy_jobs --limit 10
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime, timedelta
import logging
from pathlib import Path
import sys

from sqlalchemy import func, or_, select

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Chapter, ChapterImageJob, Comic
from app.services.chapter_image_job_service import (
    KOMIKU_ASIA_SOURCE,
    REQUESTED_CHAPTER_PRIORITY,
    enqueue_komiku_asia_nearby_chapters,
)
from app.services.chapter_service import (
    PREFETCH_WINDOW,
    ImageFetchError,
    chapter_images_are_ready,
    fetch_and_save_chapter_images,
)
from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper
from scraper.utils import configure_external_loggers, configure_logging

logger = logging.getLogger("scraper.komiku_asia_lazy_jobs")

DEFAULT_LIMIT = 10
IMAGE_FETCH_TIMEOUT_SECONDS = 120.0
STALE_CLAIM_MINUTES = 10
MAX_RETRY_DELAY_SECONDS = 15 * 60


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Drain lazy-load chapter image queue khusus Komiku Asia.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_LIMIT,
        help=f"Maksimum job per run. Default: {DEFAULT_LIMIT}.",
    )
    parser.add_argument(
        "--log-file",
        default="komiku_asia_lazy_jobs.log",
        help="Nama log relatif terhadap backend/logs atau absolute path.",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Hanya cek apakah ada job siap proses tanpa membuka browser.",
    )
    parser.add_argument(
        "--github-output",
        help="Opsional: tulis has_pending dan pending_count ke file GITHUB_OUTPUT.",
    )
    args = parser.parse_args(argv)
    if args.limit < 1:
        parser.error("--limit harus >= 1")
    return args


async def claim_next_job() -> tuple[int, int, int] | None:
    """Claim satu job siap proses agar worker paralel tidak mengerjakan chapter sama."""
    now = datetime.now(UTC)

    async with async_session() as db:
        result = await db.execute(
            select(ChapterImageJob)
            .join(Chapter, Chapter.id == ChapterImageJob.chapter_id)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(
                Comic.source_name == KOMIKU_ASIA_SOURCE,
                *ready_job_expression(now),
            )
            .order_by(
                ChapterImageJob.priority.desc(),
                ChapterImageJob.available_at.asc(),
                ChapterImageJob.created_at.asc(),
            )
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        job = result.scalars().first()
        if job is None:
            return None

        job.status = "processing"
        job.claimed_at = now
        job.attempts += 1
        job.last_error = None
        await db.commit()
        return job.id, job.chapter_id, job.priority


def ready_job_expression(now: datetime):
    """Expression job siap proses termasuk claim lama yang perlu dipulihkan."""
    stale_before = now - timedelta(minutes=STALE_CLAIM_MINUTES)
    return (
        or_(
            ChapterImageJob.status.in_(("pending", "failed")),
            (
                (ChapterImageJob.status == "processing")
                & (ChapterImageJob.claimed_at < stale_before)
            ),
        ),
        ChapterImageJob.available_at <= now,
    )


async def count_ready_jobs() -> int:
    """Hitung job Komiku Asia yang siap diproses tanpa membuka browser."""
    now = datetime.now(UTC)
    async with async_session() as db:
        result = await db.execute(
            select(func.count())
            .select_from(ChapterImageJob)
            .join(Chapter, Chapter.id == ChapterImageJob.chapter_id)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(
                Comic.source_name == KOMIKU_ASIA_SOURCE,
                *ready_job_expression(now),
            )
        )
        return int(result.scalar_one() or 0)


async def mark_job_completed(job_id: int) -> None:
    async with async_session() as db:
        job = await db.get(ChapterImageJob, job_id)
        if job is None:
            return
        now = datetime.now(UTC)
        job.status = "completed"
        job.completed_at = now
        job.claimed_at = None
        job.last_error = None
        await db.commit()


async def mark_job_failed(job_id: int, message: str) -> None:
    async with async_session() as db:
        job = await db.get(ChapterImageJob, job_id)
        if job is None:
            return
        delay_seconds = min(30 * (2 ** max(job.attempts - 1, 0)), MAX_RETRY_DELAY_SECONDS)
        job.status = "failed"
        job.available_at = datetime.now(UTC) + timedelta(seconds=delay_seconds)
        job.claimed_at = None
        job.last_error = message[:2000]
        await db.commit()


async def process_job(job_id: int, chapter_id: int, priority: int) -> bool:
    async with async_session() as db:
        chapter = await db.get(Chapter, chapter_id)
        if chapter is None:
            await mark_job_failed(job_id, f"Chapter {chapter_id} tidak ditemukan.")
            return False

        logger.info(
            "Memproses job=%s chapter_id=%s Ch %s",
            job_id,
            chapter.id,
            chapter.chapter_number,
        )
        try:
            if not chapter_images_are_ready(chapter.images):
                ok = await fetch_and_save_chapter_images(
                    chapter=chapter,
                    source_name=KOMIKU_ASIA_SOURCE,
                    timeout_seconds=IMAGE_FETCH_TIMEOUT_SECONDS,
                    db=db,
                )
                if not ok:
                    raise ImageFetchError("Tidak ada images ditemukan pada halaman chapter.")

            queued_nearby = 0
            if priority >= REQUESTED_CHAPTER_PRIORITY:
                queued_nearby = await enqueue_komiku_asia_nearby_chapters(
                    db,
                    comic_id=chapter.comic_id,
                    current_chapter_number=chapter.chapter_number,
                    window=PREFETCH_WINDOW,
                )
            await db.commit()
            await mark_job_completed(job_id)
            logger.info(
                "Selesai job=%s chapter_id=%s; nearby queued=%s",
                job_id,
                chapter.id,
                queued_nearby,
            )
            return True
        except ImageFetchError as exc:
            await mark_job_failed(job_id, str(exc))
            logger.warning("Gagal job=%s chapter_id=%s: %s", job_id, chapter.id, exc)
            return False
        except Exception as exc:
            await db.rollback()
            await mark_job_failed(job_id, f"{type(exc).__name__}: {exc}")
            logger.exception("Error tidak terduga job=%s chapter_id=%s", job_id, chapter.id)
            return False


async def run(limit: int) -> None:
    processed = 0
    succeeded = 0
    try:
        while processed < limit:
            claimed = await claim_next_job()
            if claimed is None:
                break
            processed += 1
            job_id, chapter_id, priority = claimed
            if await process_job(job_id, chapter_id, priority):
                succeeded += 1
    finally:
        await KomikuAsiaScraper.close_shared_session()

    logger.info("Lazy queue selesai: processed=%s succeeded=%s", processed, succeeded)


def main() -> None:
    args = parse_args()
    configure_logging(args.log_file)
    configure_external_loggers()
    if args.check_only:
        pending_count = asyncio.run(count_ready_jobs())
        has_pending = pending_count > 0
        print(f"Ready Komiku Asia lazy jobs: {pending_count}")
        if args.github_output:
            with open(args.github_output, "a", encoding="utf-8") as output:
                output.write(f"has_pending={'true' if has_pending else 'false'}\n")
                output.write(f"pending_count={pending_count}\n")
        return
    asyncio.run(run(args.limit))


if __name__ == "__main__":
    main()
