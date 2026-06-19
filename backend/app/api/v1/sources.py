"""
Tonztoon Komik — Source-Scoped API Routes

Endpoint publik utama untuk navigasi katalog per source:
    GET /api/v1/sources
    GET /api/v1/sources/{source_name}/comics
    GET /api/v1/sources/{source_name}/comics/latest
    GET /api/v1/sources/{source_name}/comics/popular
    GET /api/v1/sources/{source_name}/comics/recommendations
    GET /api/v1/sources/{source_name}/comics/top-ranking
    GET /api/v1/sources/{source_name}/comics/{slug}
    GET /api/v1/sources/{source_name}/comics/{slug}/chapters
    GET /api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number}
    GET /api/v1/sources/{source_name}/search?q=...
"""

import asyncio
import logging
import random
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Request
from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload, selectinload

from app.database import get_db
from app.models import Chapter, Comic, Genre
from app.schemas import (
    ComicResponse,
    GenreResponse,
    SourceComicListItem,
    SourceComicListResponse,
    SourceLatestComicStats,
    SourceChapterListItem,
    SourceChapterResponse,
    SourceInfoResponse,
)
from app.services.chapter_service import (
    ChapterImagesPendingError,
    ImageFetchError,
    get_chapter_with_images_by_identity,
    get_comic_by_source_and_slug,
    prefetch_nearby_chapters,
)
from app.services.image_service import build_proxy_image_url, wrap_chapter_image_urls
from app.services.source_service import get_source_stats_map
from app.services.chapter_image_job_service import RETRY_AFTER_SECONDS
from app.services.comic_search import comic_search_filter, comic_search_order
from scraper.sources.registry import get_all_source_metadata, get_source_metadata

router = APIRouter()
logger = logging.getLogger("api.sources")

# ---------------------------------------------------------------------------
# Helper: correlated subquery untuk menghitung jumlah chapter per komik.
# Jauh lebih efisien daripada memuat seluruh objek Chapter (termasuk kolom
# JSONB `images`) hanya untuk di-len().
# ---------------------------------------------------------------------------
_chapter_count_subq = (
    select(func.count(Chapter.id))
    .where(Chapter.comic_id == Comic.id)
    .correlate(Comic)
    .scalar_subquery()
)

_latest_chapter_number_subq = (
    select(func.max(Chapter.chapter_number))
    .where(Chapter.comic_id == Comic.id)
    .correlate(Comic)
    .scalar_subquery()
)

# Fallback domain signal untuk komik lama yang belum sempat diberi marker
# posisi feed oleh cron terbaru. Ini tetap lebih tepat daripada `updated_at`
# karena merepresentasikan kapan chapter terakhir diketahui rilis.
_latest_chapter_release_subq = (
    select(func.max(Chapter.release_date))
    .where(Chapter.comic_id == Comic.id)
    .correlate(Comic)
    .scalar_subquery()
)


def _get_request_base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


def _build_comic_response(
    request: Request,
    comic: Comic,
    total_chapters: int,
) -> ComicResponse:
    """Bangun response komik tanpa memuat body chapter images."""
    base_url = _get_request_base_url(request)
    return ComicResponse(
        **{
            field_name: (
                build_proxy_image_url(
                    getattr(comic, field_name),
                    base_url=base_url,
                )
                if field_name == "cover_image_url"
                else getattr(comic, field_name)
            )
            for field_name in ComicResponse.model_fields
            if field_name not in ("genres", "total_chapters")
        },
        genres=[GenreResponse(id=genre.id, name=genre.name, slug=genre.slug) for genre in comic.genres],
        total_chapters=total_chapters,
    )


def _build_source_chapter_response(
    request: Request,
    source_name: str,
    chapter: Chapter,
) -> SourceChapterResponse:
    """Bangun payload chapter reader dengan URL gambar yang sudah diproxy."""
    images = wrap_chapter_image_urls(
        chapter.images,
        base_url=_get_request_base_url(request),
    )
    return SourceChapterResponse(
        source_name=source_name,
        chapter_number=chapter.chapter_number,
        images=images,
        total=len(images),
    )


def _format_chapter_number_for_path(chapter_number: float) -> str:
    """Format chapter number agar angka bulat tidak ditulis dengan suffix `.0`."""
    return format(chapter_number, "g")


def _build_source_chapter_detail_url(source_name: str, slug: str, chapter_number: float) -> str:
    """Bangun URL API untuk detail chapter source-scoped."""
    chapter_number_path = _format_chapter_number_for_path(chapter_number)
    return f"/api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number_path}"


def _build_source_comic_detail_url(source_name: str, slug: str) -> str:
    """Bangun URL API untuk detail komik source-scoped."""
    return f"/api/v1/sources/{source_name}/comics/{slug}"


def _build_absolute_url(request: Request, path: str) -> str:
    """Gabungkan host aktif request dengan path API absolut."""
    return f"{_get_request_base_url(request)}{path}"


def _schedule_nearby_prefetch(
    *,
    chapter_id: int,
    comic_id: int,
    current_chapter_number: float,
) -> None:
    """Jalankan nearby prefetch sebagai task terlepas dan log error task."""
    task = asyncio.create_task(
        prefetch_nearby_chapters(
            chapter_id=chapter_id,
            comic_id=comic_id,
            current_chapter_number=current_chapter_number,
        ),
        name=f"nearby-prefetch-comic-{comic_id}-ch-{current_chapter_number:g}",
    )

    def _log_task_error(done_task: asyncio.Task) -> None:
        try:
            done_task.result()
        except Exception:
            logger.exception(
                "Nearby prefetch task failed "
                "(comic_id=%s, chapter_id=%s, chapter=%s)",
                comic_id,
                chapter_id,
                current_chapter_number,
            )

    task.add_done_callback(_log_task_error)


def _build_source_comic_list_item(
    request: Request,
    source_name: str,
    comic: Comic,
    latest_chapter_number: float | None,
    latest_chapter_release_date: datetime | None = None,
) -> SourceComicListItem:
    """Bangun item response katalog komik source-scoped."""
    base_url = _get_request_base_url(request)
    return SourceComicListItem(
        title=comic.title,
        slug=comic.slug,
        source_name=source_name,
        cover_image_url=build_proxy_image_url(
            comic.cover_image_url,
            base_url=base_url,
        ),
        status=comic.status,
        type=comic.type,
        rating=comic.rating,
        total_view=comic.total_view,
        genres=[
            GenreResponse(id=genre.id, name=genre.name, slug=genre.slug)
            for genre in comic.genres
        ],
        latest_chapter_number=latest_chapter_number,
        latest_chapter_release_date=latest_chapter_release_date,
        detail_url=_build_absolute_url(
            request,
            _build_source_comic_detail_url(source_name, comic.slug),
        ),
    )


def _normalize_query_value(value: str | None) -> str | None:
    normalized = (value or "").strip().lower()
    return normalized or None


def _slugify_query_value(value: str) -> str:
    return "-".join(value.replace("_", " ").split())


def _latest_feed_order():
    return (
        Comic.latest_feed_batch_at.desc().nullslast(),
        Comic.latest_feed_page.asc().nullslast(),
        Comic.latest_feed_position.asc().nullslast(),
        Comic.updated_at.desc(),
        Comic.id.asc(),
    )


def _popular_feed_order():
    return (
        Comic.popular_feed_batch_at.desc().nullslast(),
        Comic.popular_feed_page.asc().nullslast(),
        Comic.popular_feed_position.asc().nullslast(),
        Comic.rating.desc().nullslast(),
        Comic.total_view.desc().nullslast(),
        Comic.updated_at.desc(),
        Comic.id.asc(),
    )


def _top_ranking_order():
    return (
        Comic.total_view.desc().nullslast(),
        Comic.rating.desc().nullslast(),
        Comic.title.asc(),
        Comic.id.asc(),
    )


def _apply_source_comic_sort(base_query, sort: str | None):
    sort_value = _normalize_query_value(sort)
    if sort_value:
        sort_value = sort_value.replace("-", "_").replace(" ", "_")

    match sort_value:
        case "update_terbaru" | "update_newest" | "latest" | "newest":
            return base_query.order_by(
                *_latest_feed_order(),
                Comic.title.asc(),
            )
        case "popular" | "populer":
            return base_query.order_by(
                *_popular_feed_order(),
                Comic.title.asc(),
            )
        case (
            "total_view"
            | "total_view_high"
            | "total_view_tertinggi"
            | "view_high"
            | "views_high"
        ):
            return base_query.order_by(
                Comic.total_view.desc().nullslast(),
                Comic.rating.desc().nullslast(),
                Comic.title.asc(),
                Comic.id.asc(),
            )
        case "rating_high" | "rating_tinggi" | "rating":
            return base_query.order_by(
                Comic.rating.desc().nullslast(),
                Comic.total_view.desc().nullslast(),
                Comic.title.asc(),
            )
        case "az" | "a_z" | "title_asc":
            return base_query.order_by(Comic.title.asc())
        case "za" | "z_a" | "title_desc":
            return base_query.order_by(Comic.title.desc())
        case "relevance" | "relevansi" | None:
            return base_query
        case _:
            return base_query


def _apply_source_comic_filters(
    base_query,
    *,
    type: str | None = None,
    status: str | None = None,
    genre: str | None = None,
):
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
    return base_query


def _get_source_or_404(source_name: str) -> dict:
    """Validasi source publik dan ubah ke metadata aktif."""
    try:
        return get_source_metadata(source_name)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


async def _get_db_comic_counts_by_source(db: AsyncSession) -> dict[str, int]:
    """Ambil total komik di DB lokal, dikelompokkan per source."""
    result = await db.execute(
        select(Comic.source_name, func.count(Comic.id))
        .group_by(Comic.source_name)
    )
    return {
        source_name: total
        for source_name, total in result.all()
        if source_name
    }


@router.get("", response_model=list[SourceInfoResponse])
async def list_sources(db: AsyncSession = Depends(get_db)):
    """Daftar source aktif beserta ringkasan jumlah komik yang tersimpan."""
    source_metadata_list = get_all_source_metadata()
    source_names = [source_metadata["id"] for source_metadata in source_metadata_list]
    db_counts = await _get_db_comic_counts_by_source(db)
    source_stats_map = await get_source_stats_map(db, source_names)
    return [
        SourceInfoResponse(
            **source_metadata,
            source_comic_count=(
                source_stats_map[source_metadata["id"]].source_comic_count
                if source_metadata["id"] in source_stats_map
                else None
            ),
            source_comic_count_last_refreshed_at=(
                source_stats_map[source_metadata["id"]].last_refreshed_at
                if source_metadata["id"] in source_stats_map
                else None
            ),
            db_comic_count=db_counts.get(source_metadata["id"], 0),
        )
        for source_metadata in source_metadata_list
    ]


@router.get("/{source_name}/comics", response_model=SourceComicListResponse)
async def list_source_comics(
    request: Request,
    source_name: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    status: str | None = Query(None, description="Filter by status: ongoing/completed/hiatus"),
    genre: str | None = Query(None, description="Filter by genre name or slug"),
    sort: str | None = Query(
        None,
        description="Sort: latest/popular/total_view/rating_high/az/relevance",
    ),
    db: AsyncSession = Depends(get_db),
):
    """List katalog komik untuk satu source."""
    source = _get_source_or_404(source_name)
    base_query = select(Comic).where(Comic.source_name == source["id"])
    base_query = _apply_source_comic_filters(
        base_query,
        type=type,
        status=status,
        genre=genre,
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
            _build_source_comic_list_item(request, source["id"], comic, latest_chapter_number)
            for comic, latest_chapter_number in rows
        ],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/{source_name}/comics/latest", response_model=list[SourceComicListItem])
async def get_source_latest_comics(
    request: Request,
    source_name: str = Path(..., description="Filter by source name (e.g. komiku, shinigami, komicast, komiku_asia)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    genre: str | None = Query(None, description="Filter by genre name or slug"),
    sort: str | None = Query(
        None,
        description="Sort: popular/total_view/rating_high/az/za/relevance",
    ),
    db: AsyncSession = Depends(get_db),
):
    """Feed komik terbaru dari satu source."""
    source = _get_source_or_404(source_name)
    offset = (page - 1) * page_size
    base_query = select(
        Comic,
        _latest_chapter_number_subq.label("latest_chapter_number"),
        _latest_chapter_release_subq.label("latest_chapter_release_date"),
    ).where(Comic.source_name == source["id"])
    base_query = _apply_source_comic_filters(
        base_query,
        type=type,
        genre=genre,
    )
    stmt = (
        _apply_source_comic_sort(base_query, sort or "latest")
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(
            request,
            source["id"],
            comic,
            latest_chapter_number,
            latest_chapter_release_date,
        )
        for comic, latest_chapter_number, latest_chapter_release_date in rows
    ]


@router.get("/{source_name}/comics/latest/stats", response_model=SourceLatestComicStats)
async def get_source_latest_comic_stats(
    source_name: str = Path(..., description="Filter by source name"),
    period_days: int = Query(7, ge=1, le=30),
    db: AsyncSession = Depends(get_db),
):
    """Hitung komik yang memiliki rilis chapter dalam rentang waktu terbaru."""
    source = _get_source_or_404(source_name)
    cutoff = datetime.now(timezone.utc) - timedelta(days=period_days)
    stmt = select(func.count(Comic.id)).where(
        Comic.source_name == source["id"],
        _latest_chapter_release_subq >= cutoff,
    )
    updated_comic_count = (await db.execute(stmt)).scalar() or 0
    return SourceLatestComicStats(
        period_days=period_days,
        updated_comic_count=updated_comic_count,
    )


@router.get("/{source_name}/comics/popular", response_model=list[SourceComicListItem])
async def get_source_popular_comics(
    request: Request,
    source_name: str = Path(..., description="Filter by source name (e.g. komiku, shinigami, komicast, komiku_asia)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    status: str | None = Query(None, description="Filter by status: ongoing/completed/hiatus"),
    genre: str | None = Query(None, description="Filter by genre name or slug"),
    sort: str | None = Query(
        None,
        description="Sort: latest/total_view/rating_high/az/za/relevance",
    ),
    db: AsyncSession = Depends(get_db),
):
    """Feed komik populer dari satu source."""
    source = _get_source_or_404(source_name)
    offset = (page - 1) * page_size
    base_query = select(
        Comic,
        _latest_chapter_number_subq.label("latest_chapter_number"),
        _latest_chapter_release_subq.label("latest_chapter_release_date"),
    ).where(Comic.source_name == source["id"])
    base_query = _apply_source_comic_filters(
        base_query,
        type=type,
        status=status,
        genre=genre,
    )
    stmt = (
        _apply_source_comic_sort(base_query, sort or "popular")
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(
            request,
            source["id"],
            comic,
            latest_chapter_number,
            latest_chapter_release_date,
        )
        for comic, latest_chapter_number, latest_chapter_release_date in rows
    ]


@router.get(
    "/{source_name}/comics/recommendations",
    response_model=list[SourceComicListItem],
)
async def get_source_recommended_comics(
    request: Request,
    source_name: str = Path(
        ...,
        description=(
            "Filter by source name "
            "(e.g. komiku, shinigami, komicast, komiku_asia)"
        ),
    ),
    limit: int = Query(4, ge=1, le=12),
    pool_size: int = Query(24, ge=4, le=50),
    db: AsyncSession = Depends(get_db),
):
    """Rekomendasi komik dari kandidat populer dengan rating dan total view terbaik."""
    source = _get_source_or_404(source_name)
    effective_pool_size = max(pool_size, limit)
    base_stmt = (
        select(
            Comic,
            _latest_chapter_number_subq.label("latest_chapter_number"),
            _latest_chapter_release_subq.label("latest_chapter_release_date"),
        )
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .where(Comic.source_name == source["id"])
        .order_by(*_popular_feed_order())
        .limit(effective_pool_size)
    )

    strict_result = await db.execute(
        base_stmt.where(Comic.rating.is_not(None), Comic.total_view.is_not(None))
    )
    rows = strict_result.unique().all()
    if not rows:
        fallback_result = await db.execute(
            base_stmt.where(
                or_(Comic.rating.is_not(None), Comic.total_view.is_not(None))
            )
        )
        rows = fallback_result.unique().all()
    if not rows:
        fallback_result = await db.execute(base_stmt)
        rows = fallback_result.unique().all()

    today = datetime.now(timezone.utc).date()
    shuffled_rows = list(rows)
    random.Random(f"{source['id']}|{today.isoformat()}").shuffle(shuffled_rows)
    return [
        _build_source_comic_list_item(
            request,
            source["id"],
            comic,
            latest_chapter_number,
            latest_chapter_release_date,
        )
        for comic, latest_chapter_number, latest_chapter_release_date in shuffled_rows[
            :limit
        ]
    ]


@router.get(
    "/{source_name}/comics/top-ranking",
    response_model=list[SourceComicListItem],
)
async def get_source_top_ranking_comics(
    request: Request,
    source_name: str = Path(
        ...,
        description=(
            "Filter by source name "
            "(e.g. komiku, shinigami, komicast, komiku_asia)"
        ),
    ),
    limit: int = Query(10, ge=1, le=10),
    type: str | None = Query(
        None,
        description="Filter by type: manga/manhwa/manhua",
    ),
    db: AsyncSession = Depends(get_db),
):
    """Top ranking komik dari total view tertinggi pada satu source."""
    source = _get_source_or_404(source_name)
    type_value = _normalize_query_value(type)
    filters = [Comic.source_name == source["id"], Comic.total_view.is_not(None)]
    if type_value:
        filters.append(func.lower(Comic.type) == type_value)

    stmt = (
        select(
            Comic,
            _latest_chapter_number_subq.label("latest_chapter_number"),
            _latest_chapter_release_subq.label("latest_chapter_release_date"),
        )
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .where(*filters)
        .order_by(*_top_ranking_order())
        .limit(limit)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(
            request,
            source["id"],
            comic,
            latest_chapter_number,
            latest_chapter_release_date,
        )
        for comic, latest_chapter_number, latest_chapter_release_date in rows
    ]


@router.get("/{source_name}/search", response_model=SourceComicListResponse)
async def search_source_comics(
    request: Request,
    source_name: str,
    q: str = Query(..., min_length=1, max_length=200, description="Search query"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """Pencarian komik dalam satu source saja."""
    source = _get_source_or_404(source_name)
    base_query = select(Comic).where(
        Comic.source_name == source["id"],
        comic_search_filter(q),
    )
    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0
    offset = (page - 1) * page_size

    stmt = (
        base_query.add_columns(
            _latest_chapter_number_subq.label("latest_chapter_number")
        )
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .order_by(*comic_search_order(q))
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
                source["id"],
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


@router.get("/{source_name}/comics/{slug}", response_model=ComicResponse)
async def get_source_comic_detail(
    request: Request,
    source_name: str,
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Detail komik untuk satu source."""
    source = _get_source_or_404(source_name)
    stmt = (
        select(Comic, _chapter_count_subq.label("total_chapters"))
        .options(selectinload(Comic.genres), noload(Comic.chapters))
        .where(Comic.slug == slug, Comic.source_name == source["id"])
    )
    result = await db.execute(stmt)
    row = result.unique().first()
    if not row:
        raise HTTPException(status_code=404, detail="Comic not found")

    comic, total_chapters = row
    return _build_comic_response(request, comic, total_chapters)


@router.get(
    "/{source_name}/comics/{slug}/chapters",
    response_model=list[SourceChapterListItem],
)
async def get_source_comic_chapters(
    request: Request,
    source_name: str,
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Daftar chapter komik untuk satu source."""
    source = _get_source_or_404(source_name)
    comic = await get_comic_by_source_and_slug(db, source["id"], slug)
    if comic is None:
        raise HTTPException(status_code=404, detail="Comic not found")

    result = await db.execute(
        select(
            Chapter.chapter_number,
            Chapter.title,
            Chapter.release_date,
            Chapter.created_at,
            case(
                (
                    func.jsonb_typeof(Chapter.images) == "array",
                    func.jsonb_array_length(Chapter.images),
                ),
                else_=0,
            ).label("total_images"),
        )
        .where(Chapter.comic_id == comic.id)
        .order_by(Chapter.chapter_number.desc())
    )
    chapters = result.all()
    return [
        SourceChapterListItem(
            chapter_number=chapter.chapter_number,
            title=chapter.title,
            detail_url=_build_absolute_url(
                request,
                _build_source_chapter_detail_url(
                    source["id"],
                    slug,
                    chapter.chapter_number,
                ),
            ),
            release_date=chapter.release_date,
            created_at=chapter.created_at,
            total_images=chapter.total_images,
        )
        for chapter in chapters
    ]


@router.get(
    "/{source_name}/comics/{slug}/chapters/{chapter_number}",
    response_model=SourceChapterResponse,
)
async def get_source_chapter_detail(
    request: Request,
    source_name: str,
    slug: str,
    chapter_number: float,
    db: AsyncSession = Depends(get_db),
):
    """Payload chapter reader source-scoped dengan lazy image loading."""
    source = _get_source_or_404(source_name)
    try:
        chapter = await get_chapter_with_images_by_identity(
            db,
            source["id"],
            slug,
            chapter_number,
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Chapter tidak ditemukan")
    except ChapterImagesPendingError as exc:
        raise HTTPException(
            status_code=202,
            detail={
                "message": str(exc),
                "code": "chapter_images_preparing",
                "retry_after_seconds": RETRY_AFTER_SECONDS,
            },
            headers={"Retry-After": str(RETRY_AFTER_SECONDS)},
        ) from exc
    except ImageFetchError as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Sumber komik sedang tidak dapat diakses. {exc}",
        ) from exc

    _schedule_nearby_prefetch(
        chapter_id=chapter.id,
        comic_id=chapter.comic_id,
        current_chapter_number=chapter.chapter_number,
    )
    return _build_source_chapter_response(request, source["id"], chapter)
