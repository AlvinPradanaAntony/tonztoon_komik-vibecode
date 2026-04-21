"""
Tonztoon Komik — Pydantic Schemas

Semua schema di-export dari sini:
    from app.schemas import ComicResponse, ChapterImageItem, ...
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
from app.schemas.chapter import ChapterImageItem
from app.schemas.source import (
    SourceInfoResponse,
    SourceChapterListItem,
    SourceChapterResponse,
)

__all__ = [
    "ComicBase",
    "ComicCreate",
    "ComicResponse",
    "ComicListResponse",
    "GenreBase",
    "GenreCreate",
    "GenreResponse",
    "ChapterImageItem",
    "SourceInfoResponse",
    "SourceChapterListItem",
    "SourceChapterResponse",
]
