"""
Tonztoon Komik — Scraper Database Operations

Lapisan database operations murni untuk proses scraping.
Fungsi-fungsi ini menangani upsert/update ke tabel Comic, Chapter,
dan Genre. Diekstrak dari main.py agar:

1. CLI scripts (main.py, sync_full_library.py) tidak saling import
2. Logika DB terpisah dari logika orkestrasi scraping
3. Mudah diuji secara independen
"""

from sqlalchemy import delete, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Chapter, Comic, Genre, comic_genre
from app.schemas import ComicCreate
from scraper.time_utils import now_wib


# ═══════════════════════════════════════════════════════════════════
# GENRE OPS
# ═══════════════════════════════════════════════════════════════════


async def upsert_genre(session: AsyncSession, genre_name: str) -> int:
    """Insert genre jika belum ada, return genre id."""
    slug = genre_name.lower().replace(" ", "-")
    stmt = pg_insert(Genre).values(name=genre_name, slug=slug)
    stmt = stmt.on_conflict_do_nothing(index_elements=["slug"])
    await session.execute(stmt)
    await session.flush()

    result = await session.execute(
        select(Genre.id).where(Genre.slug == slug)
    )
    return result.scalar_one()


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
    target_genre_ids: list[int] = []
    seen_genre_ids: set[int] = set()

    for genre_name in genre_names:
        genre_id = await upsert_genre(session, genre_name)
        if genre_id in seen_genre_ids:
            continue
        seen_genre_ids.add(genre_id)
        target_genre_ids.append(genre_id)

    current_ids_result = await session.execute(
        select(comic_genre.c.genre_id).where(comic_genre.c.comic_id == comic_id)
    )
    current_genre_ids = set(current_ids_result.scalars().all())
    target_genre_ids_set = set(target_genre_ids)

    # Hapus genre yang sudah tidak relevan
    stale_genre_ids = current_genre_ids - target_genre_ids_set
    if stale_genre_ids:
        await session.execute(
            delete(comic_genre).where(
                comic_genre.c.comic_id == comic_id,
                comic_genre.c.genre_id.in_(stale_genre_ids),
            )
        )

    # Tambah genre baru
    missing_genre_ids = target_genre_ids_set - current_genre_ids
    for genre_id in missing_genre_ids:
        genre_link = pg_insert(comic_genre).values(
            comic_id=comic_id,
            genre_id=genre_id,
        )
        genre_link = genre_link.on_conflict_do_nothing()
        await session.execute(genre_link)


# ═══════════════════════════════════════════════════════════════════
# COMIC OPS
# ═══════════════════════════════════════════════════════════════════


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
        "cover_image_url": validated.cover_image_url,
        "author": validated.author,
        "artist": validated.artist,
        "status": validated.status,
        "synopsis": validated.synopsis,
        "type": validated.type,
        "rating": validated.rating,
        "total_view": validated.total_view,
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
    )
    await session.execute(stmt)
    await session.flush()

    result = await session.execute(
        select(Comic.id).where(
            Comic.slug == validated.slug,
            Comic.source_name == validated.source_name
        )
    )
    return result.scalar_one()


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
    await session.execute(
        update(Comic)
        .where(Comic.id == comic_id)
        .values(
            latest_feed_batch_at=latest_feed_batch_at,
            latest_feed_page=latest_feed_page,
            latest_feed_position=latest_feed_position,
        )
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
    await session.execute(
        update(Comic)
        .where(Comic.id == comic_id)
        .values(
            popular_feed_batch_at=popular_feed_batch_at,
            popular_feed_page=popular_feed_page,
            popular_feed_position=popular_feed_position,
        )
    )


# ═══════════════════════════════════════════════════════════════════
# CHAPTER OPS
# ═══════════════════════════════════════════════════════════════════


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


async def upsert_chapter_images(
    session: AsyncSession,
    comic_id: int,
    ch_data: dict,
    images: list[dict],
) -> None:
    """Update kolom images chapter yang sudah ada di database."""
    images_json = [{"page": img["page"], "url": img["url"]} for img in images]
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
