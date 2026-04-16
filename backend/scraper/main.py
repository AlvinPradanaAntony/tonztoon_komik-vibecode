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
    4. Upsert comic ke PostgreSQL
    5. Simpan metadata SEMUA chapter (agar katalog selalu lengkap & update)
    6. Fetch images HANYA untuk MAX_CHAPTERS_PER_COMIC chapter terbaru
    7. Tutup koneksi dan exit

Strategi "Pre-warm Cache" (Hybrid):
    - Metadata (nomor, judul, url, tanggal) disimpan untuk SEMUA chapter
      sehingga daftar chapter di halaman detail komik selalu up-to-date.
    - Images hanya di-fetch untuk N chapter TERBARU per komik.
      Tujuannya agar chapter yang baru rilis sudah siap sebelum user datang
      (mencegah Thundering Herd), tanpa membebani server dengan ribuan request
      untuk chapter-chapter lama yang mungkin tidak pernah dibaca.
    - Chapter lama yang images-nya masih NULL akan ditangani oleh
      Lazy Loading di API saat ada user yang benar-benar membacanya.

Anti-Blocking:
    - Semua delay menggunakan random.uniform (bukan fixed) agar pola request
      tidak terdeteksi sebagai bot.
    - Delay SELALU dijalankan bahkan saat error, mencegah burst request
      yang terjadi ketika error berturut-turut (kemungkinan tanda rate limit).
    - Ada jeda sebelum fetch detail pertama dan antar-komik.
"""

import asyncio
import logging
import random
import sys
import time
from datetime import datetime, timezone, timedelta

TZ_WIB = timezone(timedelta(hours=7))

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Tambahkan parent directory ke path agar bisa import app.*
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))

from app.config import settings
from app.database import async_session, engine
from app.models import Comic, Chapter, Genre, comic_genre
from app.schemas import ComicCreate

from scraper.sources.komiku_scraper import KomikuScraper

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("scraper")

# ── Konfigurasi ───────────────────────────────────────────────────────────────

# Jumlah chapter terbaru per komik yang di-fetch images-nya oleh cron job.
# Chapter di luar batas ini dibiarkan images=NULL dan ditangani lazy load.
MAX_CHAPTERS_PER_COMIC = 3

# Delay antar-request (detik) — random untuk menghindari deteksi bot
DELAY_DETAIL_MIN  = 1.5   # jeda sebelum fetch halaman detail komik
DELAY_DETAIL_MAX  = 3.5
DELAY_CHAPTER_MIN = 2.0   # jeda antar-fetch images chapter
DELAY_CHAPTER_MAX = 4.0
DELAY_COMIC_MIN   = 3.0   # jeda antar-komik (setelah semua chapter selesai)
DELAY_COMIC_MAX   = 6.0


# ── Utility ───────────────────────────────────────────────────────────────────

async def random_delay(min_sec: float, max_sec: float, label: str = "") -> None:
    """Jeda acak antara min_sec dan max_sec detik."""
    delay = random.uniform(min_sec, max_sec)
    if label:
        logger.debug(f"  ⏳ {label}: {delay:.1f}s")
    await asyncio.sleep(delay)


# ── Database Helpers ──────────────────────────────────────────────────────────

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
        constraint="uq_source_slug",
        set_={
            "title": validated.title,
            "cover_image_url": validated.cover_image_url,
            "author": validated.author,
            "status": validated.status,
            "synopsis": validated.synopsis,
            "type": validated.type,
            "rating": validated.rating,
            "updated_at": datetime.now(TZ_WIB),
        },
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


async def upsert_chapter_metadata(session, comic_id: int, ch_data: dict) -> None:
    """Upsert metadata chapter ke database (tanpa images)."""
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
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


async def upsert_chapter_images(session, comic_id: int, ch_data: dict, images: list[dict]) -> None:
    """Update kolom images chapter yang sudah ada di database."""
    images_json = [{"page": img["page"], "url": img["url"]} for img in images]
    stmt = pg_insert(Chapter).values(
        comic_id=comic_id,
        chapter_number=ch_data["chapter_number"],
        title=ch_data.get("title"),
        source_url=ch_data["source_url"],
        release_date=ch_data.get("release_date"),
        images=images_json,
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_comic_chapter",
        set_={"images": images_json},
    )
    await session.execute(stmt)


# ── Main Pipeline ─────────────────────────────────────────────────────────────

async def run_scraper():
    """Main scraping pipeline."""
    start_time = time.time()
    logger.info("=" * 60)
    logger.info(f"Scraper started at {datetime.now(TZ_WIB).isoformat()}")
    logger.info("=" * 60)

    scrapers = [
        KomikuScraper(),
        # TODO: tambahkan scraper lain saat siap
    ]

    total_comics = 0
    total_chapters_meta = 0    # chapter yang metadata-nya disimpan/diperbarui
    total_chapters_images = 0  # chapter yang images-nya berhasil di-fetch

    async with async_session() as session:
        for scraper in scrapers:
            logger.info(f"Running scraper: {scraper.SOURCE_NAME} ({scraper.BASE_URL})")
            try:
                # Step 1: Ambil semua komik terbaru dari halaman listing
                comics_list = await scraper.get_latest_updates(page=1)
                logger.info(f"  Found {len(comics_list)} comics from listing page")

                for comic_basic in comics_list:
                    try:
                        detail_url = comic_basic.get("source_url", "")
                        if not detail_url:
                            continue

                        # Step 2: Jeda sebelum fetch detail (anti-blocking)
                        await random_delay(
                            DELAY_DETAIL_MIN, DELAY_DETAIL_MAX,
                            f"pre-detail {comic_basic['title']}"
                        )

                        # Step 3: Ambil detail lengkap dari halaman detail
                        logger.info(f"  Fetching detail: {comic_basic['title']}")
                        comic_detail = await scraper.get_comic_detail(detail_url)

                        if not comic_detail.get("title"):
                            logger.warning(f"  ✗ No title found for {detail_url}, skipping")
                            continue

                        # Step 4: Validasi data dengan Pydantic
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

                        # Step 5: Upsert comic ke database
                        comic_id = await upsert_comic(session, validated)
                        total_comics += 1

                        # Step 6: Upsert genres & link
                        for genre_name in validated.genres:
                            genre_id = await upsert_genre(session, genre_name)
                            genre_link = pg_insert(comic_genre).values(
                                comic_id=comic_id, genre_id=genre_id
                            )
                            genre_link = genre_link.on_conflict_do_nothing()
                            await session.execute(genre_link)

                        # Step 7: Proses semua chapter
                        # Diurutkan terbaru → terlama
                        chapters_data = comic_detail.get("chapters", [])
                        chapters_sorted = sorted(
                            chapters_data,
                            key=lambda c: c.get("chapter_number", 0),
                            reverse=True,
                        )

                        # Pisahkan chapter terbaru (akan di-fetch images)
                        # dari chapter lama (metadata saja, images tetap NULL)
                        chapters_to_warm = chapters_sorted[:MAX_CHAPTERS_PER_COMIC]
                        chapters_rest    = chapters_sorted[MAX_CHAPTERS_PER_COMIC:]

                        # 7a — Simpan metadata SEMUA chapter (tanpa images)
                        for ch_data in chapters_sorted:
                            if not ch_data.get("source_url"):
                                continue
                            await upsert_chapter_metadata(session, comic_id, ch_data)
                            total_chapters_meta += 1

                        await session.flush()

                        # 7b — Fetch images HANYA untuk chapter terbaru (Pre-warm)
                        ch_images_count = 0
                        logger.info(
                            f"  Pre-warming {len(chapters_to_warm)} chapter terbaru "
                            f"(dari total {len(chapters_sorted)}) "
                            f"untuk {validated.title}..."
                        )

                        for ch_data in chapters_to_warm:
                            ch_url = ch_data.get("source_url", "")
                            if not ch_url:
                                continue

                            # Skip jika images sudah ada di DB
                            existing = await session.execute(
                                select(Chapter.id, Chapter.images).where(
                                    Chapter.comic_id == comic_id,
                                    Chapter.chapter_number == ch_data["chapter_number"],
                                )
                            )
                            row = existing.first()
                            if row and row.images:
                                logger.info(
                                    f"    → Ch {ch_data['chapter_number']} "
                                    f"sudah punya images, skip."
                                )
                                continue

                            # Fetch dan simpan images
                            # Delay SELALU dijalankan — bahkan saat error,
                            # agar tidak terjadi burst request ke sumber.
                            try:
                                images = await scraper.get_chapter_images(ch_url)

                                if images:
                                    await upsert_chapter_images(
                                        session, comic_id, ch_data, images
                                    )
                                    ch_images_count += 1
                                    total_chapters_images += 1
                                    logger.info(
                                        f"    ✓ Ch {ch_data['chapter_number']}: "
                                        f"{len(images)} images"
                                    )
                                else:
                                    logger.warning(
                                        f"    ✗ Ch {ch_data['chapter_number']}: "
                                        f"tidak ada images ditemukan"
                                    )

                            except Exception as e:
                                logger.error(
                                    f"    ✗ Gagal fetch images "
                                    f"Ch {ch_data.get('chapter_number')}: {e}"
                                )

                            finally:
                                # Delay antar-chapter SELALU jalan (sukses maupun error)
                                await random_delay(
                                    DELAY_CHAPTER_MIN, DELAY_CHAPTER_MAX,
                                    f"post-chapter {ch_data.get('chapter_number')}"
                                )

                        logger.info(
                            f"  ✓ Done: {validated.title} — "
                            f"{len(chapters_sorted)} chapters metadata, "
                            f"{ch_images_count} images pre-warmed, "
                            f"{len(chapters_rest)} chapter lama → lazy load"
                        )

                        # Commit per komik agar tidak hilang jika crash di tengah
                        await session.commit()

                        # Delay antar-komik SELALU jalan (sukses maupun error)
                        await random_delay(
                            DELAY_COMIC_MIN, DELAY_COMIC_MAX, "antar-komik"
                        )

                    except Exception as e:
                        logger.error(f"  ✗ Error processing comic: {e}")
                        await session.rollback()
                        # Delay tetap jalan meskipun komik gagal total
                        await random_delay(
                            DELAY_COMIC_MIN, DELAY_COMIC_MAX, "antar-komik (after error)"
                        )
                        continue

                logger.info(
                    f"  Selesai scraper {scraper.SOURCE_NAME}: "
                    f"{total_comics} comics, "
                    f"{total_chapters_meta} chapter metadata, "
                    f"{total_chapters_images} chapter images pre-warmed"
                )

            except Exception as e:
                logger.error(f"  Scraper {scraper.SOURCE_NAME} failed: {e}")
                await session.rollback()
                continue

    elapsed = time.time() - start_time
    logger.info("=" * 60)
    logger.info(f"Scraper finished at {datetime.now(TZ_WIB).isoformat()}")
    logger.info(f"Total comics         : {total_comics}")
    logger.info(f"Total chapter meta   : {total_chapters_meta}")
    logger.info(f"Total pre-warmed     : {total_chapters_images} chapter images")
    logger.info(f"Elapsed              : {elapsed:.1f}s")
    logger.info("=" * 60)


def main():
    """Entry point synchronous wrapper."""
    asyncio.run(run_scraper())


if __name__ == "__main__":
    main()
