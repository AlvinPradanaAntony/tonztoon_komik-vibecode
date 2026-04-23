"""
Clear database for re-testing.

PERHATIAN: Script ini menghapus SEMUA data dari tabel utama.
Gunakan hanya di environment development/testing.
Connection string dibaca dari .env via app.config.

Usage (dari folder backend/):
    python -m scripts.clear_db
"""

import asyncio
import sys
from pathlib import Path

# Pastikan backend/ ada di sys.path agar bisa import app.*
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import settings


async def clear():
    engine = create_async_engine(settings.DATABASE_URL)
    async with engine.begin() as conn:
        await conn.execute(text("DELETE FROM chapters"))
        await conn.execute(text("DELETE FROM comic_genre"))
        await conn.execute(text("DELETE FROM genres"))
        await conn.execute(text("DELETE FROM comics"))
        print("Database cleared!")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(clear())
