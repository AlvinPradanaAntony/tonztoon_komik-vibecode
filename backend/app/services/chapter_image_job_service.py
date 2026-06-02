"""
Lazy image queue khusus source yang membutuhkan browser worker.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence

from sqlalchemy import case, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Chapter, ChapterImageJob

logger = logging.getLogger("service.chapter_image_job")

KOMIKU_ASIA_SOURCE = "komiku_asia"
REQUESTED_CHAPTER_PRIORITY = 100
NEARBY_CHAPTER_PRIORITY = 10
RETRY_AFTER_SECONDS = 5
CHAPTER_IMAGE_JOB_UPSERT_CHUNK_SIZE = 500


def _chunked(items: list[int], size: int = CHAPTER_IMAGE_JOB_UPSERT_CHUNK_SIZE):
    for offset in range(0, len(items), size):
        yield items[offset : offset + size]


def build_chapter_image_job_upsert_statement(
    chapter_ids: Sequence[int],
    *,
    priority: int,
):
    """Bangun bulk upsert job image chapter tanpa commit transaction caller."""
    rows = [
        {
            "chapter_id": chapter_id,
            "priority": priority,
            "status": "pending",
        }
        for chapter_id in chapter_ids
    ]
    stmt = insert(ChapterImageJob).values(rows)
    return stmt.on_conflict_do_update(
        index_elements=[ChapterImageJob.chapter_id],
        set_={
            "priority": func.greatest(ChapterImageJob.priority, priority),
            "status": case(
                (ChapterImageJob.status == "processing", "processing"),
                (ChapterImageJob.status == "failed", "failed"),
                else_="pending",
            ),
            "available_at": case(
                (
                    ChapterImageJob.status.in_(("pending", "processing", "failed")),
                    ChapterImageJob.available_at,
                ),
                else_=func.now(),
            ),
            "completed_at": None,
            "attempts": case(
                (ChapterImageJob.status == "completed", 0),
                else_=ChapterImageJob.attempts,
            ),
            "last_error": case(
                (ChapterImageJob.status == "failed", ChapterImageJob.last_error),
                else_=None,
            ),
            "updated_at": func.now(),
        },
    )


async def enqueue_komiku_asia_chapter_image_jobs(
    db: AsyncSession,
    chapter_ids: Sequence[int],
    *,
    priority: int,
) -> int:
    """Masukkan chapter ke antrean secara idempoten dan naikkan prioritas bila perlu."""
    normalized_ids = list(dict.fromkeys(chapter_ids))
    if not normalized_ids:
        return 0

    for chunk in _chunked(normalized_ids):
        await db.execute(
            build_chapter_image_job_upsert_statement(
                chunk,
                priority=priority,
            )
        )
    return len(normalized_ids)


async def enqueue_komiku_asia_nearby_chapters(
    db: AsyncSession,
    *,
    comic_id: int,
    current_chapter_number: float,
    window: int,
) -> int:
    """Antrekan nearby chapter yang cache images-nya belum siap."""
    from app.services.chapter_service import chapter_images_are_invalid_expression

    result = await db.execute(
        select(Chapter.id).where(
            Chapter.comic_id == comic_id,
            Chapter.chapter_number >= current_chapter_number - window,
            Chapter.chapter_number <= current_chapter_number + window,
            Chapter.chapter_number != current_chapter_number,
            chapter_images_are_invalid_expression(),
        )
    )
    chapter_ids = list(result.scalars().all())
    return await enqueue_komiku_asia_chapter_image_jobs(
        db,
        chapter_ids,
        priority=NEARBY_CHAPTER_PRIORITY,
    )
