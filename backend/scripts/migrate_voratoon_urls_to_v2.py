"""
Tonztoon Komik — Batch Migration: Update Voratoon URLs to v2 (Canonical)

Mengubah seluruh source_url legacy (v1.voratoon.com / voratoon.com) pada tabel
comics dan chapters ke domain canonical https://v2.voratoon.com secara bertahap (chunked)
agar tidak membebani database ataupun mengunci tabel.

Penggunaan:
    # Cek jumlah baris yang terdampak (Dry Run):
    python -m scripts.migrate_voratoon_urls_to_v2

    # Jalankan migrasi:
    python -m scripts.migrate_voratoon_urls_to_v2 --apply --batch-size 5000
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import time

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session
from app.models import Chapter, Comic

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("scripts.migrate_voratoon_urls")


async def count_legacy_urls(session: AsyncSession) -> tuple[int, int]:
    """Hitung total komik dan chapter Voratoon yang masih memakai URL v1."""
    comic_count_res = await session.execute(
        select(func.count(Comic.id)).where(
            Comic.source_name == "voratoon",
            Comic.source_url.like("%v1.voratoon.com%"),
        )
    )
    comic_count = comic_count_res.scalar() or 0

    chapter_count_res = await session.execute(
        select(func.count(Chapter.id)).where(
            Chapter.source_url.like("%v1.voratoon.com%"),
        )
    )
    chapter_count = chapter_count_res.scalar() or 0

    return comic_count, chapter_count


async def migrate_comics(session: AsyncSession, *, apply: bool) -> int:
    """Update source_url komik Voratoon."""
    if not apply:
        stmt = select(func.count(Comic.id)).where(
            Comic.source_name == "voratoon",
            Comic.source_url.like("%v1.voratoon.com%"),
        )
        return (await session.execute(stmt)).scalar() or 0

    stmt = text(
        "UPDATE comics "
        "SET source_url = REPLACE(source_url, 'https://v1.voratoon.com', 'https://v2.voratoon.com') "
        "WHERE source_name = 'voratoon' AND source_url LIKE '%v1.voratoon.com%';"
    )
    res = await session.execute(stmt)
    await session.commit()
    return res.rowcount or 0


async def migrate_chapters(session: AsyncSession, *, batch_size: int, apply: bool) -> int:
    """Update source_url chapters Voratoon per batch berdasarkan ID."""
    total_updated = 0

    while True:
        # Ambil batch ID chapter yang perlu diupdate
        subq = (
            select(Chapter.id)
            .where(Chapter.source_url.like("%v1.voratoon.com%"))
            .limit(batch_size)
        )
        ids_res = await session.execute(subq)
        ids = ids_res.scalars().all()
        if not ids:
            break

        if not apply:
            total_updated += len(ids)
            break

        update_stmt = text(
            "UPDATE chapters "
            "SET source_url = REPLACE(source_url, 'https://v1.voratoon.com', 'https://v2.voratoon.com') "
            "WHERE id = ANY(:ids);"
        )
        res = await session.execute(update_stmt, {"ids": list(ids)})
        await session.commit()
        total_updated += res.rowcount or len(ids)
        logger.info(f"Progress chapters: {total_updated:,} baris terupdate...")

    return total_updated


async def main() -> None:
    parser = argparse.ArgumentParser(description="Migrate Voratoon URLs to v2 canonical.")
    parser.add_argument("--apply", action="store_true", help="Eksekusi perubahan ke database.")
    parser.add_argument("--batch-size", type=int, default=5000, help="Jumlah baris per batch (default: 5000).")
    args = parser.parse_args()

    async with async_session() as session:
        comics_pending, chapters_pending = await count_legacy_urls(session)
        logger.info(
            f"Ditemukan {comics_pending:,} komik dan {chapters_pending:,} chapter "
            f"dengan domain v1.voratoon.com."
        )

        if not args.apply:
            logger.info("Mode DRY-RUN: tidak ada perubahan disimpan ke database. Gunakan --apply untuk mengeksekusi.")
            return

        t0 = time.perf_counter()
        logger.info("Memulai migrasi comics...")
        c_count = await migrate_comics(session, apply=True)
        logger.info(f"✅ {c_count:,} comics berhasil diperbarui.")

        logger.info(f"Memulai migrasi chapters (batch size={args.batch_size:,})...")
        ch_count = await migrate_chapters(session, batch_size=args.batch_size, apply=True)
        t_elapsed = time.perf_counter() - t0
        logger.info(
            f"✅ Selesai: {c_count:,} comics dan {ch_count:,} chapters "
            f"berhasil dimigrasikan ke v2.voratoon.com dalam {t_elapsed:.2f}s."
        )


if __name__ == "__main__":
    asyncio.run(main())
