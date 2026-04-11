"""
Tonztoon Komik — SQLAlchemy ORM Models

Semua model database di-export dari sini agar mudah di-import:
    from app.models import Comic, Chapter, Genre
"""

from app.models.comic import Comic, Genre, comic_genre
from app.models.chapter import Chapter

__all__ = [
    "Comic",
    "Chapter",
    "Genre",
    "comic_genre",
]
