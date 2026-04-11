"""
Tonztoon Komik — Comics API Routes

Endpoints:
    GET /api/v1/comics           — List komik (paginated)
    GET /api/v1/comics/latest    — Komik terbaru
    GET /api/v1/comics/popular   — Komik populer
    GET /api/v1/comics/{slug}    — Detail komik
    GET /api/v1/comics/{slug}/chapters — Daftar chapter
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models import Comic, Chapter
from app.schemas.comic import ComicResponse, ComicListResponse

router = APIRouter()


@router.get("/latest", response_model=list[ComicResponse])
async def get_latest_comics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """Ambil daftar komik yang terakhir di-update."""
    offset = (page - 1) * page_size
    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres))
        .order_by(Comic.updated_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    comics = result.scalars().unique().all()

    return [
        ComicResponse(
            **{c: getattr(comic, c) for c in ComicResponse.model_fields if c not in ("genres", "total_chapters")},
            genres=[{"id": g.id, "name": g.name, "slug": g.slug} for g in comic.genres],
            total_chapters=len(comic.chapters) if comic.chapters else 0,
        )
        for comic in comics
    ]


@router.get("/popular", response_model=list[ComicResponse])
async def get_popular_comics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """Ambil daftar komik populer (by rating)."""
    offset = (page - 1) * page_size
    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres))
        .order_by(Comic.rating.desc().nullslast())
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    comics = result.scalars().unique().all()

    return [
        ComicResponse(
            **{c: getattr(comic, c) for c in ComicResponse.model_fields if c not in ("genres", "total_chapters")},
            genres=[{"id": g.id, "name": g.name, "slug": g.slug} for g in comic.genres],
            total_chapters=len(comic.chapters) if comic.chapters else 0,
        )
        for comic in comics
    ]


@router.get("", response_model=ComicListResponse)
async def list_comics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    status: str | None = Query(None, description="Filter by status: ongoing/completed/hiatus"),
    db: AsyncSession = Depends(get_db),
):
    """List semua komik dengan pagination dan filter."""
    base_query = select(Comic)

    if type:
        base_query = base_query.where(Comic.type == type.lower())
    if status:
        base_query = base_query.where(Comic.status == status.lower())

    # Count total
    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0

    # Fetch page
    offset = (page - 1) * page_size
    stmt = (
        base_query
        .options(selectinload(Comic.genres))
        .order_by(Comic.updated_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    comics = result.scalars().unique().all()

    total_pages = (total + page_size - 1) // page_size

    items = [
        ComicResponse(
            **{c: getattr(comic, c) for c in ComicResponse.model_fields if c not in ("genres", "total_chapters")},
            genres=[{"id": g.id, "name": g.name, "slug": g.slug} for g in comic.genres],
            total_chapters=len(comic.chapters) if comic.chapters else 0,
        )
        for comic in comics
    ]

    return ComicListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/{slug}", response_model=ComicResponse)
async def get_comic_detail(
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Ambil detail komik berdasarkan slug."""
    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres), selectinload(Comic.chapters))
        .where(Comic.slug == slug)
    )
    result = await db.execute(stmt)
    comic = result.scalars().first()

    if not comic:
        raise HTTPException(status_code=404, detail="Comic not found")

    return ComicResponse(
        **{c: getattr(comic, c) for c in ComicResponse.model_fields if c not in ("genres", "total_chapters")},
        genres=[{"id": g.id, "name": g.name, "slug": g.slug} for g in comic.genres],
        total_chapters=len(comic.chapters) if comic.chapters else 0,
    )


@router.get("/{slug}/chapters")
async def get_comic_chapters(
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Ambil daftar chapter dari komik tertentu (tanpa images body)."""
    stmt = select(Comic.id).where(Comic.slug == slug)
    result = await db.execute(stmt)
    comic_id = result.scalar()

    if comic_id is None:
        raise HTTPException(status_code=404, detail="Comic not found")

    chapters_stmt = (
        select(Chapter)
        .where(Chapter.comic_id == comic_id)
        .order_by(Chapter.chapter_number.desc())
    )
    result = await db.execute(chapters_stmt)
    chapters = result.scalars().all()

    return [
        {
            "id": ch.id,
            "chapter_number": ch.chapter_number,
            "title": ch.title,
            "release_date": ch.release_date,
            "created_at": ch.created_at,
            "total_images": len(ch.images) if ch.images else 0,
        }
        for ch in chapters
    ]
