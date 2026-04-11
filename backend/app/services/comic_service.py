"""
Tonztoon Komik — Comic Service (Business Logic)

Service layer yang memisahkan business logic dari route handlers.
Bisa digunakan oleh API routes maupun scraper.
"""

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Comic, Genre, comic_genre


async def get_comic_by_slug(db: AsyncSession, slug: str) -> Comic | None:
    """Ambil comic berdasarkan slug, termasuk genres dan chapters."""
    stmt = (
        select(Comic)
        .options(selectinload(Comic.genres), selectinload(Comic.chapters))
        .where(Comic.slug == slug)
    )
    result = await db.execute(stmt)
    return result.scalars().first()


async def get_or_create_genre(db: AsyncSession, name: str, slug: str) -> Genre:
    """Ambil genre yang sudah ada, atau buat baru."""
    stmt = select(Genre).where(Genre.slug == slug)
    result = await db.execute(stmt)
    genre = result.scalars().first()

    if genre is None:
        genre = Genre(name=name, slug=slug)
        db.add(genre)
        await db.flush()

    return genre


async def count_comics(db: AsyncSession, **filters) -> int:
    """Hitung total komik dengan optional filters."""
    stmt = select(func.count(Comic.id))
    for key, value in filters.items():
        if value is not None and hasattr(Comic, key):
            stmt = stmt.where(getattr(Comic, key) == value)
    result = await db.execute(stmt)
    return result.scalar() or 0
