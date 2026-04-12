"""Clear database for re-testing."""
import asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine


async def clear():
    engine = create_async_engine(
        "postgresql+asyncpg://postgres:postgres@localhost:5432/tonztoon_komik"
    )
    async with engine.begin() as conn:
        await conn.execute(text("DELETE FROM chapters"))
        await conn.execute(text("DELETE FROM comic_genre"))
        await conn.execute(text("DELETE FROM genres"))
        await conn.execute(text("DELETE FROM comics"))
        print("Database cleared!")

    await engine.dispose()


asyncio.run(clear())
