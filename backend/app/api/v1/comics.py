"""
Tonztoon Komik — Comics API Routes

Endpoints:
    GET /api/v1/comics           — List komik (paginated)
    GET /api/v1/comics/latest    — Komik terbaru menurut canonical latest feed
    GET /api/v1/comics/popular   — Komik populer menurut canonical popular feed
    GET /api/v1/comics/{source_name}/{slug}          — Detail komik
    GET /api/v1/comics/{source_name}/{slug}/chapters — Daftar chapter
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import noload, selectinload

from app.database import get_db
from app.models import Comic, Chapter
from app.schemas.comic import ComicResponse, ComicListResponse, GenreResponse

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

# Fallback domain signal untuk komik lama yang belum sempat diberi marker
# posisi feed oleh cron terbaru. Ini tetap lebih tepat daripada `updated_at`
# karena merepresentasikan kapan chapter terakhir diketahui rilis.
_latest_chapter_release_subq = (
    select(func.max(Chapter.release_date))
    .where(Chapter.comic_id == Comic.id)
    .correlate(Comic)
    .scalar_subquery()
)


def _build_response(comic: Comic, total_chapters: int) -> ComicResponse:
    """Bangun ComicResponse dari ORM object + pre-computed chapter count."""
    return ComicResponse(
        **{
            c: getattr(comic, c)
            for c in ComicResponse.model_fields
            if c not in ("genres", "total_chapters")
        },
        genres=[GenreResponse(id=g.id, name=g.name, slug=g.slug) for g in comic.genres],
        total_chapters=total_chapters,
    )


@router.get("/latest", response_model=list[ComicResponse])
async def get_latest_comics(
    source: str | None = Query(None, description="Filter by source name (e.g. komiku)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil daftar komik terbaru berdasarkan sinyal feed latest dari cron.

    Endpoint ini sengaja TIDAK memakai `Comic.updated_at` sebagai urutan utama.
    `updated_at` adalah timestamp teknis kapan record komik disentuh sistem,
    sehingga bisa berubah saat seeding, full refresh, atau koreksi metadata
    tanpa ada chapter baru.

    Prioritas urutan:
    1. `latest_feed_*`: posisi comic saat terlihat di canonical latest feed.
    2. `MAX(chapters.release_date)`: fallback domain-level untuk data lama.
    3. `updated_at`: fallback teknis terakhir jika dua sinyal di atas kosong.

    Dengan begitu, `/latest` lebih merepresentasikan "komik dengan chapter
    terbaru menurut source" daripada "record komik yang terakhir diubah".
    """
    offset = (page - 1) * page_size
    stmt = (
        select(Comic, _chapter_count_subq.label("total_chapters"))
        .options(
            selectinload(Comic.genres),
            noload(Comic.chapters),  # cegah auto-load JSONB images via lazy="selectin"
        )
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

    if source:
        stmt = stmt.where(Comic.source_name == source.lower())

    result = await db.execute(stmt)
    rows = result.unique().all()

    return [_build_response(comic, count) for comic, count in rows]


@router.get("/popular", response_model=list[ComicResponse])
async def get_popular_comics(
    source: str | None = Query(None, description="Filter by source name (e.g. komiku)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    """
    Ambil daftar komik populer berdasarkan sinyal feed popular dari source.

    Endpoint ini sengaja TIDAK memakai `Comic.rating` sebagai urutan utama.
    `rating` di DB adalah metadata internal dan pada source Komiku bahkan
    tidak selalu tersedia, sehingga tidak bisa dianggap source of truth
    untuk ranking populer.

    Prioritas urutan:
    1. `popular_feed_*`: posisi comic saat terlihat di canonical popular feed.
    2. `rating`: fallback lemah untuk data lama yang belum punya marker popular.
    3. `updated_at`: fallback teknis terakhir.
    """
    offset = (page - 1) * page_size
    stmt = (
        select(Comic, _chapter_count_subq.label("total_chapters"))
        .options(
            selectinload(Comic.genres),
            noload(Comic.chapters),
        )
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

    if source:
        stmt = stmt.where(Comic.source_name == source.lower())

    result = await db.execute(stmt)
    rows = result.unique().all()

    return [_build_response(comic, count) for comic, count in rows]


@router.get("", response_model=ComicListResponse)
async def list_comics(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    type: str | None = Query(None, description="Filter by type: manga/manhwa/manhua"),
    status: str | None = Query(None, description="Filter by status: ongoing/completed/hiatus"),
    db: AsyncSession = Depends(get_db),
):
    """List semua komik dengan pagination dan filter opsional."""
    base_query = select(Comic)

    if type:
        base_query = base_query.where(Comic.type == type.lower())
    if status:
        base_query = base_query.where(Comic.status == status.lower())

    # Hitung total rows untuk metadata pagination
    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0

    offset = (page - 1) * page_size
    stmt = (
        base_query
        .add_columns(_chapter_count_subq.label("total_chapters"))
        .options(
            selectinload(Comic.genres),
            noload(Comic.chapters),
        )
        .order_by(Comic.updated_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(stmt)
    rows = result.unique().all()

    total_pages = (total + page_size - 1) // page_size

    return ComicListResponse(
        items=[_build_response(comic, count) for comic, count in rows],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/{source_name}/{slug}", response_model=ComicResponse)
async def get_comic_detail(
    source_name: str,
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Ambil detail komik berdasarkan sumber dan slug."""
    stmt = (
        select(Comic, _chapter_count_subq.label("total_chapters"))
        .options(
            selectinload(Comic.genres),
            noload(Comic.chapters),  # chapter list diambil lewat endpoint terpisah
        )
        .where(Comic.slug == slug, Comic.source_name == source_name)
    )
    result = await db.execute(stmt)
    row = result.unique().first()

    if not row:
        raise HTTPException(status_code=404, detail="Comic not found")

    comic, total_chapters = row
    return _build_response(comic, total_chapters)


@router.get("/{source_name}/{slug}/chapters")
async def get_comic_chapters(
    source_name: str,
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Ambil daftar chapter dari komik tertentu (tanpa images body)."""
    stmt = select(Comic.id).where(Comic.slug == slug, Comic.source_name == source_name)
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
