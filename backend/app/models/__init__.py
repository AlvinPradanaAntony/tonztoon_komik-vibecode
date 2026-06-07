"""
Tonztoon Komik — SQLAlchemy ORM Models

Semua model database di-export dari sini agar mudah di-import:
    from app.models import Comic, Chapter, Genre, SourceStat
"""

from app.models.comic import Comic, Genre, comic_genre
from app.models.chapter import Chapter
from app.models.chapter_image_job import ChapterImageJob
from app.models.source_stat import SourceStat
from app.models.profile import Profile
from app.models.helpdesk import HelpdeskSubmission
from app.models.push_notification import PushNotificationEvent, UserPushDevice
from app.models.library import (
    ReaderPreference,
    UserBookmark,
    UserBookmarkLink,
    UserCollection,
    UserCollectionComic,
    UserCompletedChapter,
    UserDownloadEntry,
    UserFavoriteScene,
    UserHistoryEntry,
    UserProgress,
    UserReadingStat,
)

__all__ = [
    "Comic",
    "Chapter",
    "ChapterImageJob",
    "Genre",
    "SourceStat",
    "Profile",
    "HelpdeskSubmission",
    "PushNotificationEvent",
    "UserPushDevice",
    "comic_genre",
    "ReaderPreference",
    "UserBookmark",
    "UserBookmarkLink",
    "UserCollection",
    "UserCollectionComic",
    "UserCompletedChapter",
    "UserDownloadEntry",
    "UserFavoriteScene",
    "UserHistoryEntry",
    "UserProgress",
    "UserReadingStat",
]
