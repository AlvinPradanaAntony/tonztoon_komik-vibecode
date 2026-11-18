"""Read-only readiness summary. Never prints environment values or identities."""
import asyncio
from sqlalchemy import text
from app.database import engine
from app.config import settings


async def main():
    async with engine.connect() as connection:
        for table in ("comics", "chapters", "genres", "profiles"):
            count = await connection.scalar(text(f"select count(*) from public.{table}"))
            print(f"{table}: {count}")
        print("monitoring_schema:", bool(await connection.scalar(text(
            "select exists(select 1 from pg_namespace where nspname='monitoring')"))))
    print("configured_admin_ids:", len([v for v in settings.ADMIN_USER_IDS.split(",") if v.strip()]))
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
