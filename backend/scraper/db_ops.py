"""
Tonztoon Komik — Scraper Database Operations

Lapisan database operations murni untuk proses scraping.
Fungsi-fungsi ini menangani upsert/update ke tabel Comic, Chapter,
dan Genre. Diekstrak dari main.py agar:

1. CLI scripts (main.py, sync_full_library.py) tidak saling import
2. Logika DB terpisah dari logika orkestrasi scraping
3. Mudah diuji secara independen
"""

from sqlalchemy import DateTime, Integer, case, column, delete, or_, select, update, values
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Chapter, Comic, Genre, comic_genre
from app.schemas import ComicCreate
from app.services.image_service import enrich_chapter_image_dimensions
from scraper.time_utils import now_wib


# ═══════════════════════════════════════════════════════════════════
# GENRE OPS
# ═══════════════════════════════════════════════════════════════════


async def upsert_genre(session: AsyncSession, genre_name: str) -> int:
    """Insert genre jika belum ada, return genre id."""
    genre_ids = await upsert_genres(session, [genre_name])
    return genre_ids[genre_name.lower().replace(" ", "-")]


async def upsert_genres(
    session: AsyncSession,
    genre_names: list[str],
) -> dict[str, int]:
    """Bulk upsert genre dan return map slug -> id."""
    genres_by_slug = {
        genre_name.lower().replace(" ", "-"): genre_name
        for genre_name in genre_names
        if genre_name
    }
    if not genres_by_slug:
        return {}

    rows = [
        {"name": genre_name, "slug": slug}
        for slug, genre_name in genres_by_slug.items()
    ]
    stmt = pg_insert(Genre).values(rows)
    stmt = stmt.on_conflict_do_update(
        index_elements=["slug"],
        set_={"name": stmt.excluded.name},
    ).returning(Genre.slug, Genre.id)
    result = await session.execute(stmt)
    return {
        row.slug: row.id
        for row in result.all()
    }


async def sync_comic_genre_ids(
    session: AsyncSession,
    comic_id: int,
    target_genre_ids: list[int],
) -> None:
    """Sinkronkan association comic_genre dari daftar genre id final."""
    target_genre_ids_set = set(target_genre_ids)
    current_ids_result = await session.execute(
        select(comic_genre.c.genre_id).where(comic_genre.c.comic_id == comic_id)
    )
    current_genre_ids = set(current_ids_result.scalars().all())

    stale_genre_ids = current_genre_ids - target_genre_ids_set
    if stale_genre_ids:
        await session.execute(
            delete(comic_genre).where(
                comic_genre.c.comic_id == comic_id,
                comic_genre.c.genre_id.in_(stale_genre_ids),
            )
        )

    missing_genre_ids = target_genre_ids_set - current_genre_ids
    if missing_genre_ids:
        genre_link = pg_insert(comic_genre).values(
            [
                {
                    "comic_id": comic_id,
                    "genre_id": genre_id,
                }
                for genre_id in missing_genre_ids
            ]
        )
        await session.execute(genre_link.on_conflict_do_nothing())


async def sync_comic_genres(
    session: AsyncSession,
    comic_id: int,
    genre_names: list[str],
) -> None:
    """
    Sinkronkan relasi genre komik secara penuh.

    - Tambahkan genre baru yang belum terhubung.
    - Hapus relasi genre lama yang sudah tidak ada di source detail.
    """
    genre_ids_by_slug = await upsert_genres(session, genre_names)
    target_genre_ids = list(dict.fromkeys(genre_ids_by_slug.values()))
    await sync_comic_genre_ids(session, comic_id, target_genre_ids)


# ═══════════════════════════════════════════════════════════════════
# COMIC OPS
# ═══════════════════════════════════════════════════════════════════


def _public_storage_prefix() -> str | None:
    if not settings.SUPABASE_URL:
        return None
    return f"{settings.SUPABASE_URL.rstrip('/')}/storage/v1/object/public/"


def _storage_cover_preserve_condition():
    """
    Kenali cover yang sudah berada di public object storage.

    Jika SUPABASE_URL tersedia, prefix project tetap dicek secara spesifik.
    Jika tidak tersedia (misalnya GitHub Actions hanya punya DATABASE_URL),
    pola public storage generik tetap cukup untuk mencegah URL source scraper
    menimpa cover yang sudah dimigrasi.
    """
    conditions = [Comic.cover_image_url.like("%/storage/v1/object/public/%")]
    storage_prefix = _public_storage_prefix()
    if storage_prefix:
        conditions.insert(0, Comic.cover_image_url.like(f"{storage_prefix}%"))
    return or_(*conditions)


def _preserve_storage_cover_value(scraped_cover_url: str | None):
    """
    Jangan timpa cover yang sudah dimigrasi ke Supabase Storage.

    Scraper tetap menyimpan cover source untuk komik baru. Untuk comic existing
    yang sudah punya URL storage, metadata sync berikutnya tidak boleh
    mengembalikannya ke URL source/canonical.
    """
    return case(
        (
            _storage_cover_preserve_condition(),
            Comic.cover_image_url,
        ),
        else_=scraped_cover_url,
    )


async def upsert_comic(session: AsyncSession, validated: ComicCreate) -> int:
    """
    Upsert comic ke database tanpa mengubah marker urutan feed apa pun.

    Helper ini dipakai oleh alur lain yang hanya ingin menyimpan metadata
    comic. Untuk cron feed-based (`/latest` dan `/popular`), gunakan
    `upsert_comic_with_feed_markers` agar urutan endpoint ikut diperbarui.
    """
    return await upsert_comic_with_feed_markers(
        session,
        validated,
        latest_feed_batch_at=None,
        latest_feed_page=None,
        latest_feed_position=None,
        popular_feed_batch_at=None,
        popular_feed_page=None,
        popular_feed_position=None,
    )


async def upsert_comic_with_feed_markers(
    session: AsyncSession,
    validated: ComicCreate,
    *,
    latest_feed_batch_at,
    latest_feed_page: int | None,
    latest_feed_position: int | None,
    popular_feed_batch_at,
    popular_feed_page: int | None,
    popular_feed_position: int | None,
) -> int:
    """
    Upsert comic ke database dengan metadata posisi canonical feed opsional.

    `updated_at` tetap di-update sebagai jejak teknis perubahan row, tetapi
    urutan business-level untuk endpoint `/latest` dan `/popular` disimpan
    terpisah di marker `latest_feed_*` dan `popular_feed_*`.
    """
    current_time = now_wib()
    stmt = pg_insert(Comic).values(
        title=validated.title,
        slug=validated.slug,
        alternative_titles=validated.alternative_titles,
        cover_image_url=validated.cover_image_url,
        author=validated.author,
        artist=validated.artist,
        status=validated.status,
        type=validated.type,
        synopsis=validated.synopsis,
        rating=validated.rating,
        total_view=validated.total_view,
        source_url=validated.source_url,
        source_name=validated.source_name,
        created_at=current_time,
        updated_at=current_time,
        latest_feed_batch_at=latest_feed_batch_at,
        latest_feed_page=latest_feed_page,
        latest_feed_position=latest_feed_position,
        popular_feed_batch_at=popular_feed_batch_at,
        popular_feed_page=popular_feed_page,
        popular_feed_position=popular_feed_position,
    )
    update_values = {
        "title": validated.title,
        "alternative_titles": validated.alternative_titles,
        "cover_image_url": _preserve_storage_cover_value(validated.cover_image_url),
        "author": validated.author,
        "artist": validated.artist,
        "status": validated.status,
        "synopsis": validated.synopsis,
        "type": validated.type,
        "rating": Comic.rating if validated.rating is None else validated.rating,
        "total_view": Comic.total_view if validated.total_view is None else validated.total_view,
        "source_url": validated.source_url,
        "updated_at": current_time,
    }
    if latest_feed_batch_at is not None:
        update_values["latest_feed_batch_at"] = latest_feed_batch_at
        update_values["latest_feed_page"] = latest_feed_page
        update_values["latest_feed_position"] = latest_feed_position
    if popular_feed_batch_at is not None:
        update_values["popular_feed_batch_at"] = popular_feed_batch_at
        update_values["popular_feed_page"] = popular_feed_page
        update_values["popular_feed_position"] = popular_feed_position

    stmt = stmt.on_conflict_do_update(
        constraint="uq_source_slug",
        set_=update_values,
    ).returning(Comic.id)
    result = await session.execute(stmt)
    return result.scalar_one()


def build_latest_feed_marker_update_statement(markers: list[dict]):
    marker_values = (
        values(
            column("comic_id", Integer),
            column("latest_feed_batch_at", DateTime(timezone=True)),
            column("latest_feed_page", Integer),
            column("latest_feed_position", Integer),
            name="latest_feed_markers",
        )
        .data(
            [
                (
                    marker["comic_id"],
                    marker["latest_feed_batch_at"],
                    marker["latest_feed_page"],
                    marker["latest_feed_position"],
                )
                for marker in markers
            ]
        )
        .alias("latest_feed_markers")
    )
    return (
        update(Comic)
        .where(Comic.id == marker_values.c.comic_id)
        .values(
            latest_feed_batch_at=marker_values.c.latest_feed_batch_at,
            latest_feed_page=marker_values.c.latest_feed_page,
            latest_feed_position=marker_values.c.latest_feed_position,
        )
    )


def build_popular_feed_marker_update_statement(markers: list[dict]):
    marker_values = (
        values(
            column("comic_id", Integer),
            column("popular_feed_batch_at", DateTime(timezone=True)),
            column("popular_feed_page", Integer),
            column("popular_feed_position", Integer),
            name="popular_feed_markers",
        )
        .data(
            [
                (
                    marker["comic_id"],
                    marker["popular_feed_batch_at"],
                    marker["popular_feed_page"],
                    marker["popular_feed_position"],
                )
                for marker in markers
            ]
        )
        .alias("popular_feed_markers")
    )
    return (
        update(Comic)
        .where(Comic.id == marker_values.c.comic_id)
        .values(
            popular_feed_batch_at=marker_values.c.popular_feed_batch_at,
            popular_feed_page=marker_values.c.popular_feed_page,
            popular_feed_position=marker_values.c.popular_feed_position,
        )
    )


async def mark_comics_seen_in_latest_feed(
    session: AsyncSession,
    markers: list[dict],
) -> None:
    """Bulk update marker latest feed untuk banyak comic dalam satu statement."""
    if markers:
        await session.execute(build_latest_feed_marker_update_statement(markers))


async def mark_comics_seen_in_popular_feed(
    session: AsyncSession,
    markers: list[dict],
) -> None:
    """Bulk update marker popular feed untuk banyak comic dalam satu statement."""
    if markers:
        await session.execute(build_popular_feed_marker_update_statement(markers))


async def mark_comic_seen_in_latest_feed(
    session: AsyncSession,
    *,
    comic_id: int,
    latest_feed_batch_at,
    latest_feed_page: int,
    latest_feed_position: int,
) -> None:
    """
    Simpan posisi comic saat terlihat di canonical latest feed.

    Fungsi ini dipakai juga untuk item yang dianggap `unchanged`, karena comic
    tersebut tetap muncul di feed terbaru meskipun kita tidak perlu fetch
    detail ulang. Dengan begitu urutan `/latest` tetap mengikuti source.
    """
    await mark_comics_seen_in_latest_feed(
        session,
        [
            {
                "comic_id": comic_id,
                "latest_feed_batch_at": latest_feed_batch_at,
                "latest_feed_page": latest_feed_page,
                "latest_feed_position": latest_feed_position,
            }
        ],
    )


async def mark_comic_seen_in_popular_feed(
    session: AsyncSession,
    *,
    comic_id: int,
    popular_feed_batch_at,
    popular_feed_page: int,
    popular_feed_position: int,
) -> None:
    """
    Simpan posisi comic saat terlihat di canonical popular feed.

    Bahkan jika comic tidak perlu di-fetch ulang, ranking canonical source
    tetap perlu disalin ke DB agar endpoint `/popular` mengikuti source of
    truth dan tidak fallback ke `rating`.
    """
    await mark_comics_seen_in_popular_feed(
        session,
        [
            {
                "comic_id": comic_id,
                "popular_feed_batch_at": popular_feed_batch_at,
                "popular_feed_page": popular_feed_page,
                "popular_feed_position": popular_feed_position,
            }
        ],
    )


# ═══════════════════════════════════════════════════════════════════
# CHAPTER OPS
# ═══════════════════════════════════════════════════════════════════


def _dedupe_chapter_metadata_rows(chapters_data: list[dict]) -> list[dict]:
    """Hilangkan duplikat key upsert agar bulk ON CONFLICT tetap valid."""
    chapters_by_number: dict[object, dict] = {}
    for ch_data in chapters_data:
        if not ch_data.get("source_url"):
            continue

        chapter_number = ch_data["chapter_number"]
        try:
            chapter_key = float(chapter_number)
        except (TypeError, ValueError):
            chapter_key = chapter_number

        chapters_by_number.setdefault(chapter_key, ch_data)

    return list(chapters_by_number.values())


async def upsert_chapter_metadata(
    session: AsyncSession,
    comic_id: int,
    ch_data: dict,
) -> None:
    """Upsert metadata chapter ke database (tanpa images)."""
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
        created_at=now_wib(),
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={
            "title": ch_data.get("title"),
            "source_url": ch_data["source_url"],
            "release_date": ch_data.get("release_date"),
        },
    )
    await session.execute(stmt)


def build_chapter_metadata_upsert_statement(
    comic_id: int,
    chapters_data: list[dict],
):
    """Bangun bulk upsert metadata chapter tanpa kolom images."""
    current_time = now_wib()
    rows = [
        {
            "comic_id": comic_id,
            "chapter_number": ch_data["chapter_number"],
            "title": ch_data.get("title"),
            "source_url": ch_data["source_url"],
            "release_date": ch_data.get("release_date"),
            "created_at": current_time,
        }
        for ch_data in _dedupe_chapter_metadata_rows(chapters_data)
    ]
    stmt = pg_insert(Chapter).values(rows)
    return stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={
            "title": stmt.excluded.title,
            "source_url": stmt.excluded.source_url,
            "release_date": stmt.excluded.release_date,
        },
    )


async def upsert_chapter_metadata_many(
    session: AsyncSession,
    comic_id: int,
    chapters_data: list[dict],
) -> int:
    """Bulk upsert metadata chapter, return jumlah row valid yang dikirim."""
    valid_chapters = _dedupe_chapter_metadata_rows(chapters_data)
    if not valid_chapters:
        return 0

    await session.execute(
        build_chapter_metadata_upsert_statement(comic_id, valid_chapters)
    )
    return len(valid_chapters)


async def upsert_chapter_images(
    session: AsyncSession,
    comic_id: int,
    ch_data: dict,
    images: list[dict],
) -> None:
    """Update kolom images chapter yang sudah ada di database."""
    images_json = await enrich_chapter_image_dimensions(images)
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
        images=images_json,
        created_at=now_wib(),
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={"images": images_json},
    )
    await session.execute(stmt)
