"""
Tonztoon Komik — SQLAlchemy ORM Models

Semua model database di-export dari sini agar mudah di-import:
    from app.models import Comic, Chapter, Genre, SourceStat
"""

from app.models.comic import Comic, Genre, comic_genre
from app.models.chapter import Chapter
from app.models.source_stat import SourceStat

__all__ = [
    "Comic",
    "Chapter",
    "Genre",
    "SourceStat",
    "comic_genre",
]
