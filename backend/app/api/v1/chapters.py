"""
Tonztoon Komik — Chapters API Routes

Endpoints:
    GET /api/v1/chapters/{id}        — Detail chapter (lazy load images)
    GET /api/v1/chapters/{id}/images — Gambar-gambar dari chapter (lazy load)

Error Responses:
    404 — Chapter tidak ditemukan di database
    503 — Sumber komik tidak dapat diakses saat ini (scraping gagal/timeout)
          → Aplikasi client (Flutter) harus menampilkan pesan "Coba lagi nanti"
            dan tombol Retry, bukan blank screen.

Flow setelah response dikirim:
    Background task prefetch images untuk chapter terdekat (±5 chapter)
    yang images-nya masih NULL, diam-diam tanpa mempengaruhi response time.
"""

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Chapter
from app.schemas.chapter import ChapterResponse
from app.services.chapter_service import (
    ImageFetchError,
    get_chapter_images_only,
    get_chapter_with_images,
    prefetch_nearby_chapters,
)

router = APIRouter()


@router.get("/{chapter_id}", response_model=ChapterResponse)
async def get_chapter(
    chapter_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil detail chapter termasuk daftar gambar.

    - Cache hit  : images langsung dari DB (milidetik)
    - Cache miss : on-demand scraping maks 10 detik, lalu disimpan ke DB
    - Gagal      : HTTP 503 dengan pesan yang jelas untuk ditampilkan ke user
    """
    try:
        chapter = await get_chapter_with_images(db, chapter_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="Chapter tidak ditemukan")
    except ImageFetchError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Sumber komik sedang tidak dapat diakses. {e}",
        )

    # Trigger background prefetch untuk chapter-chapter terdekat
    background_tasks.add_task(
        prefetch_nearby_chapters,
        chapter_id=chapter.id,
        comic_id=chapter.comic_id,
        current_chapter_number=chapter.chapter_number,
    )

    return chapter


@router.get("/{chapter_id}/images")
async def get_chapter_images(
    chapter_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil hanya daftar URL gambar dari chapter tertentu.

    - Cache hit  : images langsung dari DB (milidetik)
    - Cache miss : on-demand scraping maks 10 detik, lalu disimpan ke DB
    - Gagal      : HTTP 503 dengan pesan yang jelas untuk ditampilkan ke user
    """
    try:
        result = await get_chapter_images_only(db, chapter_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="Chapter tidak ditemukan")
    except ImageFetchError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Sumber komik sedang tidak dapat diakses. {e}",
        )

    # Ambil info chapter untuk trigger prefetch
    ch_result = await db.execute(
        select(Chapter.comic_id, Chapter.chapter_number)
        .where(Chapter.id == chapter_id)
    )
    row = ch_result.first()
    if row:
        background_tasks.add_task(
            prefetch_nearby_chapters,
            chapter_id=chapter_id,
            comic_id=row.comic_id,
            current_chapter_number=row.chapter_number,
        )

    return result
