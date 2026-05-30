"""
Tonztoon Komik — Komiku Asia In-Process Background Worker

Background worker yang berjalan di dalam proses FastAPI untuk memproses
antrean chapter image jobs Komiku Asia secara langsung di container
Hugging Face, tanpa perlu memicu GitHub Actions workflow.

Arsitektur:
    - Worker berjalan sebagai asyncio task di dalam event loop FastAPI.
    - Memantau tabel `ChapterImageJob` setiap beberapa detik (polling).
    - Saat ada job, memproses secara sequential (satu per satu) menggunakan
      browser headless Scrapling yang sama dengan cron scraper.
    - Browser session di-reuse antar job dan ditutup otomatis setelah idle
      untuk menghemat memory.

Keuntungan vs GitHub Actions dispatch:
    - Latensi setup ~0 detik (vs ~45 detik untuk runner spin-up)
    - User mendapatkan gambar chapter dalam ~5-10 detik
    - Tidak ada ketergantungan pada GitHub API rate limit
"""

from __future__ import annotations

import asyncio
import logging
import time

from app.config import settings

logger = logging.getLogger("service.komiku_asia_worker")

_worker_task: asyncio.Task | None = None
_shutdown_event: asyncio.Event | None = None


async def _claim_and_process_one_job() -> bool:
    """
    Claim satu job dari antrean dan proses.

    Return True jika ada job yang berhasil di-claim (terlepas dari hasil
    pemrosesan), False jika antrean kosong.
    """
    # Impor lazy untuk menghindari circular import saat modul di-load
    from app.database import async_session
    from app.models import Chapter, ChapterImageJob, Comic
    from app.services.chapter_image_job_service import (
        KOMIKU_ASIA_SOURCE,
        REQUESTED_CHAPTER_PRIORITY,
    )
    from app.services.chapter_service import (
        PREFETCH_WINDOW,
        ImageFetchError,
        chapter_images_are_ready,
        fetch_and_save_chapter_images,
    )
    from datetime import UTC, datetime, timedelta
    from sqlalchemy import func, or_, select

    STALE_CLAIM_MINUTES = 10
    IMAGE_FETCH_TIMEOUT = 120.0
    MAX_RETRY_DELAY_SECONDS = 15 * 60

    now = datetime.now(UTC)
    stale_before = now - timedelta(minutes=STALE_CLAIM_MINUTES)

    # ── Claim satu job ─────────────────────────────────────────────
    async with async_session() as db:
        result = await db.execute(
            select(ChapterImageJob)
            .join(Chapter, Chapter.id == ChapterImageJob.chapter_id)
            .join(Comic, Comic.id == Chapter.comic_id)
            .where(
                Comic.source_name == KOMIKU_ASIA_SOURCE,
                or_(
                    ChapterImageJob.status.in_(("pending", "failed")),
                    (
                        (ChapterImageJob.status == "processing")
                        & (ChapterImageJob.claimed_at < stale_before)
                    ),
                ),
                ChapterImageJob.available_at <= now,
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
            return False

        job_id = job.id
        chapter_id = job.chapter_id
        priority = job.priority

        job.status = "processing"
        job.claimed_at = now
        job.attempts += 1
        job.last_error = None
        await db.commit()

    logger.info(
        "Worker: claimed job=%s chapter_id=%s priority=%s",
        job_id,
        chapter_id,
        priority,
    )

    # ── Proses job ─────────────────────────────────────────────────
    async with async_session() as db:
        chapter = await db.get(Chapter, chapter_id)
        if chapter is None:
            await _mark_job_failed(job_id, f"Chapter {chapter_id} tidak ditemukan.")
            return True

        try:
            if not chapter_images_are_ready(chapter.images):
                ok = await fetch_and_save_chapter_images(
                    chapter=chapter,
                    source_name=KOMIKU_ASIA_SOURCE,
                    timeout_seconds=IMAGE_FETCH_TIMEOUT,
                    db=db,
                )
                if not ok:
                    raise ImageFetchError(
                        "Tidak ada images ditemukan pada halaman chapter."
                    )

            # Enqueue nearby chapters jika ini adalah request dari user
            queued_nearby = 0
            if priority >= REQUESTED_CHAPTER_PRIORITY:
                from app.services.chapter_image_job_service import (
                    enqueue_komiku_asia_nearby_chapters,
                )

                queued_nearby = await enqueue_komiku_asia_nearby_chapters(
                    db,
                    comic_id=chapter.comic_id,
                    current_chapter_number=chapter.chapter_number,
                    window=PREFETCH_WINDOW,
                )
            await db.commit()

            # Mark job completed
            await _mark_job_completed(job_id)
            logger.info(
                "Worker: completed job=%s chapter_id=%s; nearby queued=%s",
                job_id,
                chapter_id,
                queued_nearby,
            )
            return True

        except ImageFetchError as exc:
            await _mark_job_failed(job_id, str(exc))
            logger.warning(
                "Worker: failed job=%s chapter_id=%s: %s", job_id, chapter_id, exc
            )
            return True

        except Exception as exc:
            await db.rollback()
            await _mark_job_failed(job_id, f"{type(exc).__name__}: {exc}")
            logger.exception(
                "Worker: unexpected error job=%s chapter_id=%s", job_id, chapter_id
            )
            return True


async def _mark_job_completed(job_id: int) -> None:
    """Tandai job sebagai selesai."""
    from app.database import async_session
    from app.models import ChapterImageJob
    from datetime import UTC, datetime

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


async def _mark_job_failed(job_id: int, message: str) -> None:
    """Tandai job sebagai gagal dengan exponential backoff retry delay."""
    from app.database import async_session
    from app.models import ChapterImageJob
    from datetime import UTC, datetime, timedelta

    MAX_RETRY_DELAY_SECONDS = 15 * 60

    async with async_session() as db:
        job = await db.get(ChapterImageJob, job_id)
        if job is None:
            return
        delay_seconds = min(
            30 * (2 ** max(job.attempts - 1, 0)), MAX_RETRY_DELAY_SECONDS
        )
        job.status = "failed"
        job.available_at = datetime.now(UTC) + timedelta(seconds=delay_seconds)
        job.claimed_at = None
        job.last_error = message[:2000]
        await db.commit()


async def _close_browser_session() -> None:
    """Tutup Scrapling browser session untuk menghemat memory."""
    try:
        from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper

        await KomikuAsiaScraper.close_shared_session()
        logger.info("Worker: browser session ditutup (idle timeout).")
    except Exception as exc:
        logger.warning("Worker: gagal menutup browser session: %s", exc)


async def _worker_loop() -> None:
    """
    Loop utama worker yang memantau antrean dan memproses job.

    Strategi:
    - Poll antrean setiap POLL_SECONDS saat idle.
    - Saat ada job, proses langsung tanpa delay tambahan.
    - Tutup browser session setelah IDLE_CLOSE_SECONDS tanpa job.
    """
    poll_interval = settings.KOMIKU_ASIA_WORKER_POLL_SECONDS
    idle_close_seconds = settings.KOMIKU_ASIA_WORKER_IDLE_CLOSE_SECONDS

    last_job_time: float = 0.0
    browser_open = False

    logger.info(
        "Komiku Asia worker dimulai (poll=%.1fs, idle_close=%.0fs).",
        poll_interval,
        idle_close_seconds,
    )

    while not _shutdown_event.is_set():
        try:
            had_job = await _claim_and_process_one_job()

            if had_job:
                last_job_time = time.monotonic()
                browser_open = True
                # Langsung cek antrean lagi tanpa delay
                continue

            # Tidak ada job — cek apakah browser harus ditutup
            if browser_open and last_job_time > 0:
                idle_duration = time.monotonic() - last_job_time
                if idle_duration >= idle_close_seconds:
                    await _close_browser_session()
                    browser_open = False

        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Worker: error dalam loop utama: %s", exc, exc_info=True)

        # Tunggu sebelum polling berikutnya, bisa diinterupsi oleh shutdown
        try:
            await asyncio.wait_for(
                _shutdown_event.wait(),
                timeout=poll_interval,
            )
            # Jika wait selesai tanpa timeout, berarti shutdown diminta
            break
        except asyncio.TimeoutError:
            # Timeout normal — lanjutkan polling
            pass

    # Cleanup browser saat shutdown
    if browser_open:
        await _close_browser_session()

    logger.info("Komiku Asia worker dihentikan.")


async def start_worker() -> None:
    """Mulai background worker jika diaktifkan di konfigurasi."""
    global _worker_task, _shutdown_event

    if not settings.KOMIKU_ASIA_WORKER_ENABLED:
        logger.info(
            "Komiku Asia worker dinonaktifkan (KOMIKU_ASIA_WORKER_ENABLED=false)."
        )
        return

    _shutdown_event = asyncio.Event()
    _worker_task = asyncio.create_task(
        _worker_loop(),
        name="komiku-asia-background-worker",
    )
    logger.info("Komiku Asia background worker task telah dijadwalkan.")


async def stop_worker() -> None:
    """Hentikan background worker secara graceful."""
    global _worker_task, _shutdown_event

    if _shutdown_event is not None:
        _shutdown_event.set()

    if _worker_task is not None:
        logger.info("Menunggu Komiku Asia worker selesai...")
        try:
            await asyncio.wait_for(_worker_task, timeout=30.0)
        except asyncio.TimeoutError:
            logger.warning("Worker tidak selesai dalam 30 detik, membatalkan task.")
            _worker_task.cancel()
            try:
                await _worker_task
            except asyncio.CancelledError:
                pass
        except asyncio.CancelledError:
            pass

    _worker_task = None
    _shutdown_event = None
    logger.info("Komiku Asia worker cleanup selesai.")
