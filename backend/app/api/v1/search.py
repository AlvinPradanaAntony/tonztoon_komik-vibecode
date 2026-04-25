"""
Tonztoon Komik — Search API Route

Endpoints:
    GET /api/v1/search?q={query} — Pencarian komik
"""

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload

from app.database import get_db
from app.models import Chapter, Comic
from app.schemas import SourceComicListItem
from app.services.image_service import build_proxy_image_url

router = APIRouter()

_latest_chapter_number_subq = (
    select(func.max(Chapter.chapter_number))
    .where(Chapter.comic_id == Comic.id)
    .correlate(Comic)
    .scalar_subquery()
)


def _build_absolute_url(request: Request, path: str) -> str:
    """Gabungkan host aktif request dengan path API absolut."""
    return f"{str(request.base_url).rstrip('/')}{path}"


def _build_source_comic_detail_url(source_name: str, slug: str) -> str:
    """Bangun URL API untuk detail komik source-scoped."""
    return f"/api/v1/sources/{source_name}/comics/{slug}"


@router.get("", response_model=list[SourceComicListItem])
async def search_comics(
    request: Request,
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
        select(Comic, _latest_chapter_number_subq.label("latest_chapter_number"))
        .options(noload(Comic.genres), noload(Comic.chapters))
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
    rows = result.unique().all()
    base_url = str(request.base_url).rstrip("/")

    return [
        SourceComicListItem(
            title=comic.title,
            slug=comic.slug,
            source_name=comic.source_name,
            cover_image_url=build_proxy_image_url(comic.cover_image_url, base_url=base_url),
            status=comic.status,
            type=comic.type,
            rating=comic.rating,
            total_view=comic.total_view,
            latest_chapter_number=latest_chapter_number,
            detail_url=_build_absolute_url(
                request,
                _build_source_comic_detail_url(comic.source_name, comic.slug),
            ),
        )
        for comic, latest_chapter_number in rows
    ]
