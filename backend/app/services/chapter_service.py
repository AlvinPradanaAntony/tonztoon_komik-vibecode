"""
Tonztoon Komik — Chapter Service (Lazy Loading)

Service layer yang menangani logika on-demand scraping untuk chapter images.
Saat user membuka/membaca sebuah chapter, images akan di-fetch dari sumber
hanya jika belum ada di database (lazy loading).

Flow:
    1. User request GET /api/v1/chapters/{id} atau /chapters/{id}/images
    2. Service cek DB: apakah chapter sudah punya images?
    3. Jika sudah → langsung return dari DB (cache hit)
    4. Jika belum → panggil scraper.get_chapter_images() → simpan ke DB → return

Keuntungan:
    - Tidak membebani situs sumber dengan ribuan request saat mass sync
    - Hanya chapter yang benar-benar dibaca user yang di-scrape
    - Pola request menyerupai trafik manusia normal
"""

import logging

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Chapter, Comic

logger = logging.getLogger("service.chapter")


def _get_scraper_for_source(source_name: str):
    """
    Factory: return scraper instance berdasarkan source_name.
    Scalable — tinggal tambahkan elif untuk sumber baru.
    """
    if source_name == "komiku":
        from scraper.sources.komiku_scraper import KomikuScraper
        return KomikuScraper()
    # elif source_name == "komikcast":
    #     from scraper.sources.komikcast_scraper import KomikcastScraper
    #     return KomikcastScraper()
    else:
        return None


async def get_chapter_with_images(
    db: AsyncSession,
    chapter_id: int,
) -> Chapter | None:
    """
    Ambil chapter dari DB. Jika images kosong/null, lakukan on-demand scraping
    dari situs sumber, simpan hasilnya ke DB, lalu return.

    Args:
        db: Database session
        chapter_id: ID chapter di database

    Returns:
        Chapter object dengan images terisi, atau None jika chapter tidak ada.
    """
    # 1. Ambil chapter beserta informasi comic (untuk source_name & source_url)
    stmt = (
        select(Chapter)
        .where(Chapter.id == chapter_id)
    )
    result = await db.execute(stmt)
    chapter = result.scalars().first()

    if not chapter:
        return None

    # 2. Jika sudah punya images → langsung return (cache hit)
    if chapter.images:
        logger.debug(f"Cache hit: Chapter {chapter_id} sudah punya {len(chapter.images)} images")
        return chapter

    # 3. Images kosong → perlu lazy fetch dari sumber
    logger.info(
        f"Lazy loading: Chapter {chapter_id} (Ch {chapter.chapter_number}) "
        f"belum punya images, memulai on-demand scraping..."
    )

    # Ambil info comic untuk mengetahui source_name
    comic_result = await db.execute(
        select(Comic.source_name).where(Comic.id == chapter.comic_id)
    )
    source_name = comic_result.scalar()

    if not source_name:
        logger.warning(f"Comic {chapter.comic_id} tidak ditemukan untuk chapter {chapter_id}")
        return chapter  # Return chapter tanpa images

    # 4. Inisialisasi scraper yang sesuai
    scraper = _get_scraper_for_source(source_name)
    if not scraper:
        logger.warning(f"Tidak ada scraper untuk source: {source_name}")
        return chapter

    # 5. Fetch images dari situs sumber
    try:
        images = await scraper.get_chapter_images(chapter.source_url)

        if not images:
            logger.warning(
                f"On-demand scraping Ch {chapter.chapter_number}: "
                f"tidak ada gambar ditemukan di {chapter.source_url}"
            )
            return chapter

        # 6. Simpan images ke database
        images_json = [{"page": img["page"], "url": img["url"]} for img in images]

        await db.execute(
            update(Chapter)
            .where(Chapter.id == chapter_id)
            .values(images=images_json)
        )
        await db.commit()

        # Refresh chapter object dengan data terbaru
        await db.refresh(chapter)

        logger.info(
            f"✅ Lazy loaded: Chapter {chapter_id} (Ch {chapter.chapter_number}) "
            f"→ {len(images_json)} gambar tersimpan ke DB"
        )

    except Exception as e:
        logger.error(
            f"✗ Gagal lazy load images untuk Chapter {chapter_id}: {e}"
        )
        await db.rollback()
        # Return chapter apa adanya (tanpa images) — tidak crash

    return chapter


async def get_chapter_images_only(
    db: AsyncSession,
    chapter_id: int,
) -> dict | None:
    """
    Ambil hanya images dari chapter (endpoint /chapters/{id}/images).
    Jika kosong, lakukan lazy loading terlebih dahulu.

    Returns:
        Dict {"chapter_id": int, "images": list, "total": int}
        atau None jika chapter tidak ditemukan.
    """
    chapter = await get_chapter_with_images(db, chapter_id)

    if not chapter:
        return None

    images = chapter.images or []

    return {
        "chapter_id": chapter_id,
        "images": images,
        "total": len(images),
    }
