"""
Tonztoon Komik — Genres API Route

Endpoints:
    GET /api/v1/genres              — Daftar semua genre
    GET /api/v1/genres/{slug}/comics — Komik per genre
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models import Comic, Genre
from app.schemas.comic import GenreResponse, ComicResponse
from app.services.image_service import build_proxy_image_url

router = APIRouter()


@router.get("", response_model=list[GenreResponse])
async def list_genres(db: AsyncSession = Depends(get_db)):
    """Daftar semua genre yang tersedia."""
    stmt = select(Genre).order_by(Genre.name)
    result = await db.execute(stmt)
    genres = result.scalars().all()
    return genres


@router.get("/{slug}/comics", response_model=list[ComicResponse])
async def get_comics_by_genre(
    slug: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """Ambil daftar komik berdasarkan genre slug."""
    # Cek genre exists
    genre_stmt = select(Genre).where(Genre.slug == slug)
    genre_result = await db.execute(genre_stmt)
    genre = genre_result.scalars().first()

    if not genre:
        raise HTTPException(status_code=404, detail="Genre not found")

    offset = (page - 1) * page_size
    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres))
        .join(Comic.genres)
        .where(Genre.slug == slug)
        .order_by(Comic.updated_at.desc())
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
