"""Provision only additive monitoring tables: python -m scripts.admin_db."""
import asyncio
from sqlalchemy import text
from app.database import engine
from app.admin.tables import metadata


async def main():
    async with engine.begin() as connection:
        await connection.execute(text("CREATE SCHEMA IF NOT EXISTS monitoring"))
        await connection.run_sync(metadata.create_all)
        await connection.execute(text("ALTER TABLE monitoring.incidents ADD COLUMN IF NOT EXISTS healthy_since timestamptz"))
        await connection.execute(text("ALTER TABLE monitoring.incidents ADD COLUMN IF NOT EXISTS condition_since timestamptz"))
    await engine.dispose()
    print("Admin schema ready; existing business tables unchanged.")


if __name__ == "__main__":
    asyncio.run(main())
