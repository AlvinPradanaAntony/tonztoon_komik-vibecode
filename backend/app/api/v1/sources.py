"""
Tonztoon Komik — Source-Scoped API Routes

Endpoint publik utama untuk navigasi katalog per source:
    GET /api/v1/sources
    GET /api/v1/sources/{source_name}/comics
    GET /api/v1/sources/{source_name}/comics/latest
    GET /api/v1/sources/{source_name}/comics/popular
    GET /api/v1/sources/{source_name}/comics/{slug}
    GET /api/v1/sources/{source_name}/comics/{slug}/chapters
    GET /api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number}
    GET /api/v1/sources/{source_name}/search?q=...
"""

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Path, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload, selectinload

from app.database import get_db
from app.models import Chapter, Comic
from app.schemas import (
    ComicResponse,
    GenreResponse,
    SourceComicListItem,
    SourceComicListResponse,
    SourceChapterListItem,
    SourceChapterResponse,
    SourceInfoResponse,
)
from app.services.chapter_service import (
    ImageFetchError,
    get_chapter_with_images_by_identity,
    get_comic_by_source_and_slug,
    prefetch_nearby_chapters,
)
from app.services.image_service import build_proxy_image_url, wrap_chapter_image_urls
from app.services.source_service import get_source_stats_map
from scraper.sources.registry import get_all_source_metadata, get_source_metadata

router = APIRouter()

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


def _build_comic_response(comic: Comic, total_chapters: int) -> ComicResponse:
    """Bangun response komik tanpa memuat body chapter images."""
    return ComicResponse(
        **{
            field_name: (
                build_proxy_image_url(getattr(comic, field_name))
                if field_name == "cover_image_url"
                else getattr(comic, field_name)
            )
            for field_name in ComicResponse.model_fields
            if field_name not in ("genres", "total_chapters")
        },
        genres=[GenreResponse(id=genre.id, name=genre.name, slug=genre.slug) for genre in comic.genres],
        total_chapters=total_chapters,
    )


def _build_source_chapter_response(source_name: str, chapter: Chapter) -> SourceChapterResponse:
    """Bangun payload chapter reader dengan URL gambar yang sudah diproxy."""
    images = wrap_chapter_image_urls(chapter.images)
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
    return f"{str(request.base_url).rstrip('/')}{path}"


def _build_source_comic_list_item(
    request: Request,
    source_name: str,
    comic: Comic,
    latest_chapter_number: float | None,
) -> SourceComicListItem:
    """Bangun item response katalog komik source-scoped."""
    return SourceComicListItem(
        title=comic.title,
        slug=comic.slug,
        source_name=source_name,
        cover_image_url=build_proxy_image_url(comic.cover_image_url),
        status=comic.status,
        type=comic.type,
        rating=comic.rating,
        total_view=comic.total_view,
        latest_chapter_number=latest_chapter_number,
        detail_url=_build_absolute_url(
            request,
            _build_source_comic_detail_url(source_name, comic.slug),
        ),
    )


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
    db: AsyncSession = Depends(get_db),
):
    """List katalog komik untuk satu source."""
    source = _get_source_or_404(source_name)
    base_query = select(Comic).where(Comic.source_name == source["id"])

    if type:
        base_query = base_query.where(Comic.type == type.lower())
    if status:
        base_query = base_query.where(Comic.status == status.lower())

    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0

    offset = (page - 1) * page_size
    stmt = (
        base_query
        .add_columns(_latest_chapter_number_subq.label("latest_chapter_number"))
        .options(noload(Comic.genres), noload(Comic.chapters))
        .order_by(Comic.title.asc())
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
    db: AsyncSession = Depends(get_db),
):
    """Feed komik terbaru dari satu source."""
    source = _get_source_or_404(source_name)
    offset = (page - 1) * page_size
    stmt = (
        select(Comic, _latest_chapter_number_subq.label("latest_chapter_number"))
        .options(noload(Comic.genres), noload(Comic.chapters))
        .where(Comic.source_name == source["id"])
        .order_by(
            Comic.latest_feed_batch_at.desc().nullslast(),
            Comic.latest_feed_page.asc().nullslast(),
            Comic.latest_feed_position.asc().nullslast(),
            _latest_chapter_release_subq.desc().nullslast(),
            Comic.updated_at.desc(),
        )
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(request, source["id"], comic, latest_chapter_number)
        for comic, latest_chapter_number in rows
    ]


@router.get("/{source_name}/comics/popular", response_model=list[SourceComicListItem])
async def get_source_popular_comics(
    request: Request,
    source_name: str = Path(..., description="Filter by source name (e.g. komiku, shinigami, komicast, komiku_asia)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    """Feed komik populer dari satu source."""
    source = _get_source_or_404(source_name)
    offset = (page - 1) * page_size
    stmt = (
        select(Comic, _latest_chapter_number_subq.label("latest_chapter_number"))
        .options(noload(Comic.genres), noload(Comic.chapters))
        .where(Comic.source_name == source["id"])
        .order_by(
            Comic.popular_feed_batch_at.desc().nullslast(),
            Comic.popular_feed_page.asc().nullslast(),
            Comic.popular_feed_position.asc().nullslast(),
            Comic.rating.desc().nullslast(),
            Comic.updated_at.desc(),
        )
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(request, source["id"], comic, latest_chapter_number)
        for comic, latest_chapter_number in rows
    ]


@router.get("/{source_name}/search", response_model=list[SourceComicListItem])
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
    search_pattern = f"%{q}%"
    offset = (page - 1) * page_size

    stmt = (
        select(Comic, _latest_chapter_number_subq.label("latest_chapter_number"))
        .options(noload(Comic.genres), noload(Comic.chapters))
        .where(
            Comic.source_name == source["id"],
            or_(
                Comic.title.ilike(search_pattern),
                Comic.alternative_titles.ilike(search_pattern),
            ),
        )
        .order_by(Comic.title.asc())
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()
    return [
        _build_source_comic_list_item(request, source["id"], comic, latest_chapter_number)
        for comic, latest_chapter_number in rows
    ]


@router.get("/{source_name}/comics/{slug}", response_model=ComicResponse)
async def get_source_comic_detail(
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
    return _build_comic_response(comic, total_chapters)


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
        select(Chapter)
        .where(Chapter.comic_id == comic.id)
        .order_by(Chapter.chapter_number.desc())
    )
    chapters = result.scalars().all()
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
            total_images=len(chapter.images) if chapter.images else 0,
        )
        for chapter in chapters
    ]


@router.get(
    "/{source_name}/comics/{slug}/chapters/{chapter_number}",
    response_model=SourceChapterResponse,
)
async def get_source_chapter_detail(
    source_name: str,
    slug: str,
    chapter_number: float,
    background_tasks: BackgroundTasks,
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
    except ImageFetchError as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Sumber komik sedang tidak dapat diakses. {exc}",
        ) from exc

    background_tasks.add_task(
        prefetch_nearby_chapters,
        chapter_id=chapter.id,
        comic_id=chapter.comic_id,
        current_chapter_number=chapter.chapter_number,
    )
    return _build_source_chapter_response(source["id"], chapter)
