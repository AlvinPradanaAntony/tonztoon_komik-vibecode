"""
Tonztoon Komik — Scraper Entry Point (One-off Script)

File ini adalah entry point utama yang dijalankan oleh:
1. GitHub Actions Cron Job (terjadwal)
2. GitHub Actions workflow_dispatch (manual sync via API)

Usage:
    python -m scraper.main

Flow:
    1. Inisialisasi koneksi database (async)
    2. Jalankan semua scraper yang aktif
    3. Validasi data via Pydantic schemas
    4. Upsert data ke PostgreSQL
    5. Tutup koneksi dan exit
"""

import asyncio
import logging
import sys
import time
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))

from app.config import settings
from app.database import async_session, engine
from app.models import Comic, Chapter, Genre, comic_genre
from app.schemas import ComicCreate, ChapterCreate, ChapterImageItem

from scraper.sources.komiku_scraper import KomikuScraper

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("scraper")

# Batasi jumlah komik per run agar tidak overload
MAX_COMICS_PER_RUN = 10
MAX_CHAPTERS_PER_COMIC = 3  # Hanya scrape N chapter terbaru per komik


async def upsert_genre(session, genre_name: str) -> int:
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


async def upsert_comic(session, validated: ComicCreate) -> int:
    """Upsert comic ke database, return comic id."""
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
        source_url=validated.source_url,
        source_name=validated.source_name,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=["slug"],
        set_={
            "title": validated.title,
            "cover_image_url": validated.cover_image_url,
            "author": validated.author,
            "status": validated.status,
            "synopsis": validated.synopsis,
            "type": validated.type,
            "rating": validated.rating,
            "updated_at": datetime.now(timezone.utc),
        },
    )
    await session.execute(stmt)
    await session.flush()

    # Get comic id
    result = await session.execute(
        select(Comic.id).where(Comic.slug == validated.slug)
    )
    return result.scalar_one()


async def upsert_chapter(session, comic_id: int, chapter_data: dict, images: list[dict]) -> None:
    """Upsert chapter dengan images JSONB."""
    # Build images JSONB array
    images_json = [{"page": img["page"], "url": img["url"]} for img in images]

    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=chapter_data["chapter_number"],
        title=chapter_data.get("title"),
        source_url=chapter_data["source_url"],
        release_date=chapter_data.get("release_date"),
        images=images_json,
    )
    # Unique constraint: comic_id + chapter_number
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={
            "title": chapter_data.get("title"),
            "images": images_json,
        },
    )
    await session.execute(stmt)


async def run_scraper():
    """Main scraping pipeline."""
    start_time = time.time()
    logger.info("=" * 60)
    logger.info(f"Scraper started at {datetime.now().isoformat()}")
    logger.info("=" * 60)

    # Daftar scraper aktif
    scrapers = [
        KomikuScraper(),
        # TODO: tambahkan scraper lain saat siap
    ]

    total_comics = 0
    total_chapters = 0

    async with async_session() as session:
        for scraper in scrapers:
            logger.info(f"Running scraper: {scraper.SOURCE_NAME} ({scraper.BASE_URL})")
            try:
                # Step 1: Ambil daftar komik terbaru (halaman listing)
                comics_list = await scraper.get_latest_updates(page=1)
                logger.info(f"  Found {len(comics_list)} comics from listing page")

                # Batasi jumlah
                comics_to_process = comics_list[:MAX_COMICS_PER_RUN]

                for comic_basic in comics_to_process:
                    try:
                        # Step 2: Ambil detail lengkap dari halaman detail
                        detail_url = comic_basic.get("source_url", "")
                        if not detail_url:
                            continue

                        logger.info(f"  Fetching detail: {comic_basic['title']}")
                        comic_detail = await scraper.get_comic_detail(detail_url)

                        if not comic_detail.get("title"):
                            logger.warning(f"  ✗ No title found for {detail_url}, skipping")
                            continue

                        # Step 3: Validasi data dengan Pydantic
                        validated = ComicCreate(
                            title=comic_detail["title"],
                            slug=comic_detail["slug"],
                            alternative_titles=comic_detail.get("alternative_titles"),
                            cover_image_url=comic_detail.get("cover_image_url"),
                            author=comic_detail.get("author"),
                            artist=comic_detail.get("artist"),
                            status=comic_detail.get("status"),
                            type=comic_detail.get("type"),
                            synopsis=comic_detail.get("synopsis"),
                            rating=comic_detail.get("rating"),
                            source_url=comic_detail["source_url"],
                            source_name=comic_detail["source_name"],
                            genres=comic_detail.get("genres", []),
                        )

                        # Step 4: Upsert comic ke database
                        comic_id = await upsert_comic(session, validated)
                        total_comics += 1

                        # Step 5: Upsert genres & link
                        for genre_name in validated.genres:
                            genre_id = await upsert_genre(session, genre_name)
                            genre_link = pg_insert(comic_genre).values(
                                comic_id=comic_id, genre_id=genre_id
                            )
                            genre_link = genre_link.on_conflict_do_nothing()
                            await session.execute(genre_link)

                        # Step 6: Scrape chapters (hanya N terbaru)
                        chapters_data = comic_detail.get("chapters", [])
                        chapters_to_scrape = chapters_data[:MAX_CHAPTERS_PER_COMIC]

                        for ch_data in chapters_to_scrape:
                            try:
                                # Check apakah chapter sudah ada dengan images
                                existing = await session.execute(
                                    select(Chapter.id, Chapter.images).where(
                                        Chapter.comic_id == comic_id,
                                        Chapter.chapter_number == ch_data["chapter_number"],
                                    )
                                )
                                row = existing.first()
                                if row and row.images:
                                    logger.info(f"    → Chapter {ch_data['chapter_number']} already has images, skipping")
                                    continue

                                # Scrape chapter images
                                logger.info(f"    Scraping images for Chapter {ch_data['chapter_number']}")
                                images = await scraper.get_chapter_images(ch_data["source_url"])

                                if images:
                                    await upsert_chapter(session, comic_id, ch_data, images)
                                    total_chapters += 1
                                    logger.info(f"    ✓ Chapter {ch_data['chapter_number']}: {len(images)} images")
                                else:
                                    logger.warning(f"    ✗ No images found for Chapter {ch_data['chapter_number']}")

                                # Delay antara chapter requests
                                await asyncio.sleep(1)

                            except Exception as e:
                                logger.error(f"    ✗ Error on chapter {ch_data.get('chapter_number')}: {e}")
                                continue

                        logger.info(f"  ✓ Upserted comic: {validated.title} ({len(validated.genres)} genres)")

                        # Delay antara comic requests
                        await asyncio.sleep(2)

                    except Exception as e:
                        logger.error(f"  ✗ Error processing comic: {e}")
                        continue

                await session.commit()
                logger.info(f"  Committed {total_comics} comics, {total_chapters} chapters for {scraper.SOURCE_NAME}")

            except Exception as e:
                logger.error(f"  Scraper {scraper.SOURCE_NAME} failed: {e}")
                await session.rollback()
                continue

    elapsed = time.time() - start_time
    logger.info("=" * 60)
    logger.info(f"Scraper finished at {datetime.now().isoformat()}")
    logger.info(f"Total: {total_comics} comics, {total_chapters} chapters in {elapsed:.1f}s")
    logger.info("=" * 60)


def main():
    """Entry point synchronous wrapper."""
    asyncio.run(run_scraper())


if __name__ == "__main__":
    main()
