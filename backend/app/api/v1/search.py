"""
Tonztoon Komik — Search API Route

Endpoints:
    GET /api/v1/search?q={query} — Pencarian komik
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models import Comic
from app.schemas.comic import ComicResponse
from app.services.image_service import build_proxy_image_url

router = APIRouter()


@router.get("", response_model=list[ComicResponse])
async def search_comics(
    q: str = Query(..., min_length=1, max_length=200, description="Search query"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """
    Cari komik berdasarkan keyword.
    Mencari di kolom title dan alternative_titles.
    """
    search_pattern = f"%{q}%"
    offset = (page - 1) * page_size

    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres))
        .where(
            or_(
                Comic.title.ilike(search_pattern),
                Comic.alternative_titles.ilike(search_pattern),
            )
        )
        .order_by(Comic.title)
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    comics = result.scalars().unique().all()

    return [
        ComicResponse(
            **{
                c: (
                    build_proxy_image_url(getattr(comic, c))
                    if c == "cover_image_url"
                    else getattr(comic, c)
                )
                for c in ComicResponse.model_fields
                if c not in ("genres", "total_chapters")
            },
            genres=[{"id": g.id, "name": g.name, "slug": g.slug} for g in comic.genres],
            total_chapters=len(comic.chapters) if comic.chapters else 0,
        )
        for comic in comics
    ]
