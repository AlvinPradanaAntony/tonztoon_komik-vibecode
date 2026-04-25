"""
Tonztoon Komik — Async Database Connection

Menggunakan SQLAlchemy 2.0 async engine dengan adapter asyncpg
untuk koneksi PostgreSQL yang non-blocking.
"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


# Async engine — connection pool ke PostgreSQL
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.APP_DEBUG,
    pool_size=5,
    max_overflow=10,
    connect_args={
        "statement_cache_size": 0,
        "prepared_statement_cache_size": 0,
    },
)

# Session factory — setiap request mendapat session independen
async_session = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """Base class untuk semua SQLAlchemy ORM models."""
    pass


async def get_db() -> AsyncSession:
    """
    Dependency injection untuk FastAPI.
    Menyediakan database session per-request yang otomatis di-close.

    Usage di route:
        @router.get("/...")
        async def my_route(db: AsyncSession = Depends(get_db)):
            ...
    """
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()
