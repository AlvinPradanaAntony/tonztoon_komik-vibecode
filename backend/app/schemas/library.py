"""
Schemas untuk domain user library, progress sync, dan reader preferences.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


READING_MODE = Literal["vertical", "paged"]
READING_DIRECTION = Literal["ltr", "rtl"]
DOWNLOAD_STATUS = Literal[
    "pending",
    "downloading",
    "completed",
    "failed",
    "cancelled",
    "missing",
]


class ComicSelector(BaseModel):
    """Selector publik komik lintas source."""

    source_name: str = Field(..., max_length=100, examples=["komiku_asia"])
    comic_slug: str = Field(..., max_length=600, examples=["solo-leveling"])


class ChapterSelector(ComicSelector):
    """Selector chapter publik lintas source."""

    chapter_number: float = Field(..., ge=0, examples=[201.0])


class LibraryComicRef(BaseModel):
    """Snapshot ringan komik untuk response library."""

    comic_id: int
    source_name: str
    slug: str
    title: str
    cover_image_url: str | None = None
    author: str | None = None
    status: str | None = None
    type: str | None = None
    rating: float | None = None
    total_view: int | None = None


class LibraryChapterRef(BaseModel):
    """Snapshot ringan chapter untuk response library."""

    chapter_id: int
    chapter_number: float
    title: str | None = None
    release_date: datetime | None = None
    total_images: int = Field(default=0, ge=0)


class ReaderPreferenceUpdateRequest(BaseModel):
    """Payload update reader settings yang dapat disinkronkan."""

    default_reading_mode: READING_MODE = "vertical"
    reading_direction: READING_DIRECTION = "ltr"
    auto_next: bool = True
    mark_read_on_complete: bool = True
    default_binge_mode: bool = False


class ReaderPreferenceResponse(ReaderPreferenceUpdateRequest):
    """Reader settings tersimpan per user."""

    updated_at: datetime


class ProgressUpsertRequest(ChapterSelector):
    """Payload sync progress / continue reading."""

    reading_mode: READING_MODE = "vertical"
    scroll_offset: float | None = Field(default=None, ge=0)
    page_index: int | None = Field(default=None, ge=0)
    last_read_page_item_index: int | None = Field(default=None, ge=0)
    total_page_items: int | None = Field(default=None, ge=0)
    is_completed: bool = False


class ProgressResponse(BaseModel):
    """Progress baca tersimpan per komik."""

    id: int
    comic: LibraryComicRef
    chapter: LibraryChapterRef
    reading_mode: READING_MODE
    scroll_offset: float | None = None
    page_index: int | None = None
    last_read_page_item_index: int | None = None
    total_page_items: int | None = None
    is_completed: bool = False
    last_read_at: datetime
    updated_at: datetime


class BookmarkResponse(BaseModel):
    """Item bookmark komik."""

    id: int
    comic: LibraryComicRef
    created_at: datetime
    updated_at: datetime


class CollectionCreateRequest(BaseModel):
    """Payload create collection."""

    name: str = Field(..., min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        normalized = " ".join(value.split()).strip()
        if not normalized:
            raise ValueError("Collection name cannot be empty.")
        return normalized


class CollectionUpdateRequest(CollectionCreateRequest):
    """Payload rename collection."""


class CollectionSummaryResponse(BaseModel):
    """Ringkasan collection untuk picker / checklist."""

    id: int
    name: str
    total_items: int = Field(default=0, ge=0)
    created_at: datetime
    updated_at: datetime


class CollectionResponse(CollectionSummaryResponse):
    """Detail collection dengan daftar komik."""

    items: list[LibraryComicRef] = Field(default_factory=list)


class FavoriteSceneCreateRequest(ChapterSelector):
    """Payload save favorite scene dari reader."""

    page_item_index: int = Field(..., ge=0)
    image_url: str | None = Field(default=None, max_length=1000)
    note: str | None = Field(default=None, max_length=1000)

    @field_validator("note")
    @classmethod
    def normalize_note(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None


class FavoriteSceneResponse(BaseModel):
    """Favorite scene yang tersimpan."""

    id: int
    comic: LibraryComicRef
    chapter: LibraryChapterRef
    page_item_index: int
    image_url: str | None = None
    note: str | None = None
    created_at: datetime
    updated_at: datetime


class HistoryItemResponse(BaseModel):
    """Riwayat baca komik terakhir."""

    id: int
    comic: LibraryComicRef
    chapter: LibraryChapterRef
    reading_mode: READING_MODE
    scroll_offset: float | None = None
    page_index: int | None = None
    last_read_page_item_index: int | None = None
    total_page_items: int | None = None
    last_read_at: datetime
    updated_at: datetime


class DownloadEntryUpsertRequest(ChapterSelector):
    """Payload update intent/status offline per chapter."""

    status: DOWNLOAD_STATUS = "pending"
    source_device_id: str | None = Field(default=None, max_length=120)
    last_error: str | None = Field(default=None, max_length=1000)

    @field_validator("source_device_id")
    @classmethod
    def normalize_source_device_id(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None

    @field_validator("last_error")
    @classmethod
    def normalize_last_error(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized[:1000] if normalized else None


class DownloadEntryResponse(BaseModel):
    """Status intent download chapter yang sinkron di cloud."""

    id: int
    comic: LibraryComicRef
    chapter: LibraryChapterRef
    status: DOWNLOAD_STATUS
    source_device_id: str | None = None
    last_error: str | None = None
    requested_at: datetime
    downloaded_at: datetime | None = None
    updated_at: datetime


class DownloadBatchRequest(ComicSelector):
    """Enqueue intent download untuk banyak chapter sekaligus."""

    chapter_numbers: list[float] | None = Field(
        default=None,
        description="Jika kosong, backend akan enqueue semua chapter komik.",
    )
    status: DOWNLOAD_STATUS = "pending"
    source_device_id: str | None = Field(default=None, max_length=120)


class DownloadBatchResponse(BaseModel):
    """Ringkasan hasil enqueue batch download intent."""

    comic: LibraryComicRef
    requested_total: int = Field(default=0, ge=0)
    created_total: int = Field(default=0, ge=0)
    updated_total: int = Field(default=0, ge=0)
    chapter_numbers: list[float] = Field(default_factory=list)


class LibrarySummaryCounts(BaseModel):
    """Counter ringkas untuk tab library."""

    bookmarks: int = Field(default=0, ge=0)
    collections: int = Field(default=0, ge=0)
    favorite_scenes: int = Field(default=0, ge=0)
    history: int = Field(default=0, ge=0)
    downloads: int = Field(default=0, ge=0)
    continue_reading: int = Field(default=0, ge=0)


class LibrarySummaryResponse(BaseModel):
    """Summary user-library untuk home/library screen."""

    counts: LibrarySummaryCounts
    continue_reading: list[ProgressResponse] = Field(default_factory=list)
    recent_history: list[HistoryItemResponse] = Field(default_factory=list)
    collections: list[CollectionSummaryResponse] = Field(default_factory=list)
    reader_preferences: ReaderPreferenceResponse | None = None


class LibraryComicStateResponse(BaseModel):
    """State terpadu per komik untuk CTA di comic detail."""

    comic: LibraryComicRef
    bookmarked: bool = False
    collections: list[CollectionSummaryResponse] = Field(default_factory=list)
    progress: ProgressResponse | None = None
    history: HistoryItemResponse | None = None
    favorite_scene_count: int = Field(default=0, ge=0)
    download_status_counts: dict[str, int] = Field(default_factory=dict)
    download_entries: list[DownloadEntryResponse] = Field(default_factory=list)


class SyncCollectionImport(BaseModel):
    """Payload koleksi untuk import migrasi local -> cloud."""

    name: str = Field(..., min_length=1, max_length=120)
    comics: list[ComicSelector] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        normalized = " ".join(value.split()).strip()
        if not normalized:
            raise ValueError("Collection name cannot be empty.")
        return normalized


class LibrarySyncImportRequest(BaseModel):
    """Batch import snapshot library untuk one-time migration."""

    bookmarks: list[ComicSelector] = Field(default_factory=list)
    collections: list[SyncCollectionImport] = Field(default_factory=list)
    progress: list[ProgressUpsertRequest] = Field(default_factory=list)
    favorite_scenes: list[FavoriteSceneCreateRequest] = Field(default_factory=list)
    downloads: list[DownloadEntryUpsertRequest] = Field(default_factory=list)
    reader_preferences: ReaderPreferenceUpdateRequest | None = None


class LibrarySyncImportResponse(BaseModel):
    """Ringkasan hasil import migrasi ke cloud."""

    bookmarks_upserted: int = Field(default=0, ge=0)
    collections_upserted: int = Field(default=0, ge=0)
    collection_items_upserted: int = Field(default=0, ge=0)
    progress_upserted: int = Field(default=0, ge=0)
    favorite_scenes_upserted: int = Field(default=0, ge=0)
    downloads_upserted: int = Field(default=0, ge=0)
    reader_preferences_updated: bool = False
