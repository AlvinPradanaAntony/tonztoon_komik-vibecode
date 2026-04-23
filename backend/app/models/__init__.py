"""
Tonztoon Komik — SQLAlchemy ORM Models

Semua model database di-export dari sini agar mudah di-import:
    from app.models import Comic, Chapter, Genre, SourceStat
"""

from app.models.comic import Comic, Genre, comic_genre
from app.models.chapter import Chapter
from app.models.source_stat import SourceStat
from app.models.profile import Profile
from app.models.library import (
    ReaderPreference,
    UserBookmark,
    UserCollection,
    UserCollectionComic,
    UserDownloadEntry,
    UserFavoriteScene,
    UserHistoryEntry,
    UserProgress,
)

__all__ = [
    "Comic",
    "Chapter",
    "Genre",
    "SourceStat",
    "Profile",
    "comic_genre",
    "ReaderPreference",
    "UserBookmark",
    "UserCollection",
    "UserCollectionComic",
    "UserDownloadEntry",
    "UserFavoriteScene",
    "UserHistoryEntry",
    "UserProgress",
]
