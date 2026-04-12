"""Quick data verification script."""
import asyncio
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine


async def check():
    engine = create_async_engine(
        "postgresql+asyncpg://postgres:postgres@localhost:5432/tonztoon_komik"
    )
    async with engine.begin() as conn:
        # Comics
        print("=" * 60)
        print("COMICS:")
        print("=" * 60)
        result = await conn.execute(
            text("SELECT id, title, slug, type, status, author, source_url FROM comics ORDER BY id")
        )
        for r in result:
            print(f"  [{r[0]}] {r[1]} | type={r[3]} | status={r[4]} | author={r[5]}")
            print(f"       url={r[6]}")

        # Chapters
        print("\n" + "=" * 60)
        print("CHAPTERS:")
        print("=" * 60)
        result = await conn.execute(
            text("SELECT c.id, co.title, c.chapter_number, c.title, c.source_url, jsonb_array_length(c.images) as img_count FROM chapters c JOIN comics co ON c.comic_id = co.id ORDER BY co.id, c.chapter_number DESC")
        )
        for r in result:
            print(f"  [{r[0]}] {r[1]} - Ch {r[2]} ({r[3]}) | {r[5]} images")

        # Genres
        print("\n" + "=" * 60)
        print("GENRES:")
        print("=" * 60)
        result = await conn.execute(
            text("SELECT g.name, COUNT(cg.comic_id) as comics FROM genres g LEFT JOIN comic_genre cg ON g.id = cg.genre_id GROUP BY g.name ORDER BY comics DESC")
        )
        for r in result:
            print(f"  {r[0]}: {r[1]} comics")

    await engine.dispose()


asyncio.run(check())
