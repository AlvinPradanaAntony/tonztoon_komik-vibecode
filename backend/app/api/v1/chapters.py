"""
Tonztoon Komik — Chapters API Routes

Endpoints:
    GET /api/v1/chapters/{id}        — Detail chapter (lazy load images)
    GET /api/v1/chapters/{id}/images — Gambar-gambar dari chapter (lazy load)

Lazy Loading:
    Jika chapter belum memiliki images di database, API akan secara otomatis
    men-scrape images dari situs sumber (on-demand), menyimpan hasilnya ke
    database, lalu mengembalikan response ke user. Request berikutnya untuk
    chapter yang sama akan langsung mengambil dari database (cache hit).
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.chapter import ChapterResponse
from app.services.chapter_service import get_chapter_with_images, get_chapter_images_only

router = APIRouter()


@router.get("/{chapter_id}", response_model=ChapterResponse)
async def get_chapter(
    chapter_id: int,
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil detail chapter termasuk daftar gambar.

    Jika images belum tersedia di database, akan di-fetch secara otomatis
    dari situs sumber (lazy loading) dan disimpan untuk request berikutnya.
    """
    chapter = await get_chapter_with_images(db, chapter_id)

    if not chapter:
        raise HTTPException(status_code=404, detail="Chapter not found")

    return chapter


@router.get("/{chapter_id}/images")
async def get_chapter_images(
    chapter_id: int,
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil hanya daftar gambar dari chapter tertentu.

    Jika images belum tersedia di database, akan di-fetch secara otomatis
    dari situs sumber (lazy loading) dan disimpan untuk request berikutnya.
    """
    result = await get_chapter_images_only(db, chapter_id)

    if result is None:
        raise HTTPException(status_code=404, detail="Chapter not found")

    return result
