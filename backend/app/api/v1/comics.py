"""
Tonztoon Komik - Global catalog API routes.

Endpoints:
    GET /api/v1/comics
"""

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload, selectinload

from app.api.v1.sources import (
    _apply_source_comic_sort,
    _build_source_comic_list_item,
    _latest_chapter_number_subq,
    _normalize_query_value,
    _slugify_query_value,
)
from app.database import get_db
from app.models import Comic, Genre
from app.schemas import SourceComicListResponse

router = APIRouter()


@router.get("", response_model=SourceComicListResponse)
async def list_comics(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    status: str | None = Query(None, description="Filter by status: ongoing/completed/hiatus"),
    genre: str | None = Query(None, description="Filter by genre name or slug"),
    sort: str | None = Query(
        None,
        description="Sort: latest/popular/total_view/rating_high/az/za/relevance",
    ),
    db: AsyncSession = Depends(get_db),
):
    """List katalog komik gabungan dari semua source."""
    base_query = select(Comic)

    type_value = _normalize_query_value(type)
    status_value = _normalize_query_value(status)
    genre_value = _normalize_query_value(genre)

    if type_value:
        base_query = base_query.where(func.lower(Comic.type) == type_value)
    if status_value:
        base_query = base_query.where(func.lower(Comic.status) == status_value)
    if genre_value:
        genre_slug = _slugify_query_value(genre_value)
        base_query = base_query.where(
            Comic.genres.any(
                or_(
                    func.lower(Genre.name) == genre_value,
                    func.lower(Genre.slug) == genre_slug,
                )
            )
        )

    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0

    offset = (page - 1) * page_size
    stmt = (
        _apply_source_comic_sort(base_query, sort)
        .add_columns(_latest_chapter_number_subq.label("latest_chapter_number"))
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()

    total_pages = (total + page_size - 1) // page_size
    return SourceComicListResponse(
        items=[
            _build_source_comic_list_item(
                request,
                comic.source_name,
                comic,
                latest_chapter_number,
            )
            for comic, latest_chapter_number in rows
        ],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )
