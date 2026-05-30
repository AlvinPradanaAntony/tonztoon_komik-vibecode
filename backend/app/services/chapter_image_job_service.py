"""
Lazy image queue khusus source yang membutuhkan browser worker.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Sequence

import httpx
from sqlalchemy import case, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Chapter, ChapterImageJob

logger = logging.getLogger("service.chapter_image_job")

KOMIKU_ASIA_SOURCE = "komiku_asia"
REQUESTED_CHAPTER_PRIORITY = 100
NEARBY_CHAPTER_PRIORITY = 10
RETRY_AFTER_SECONDS = 5
ACTIVE_WORKFLOW_RUN_STATUSES = {
    "in_progress",
    "pending",
    "queued",
    "requested",
    "waiting",
}

_dispatch_lock = asyncio.Lock()
_last_dispatch_monotonic = 0.0


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

    for chapter_id in normalized_ids:
        stmt = insert(ChapterImageJob).values(
            chapter_id=chapter_id,
            priority=priority,
            status="pending",
        )
        stmt = stmt.on_conflict_do_update(
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
        await db.execute(stmt)
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


async def dispatch_komiku_asia_lazy_worker() -> bool:
    """Trigger queue drainer GitHub Actions dengan debounce per backend process."""
    global _last_dispatch_monotonic

    if not settings.GITHUB_PAT or not settings.GITHUB_REPO_OWNER:
        logger.warning(
            "Lazy worker Komiku Asia belum ditrigger: konfigurasi GitHub API belum lengkap."
        )
        return False

    async with _dispatch_lock:
        now = time.monotonic()
        if now - _last_dispatch_monotonic < settings.KOMIKU_ASIA_LAZY_DISPATCH_COOLDOWN_SECONDS:
            return False

        api_url = (
            "https://api.github.com/repos/"
            f"{settings.GITHUB_REPO_OWNER}/{settings.GITHUB_REPO_NAME}/"
            "actions/workflows/"
            f"{settings.GITHUB_KOMIKU_ASIA_LAZY_WORKFLOW_FILE}/dispatches"
        )
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {settings.GITHUB_PAT}",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        runs_url = api_url.removesuffix("/dispatches") + "/runs"
        payload = {
            "ref": "main",
            "inputs": {"trigger_source": "reader_lazy_load"},
        }

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                runs_response = await client.get(
                    runs_url,
                    headers=headers,
                    params={
                        "branch": "main",
                        "event": "workflow_dispatch",
                        "per_page": 20,
                    },
                )
                if runs_response.status_code == 200:
                    workflow_runs = runs_response.json().get("workflow_runs", [])
                    active_run = next(
                        (
                            run
                            for run in workflow_runs
                            if run.get("status") in ACTIVE_WORKFLOW_RUN_STATUSES
                        ),
                        None,
                    )
                    if active_run is not None:
                        _last_dispatch_monotonic = now
                        logger.info(
                            "Lazy worker Komiku Asia tidak ditrigger ulang: "
                            "workflow run aktif id=%s status=%s.",
                            active_run.get("id"),
                            active_run.get("status"),
                        )
                        return False
                else:
                    logger.warning(
                        "Gagal mengecek workflow lazy worker aktif: status=%s body=%s",
                        runs_response.status_code,
                        runs_response.text,
                    )

                response = await client.post(api_url, json=payload, headers=headers)
            if response.status_code != 204:
                logger.warning(
                    "Gagal trigger lazy worker Komiku Asia: status=%s body=%s",
                    response.status_code,
                    response.text,
                )
                return False
        except httpx.HTTPError as exc:
            logger.warning("Gagal menghubungi GitHub API untuk lazy worker: %s", exc)
            return False

        _last_dispatch_monotonic = now
        logger.info("Lazy worker Komiku Asia berhasil ditrigger.")
        return True


def schedule_komiku_asia_lazy_worker_dispatch() -> None:
    """Jalankan dispatch tanpa menahan response reader."""
    task = asyncio.create_task(
        dispatch_komiku_asia_lazy_worker(),
        name="dispatch-komiku-asia-lazy-worker",
    )

    def _log_task_error(done_task: asyncio.Task) -> None:
        try:
            done_task.result()
        except Exception:
            logger.exception("Dispatch lazy worker Komiku Asia gagal tidak terduga.")

    task.add_done_callback(_log_task_error)
