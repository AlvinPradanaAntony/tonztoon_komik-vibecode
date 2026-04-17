"""
Tonztoon Komik — Pydantic Schemas

Semua schema di-export dari sini:
    from app.schemas import ComicResponse, ChapterResponse, ...
"""

from app.schemas.comic import (
    ComicBase,
    ComicCreate,
    ComicResponse,
    ComicListResponse,
    GenreBase,
    GenreCreate,
    GenreResponse,
)
from app.schemas.chapter import (
    ChapterBase,
    ChapterCreate,
    ChapterResponse,
    ChapterImageItem,
)
from app.schemas.source import (
    SourceInfoResponse,
    SourceChapterListItem,
    SourceChapterImagesResponse,
)

__all__ = [
    "ComicBase",
    "ComicCreate",
    "ComicResponse",
    "ComicListResponse",
    "GenreBase",
    "GenreCreate",
    "GenreResponse",
    "ChapterBase",
    "ChapterCreate",
    "ChapterResponse",
    "ChapterImageItem",
    "SourceInfoResponse",
    "SourceChapterListItem",
    "SourceChapterImagesResponse",
]
