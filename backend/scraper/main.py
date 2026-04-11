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
from datetime import datetime

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


async def run_scraper():
    """Main scraping pipeline."""
    logger.info("=" * 60)
    logger.info(f"Scraper started at {datetime.now().isoformat()}")
    logger.info("=" * 60)

    # Daftar scraper aktif
    scrapers = [
        KomikuScraper(),
        # TODO: tambahkan scraper lain saat siap
        # KomikcastScraper(),
        # ShinigamiScraper(),
    ]

    async with async_session() as session:
        for scraper in scrapers:
            logger.info(f"Running scraper: {scraper.SOURCE_NAME} ({scraper.BASE_URL})")
            try:
                # Step 1: Ambil daftar komik terbaru
                comics_data = await scraper.get_latest_updates(page=1)
                logger.info(f"  Found {len(comics_data)} comics from latest updates")

                for comic_data in comics_data:
                    try:
                        # Step 2: Validasi data dengan Pydantic
                        validated = ComicCreate(**comic_data)

                        # Step 3: Upsert comic ke database
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
                                "status": validated.status,
                                "rating": validated.rating,
                                "updated_at": datetime.utcnow(),
                            },
                        )
                        result = await session.execute(stmt)
                        await session.flush()

                        # Get comic id
                        comic_id_result = await session.execute(
                            select(Comic.id).where(Comic.slug == validated.slug)
                        )
                        comic_id = comic_id_result.scalar_one()

                        # Step 4: Upsert genres
                        for genre_name in validated.genres:
                            genre_id = await upsert_genre(session, genre_name)
                            genre_link = pg_insert(comic_genre).values(
                                comic_id=comic_id, genre_id=genre_id
                            )
                            genre_link = genre_link.on_conflict_do_nothing()
                            await session.execute(genre_link)

                        logger.info(f"  ✓ Upserted: {validated.title}")

                    except Exception as e:
                        logger.error(f"  ✗ Error processing comic: {e}")
                        continue

                await session.commit()
                logger.info(f"  Committed {len(comics_data)} comics for {scraper.SOURCE_NAME}")

            except Exception as e:
                logger.error(f"  Scraper {scraper.SOURCE_NAME} failed: {e}")
                await session.rollback()
                continue

    logger.info("=" * 60)
    logger.info(f"Scraper finished at {datetime.now().isoformat()}")
    logger.info("=" * 60)


def main():
    """Entry point synchronous wrapper."""
    asyncio.run(run_scraper())


if __name__ == "__main__":
    main()
