"""
Tonztoon Komik — Chapters API Routes

Endpoints:
    GET /api/v1/chapters/{id}/images — Gambar-gambar dari chapter
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Chapter
from app.schemas.chapter import ChapterResponse

router = APIRouter()


@router.get("/{chapter_id}", response_model=ChapterResponse)
async def get_chapter(
    chapter_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Ambil detail chapter termasuk daftar gambar (JSONB images)."""
    stmt = select(Chapter).where(Chapter.id == chapter_id)
    result = await db.execute(stmt)
    chapter = result.scalars().first()

    if not chapter:
        raise HTTPException(status_code=404, detail="Chapter not found")

    return chapter


@router.get("/{chapter_id}/images")
async def get_chapter_images(
    chapter_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Ambil hanya daftar gambar dari chapter tertentu."""
    stmt = select(Chapter.images).where(Chapter.id == chapter_id)
    result = await db.execute(stmt)
    images = result.scalar()

    if images is None:
        raise HTTPException(status_code=404, detail="Chapter not found")

    return {"chapter_id": chapter_id, "images": images, "total": len(images)}
