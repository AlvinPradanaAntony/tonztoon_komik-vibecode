"""
Schemas untuk domain user library, progress sync, dan reader preferences.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


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
DOWNLOAD_BATCH_MAX_CHAPTER_NUMBERS = 5_000
SYNC_IMPORT_CATEGORY_MAX_ITEMS = 2_000
SYNC_IMPORT_MAX_COLLECTIONS = 200
SYNC_IMPORT_MAX_COMICS_PER_COLLECTION = 1_000
SYNC_IMPORT_MAX_TOTAL_ITEMS = 10_000


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
    mark_read_on_complete: bool = True
    default_binge_mode: bool = False
    auto_scroll_enabled: bool = False
    auto_scroll_speed: float = Field(default=1.0, ge=0.5, le=1.5)


class ReaderPreferenceResponse(ReaderPreferenceUpdateRequest):
    """Reader settings tersimpan per user."""

    updated_at: datetime


class ReadingTimeDeltaRequest(BaseModel):
    """Delta durasi baca yang dikirim dari reader."""

    delta_seconds: int = Field(..., ge=1)


class ReadingTimeResponse(BaseModel):
    """Akumulasi waktu baca user."""

    total_reading_seconds: int = Field(default=0, ge=0)
    updated_at: datetime


class ProgressUpsertRequest(ChapterSelector):
    """Payload sync progress / continue reading."""

    reading_mode: READING_MODE = "vertical"
    scroll_offset: float | None = Field(default=None, ge=0)
    page_index: int | None = Field(default=None, ge=0)
    last_read_page_item_index: int | None = Field(default=None, ge=0)
    total_page_items: int | None = Field(default=None, ge=0)
    is_completed: bool = False


class CompletedChapterImportRequest(ChapterSelector):
    """Chapter yang pernah selesai dibaca saat import snapshot lokal."""


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
    linked_comics: list[LibraryComicRef] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class BookmarkLinkCandidate(BaseModel):
    """Kandidat source alternatif untuk satu bookmark."""

    comic: LibraryComicRef
    confidence: float = Field(..., ge=0, le=1)


class BookmarkLinkCandidateGroup(BaseModel):
    """Kandidat yang dikelompokkan berdasarkan bookmark utama."""

    bookmark: LibraryComicRef
    candidates: list[BookmarkLinkCandidate] = Field(default_factory=list)


class BookmarkLinkCandidatePage(BaseModel):
    """Satu batch bookmark yang sudah dipindai."""

    items: list[BookmarkLinkCandidateGroup] = Field(default_factory=list)
    scanned_total: int = Field(default=0, ge=0)
    next_offset: int = Field(default=0, ge=0)
    has_more: bool = False


class BookmarkLinkCreateRequest(BaseModel):
    """Satu relasi source yang telah dikonfirmasi user."""

    bookmark: ComicSelector
    linked_comic: ComicSelector
    confidence: float = Field(default=1, ge=0, le=1)


class BookmarkLinkBatchRequest(BaseModel):
    """Batch relasi source hasil dialog konfirmasi."""

    links: list[BookmarkLinkCreateRequest] = Field(
        default_factory=list,
        max_length=2_000,
    )


class BookmarkLinkBatchResponse(BaseModel):
    linked_total: int = Field(default=0, ge=0)
    completed_propagated: int = Field(default=0, ge=0)
    completion_sync_bookmark_ids: list[int] = Field(default_factory=list)


class BookmarkLinkCompletionSyncRequest(BaseModel):
    """Batch grup bookmark yang akan disinkronkan status completed-nya."""

    bookmark_ids: list[int] = Field(
        default_factory=list,
        min_length=1,
        max_length=25,
    )


class BookmarkLinkCompletionSyncResponse(BaseModel):
    processed_groups: int = Field(default=0, ge=0)
    completed_propagated: int = Field(default=0, ge=0)


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
    is_completed: bool = False
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
        max_length=DOWNLOAD_BATCH_MAX_CHAPTER_NUMBERS,
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
    reading_time_seconds: int = Field(default=0, ge=0)
    continue_reading: list[ProgressResponse] = Field(default_factory=list)
    recent_history: list[HistoryItemResponse] = Field(default_factory=list)
    collections: list[CollectionSummaryResponse] = Field(default_factory=list)
    reader_preferences: ReaderPreferenceResponse | None = None


class LibraryComicStateResponse(BaseModel):
    """State terpadu per komik untuk CTA di comic detail."""

    comic: LibraryComicRef
    bookmarked: bool = False
    bookmark_relation: Literal["none", "direct", "linked"] = "none"
    bookmark_origin: LibraryComicRef | None = None
    linked_comics: list[LibraryComicRef] = Field(default_factory=list)
    collections: list[CollectionSummaryResponse] = Field(default_factory=list)
    progress: ProgressResponse | None = None
    history: HistoryItemResponse | None = None
    completed_chapter_numbers: list[float] = Field(default_factory=list)
    favorite_scene_count: int = Field(default=0, ge=0)
    download_status_counts: dict[str, int] = Field(default_factory=dict)
    download_entries: list[DownloadEntryResponse] = Field(default_factory=list)


class SyncCollectionImport(BaseModel):
    """Payload koleksi untuk import migrasi local -> cloud."""

    name: str = Field(..., min_length=1, max_length=120)
    comics: list[ComicSelector] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_MAX_COMICS_PER_COLLECTION,
    )

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        normalized = " ".join(value.split()).strip()
        if not normalized:
            raise ValueError("Collection name cannot be empty.")
        return normalized


class LibrarySyncImportRequest(BaseModel):
    """Batch import snapshot library untuk one-time migration."""

    bookmarks: list[ComicSelector] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    bookmark_links: list[BookmarkLinkCreateRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    collections: list[SyncCollectionImport] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_MAX_COLLECTIONS,
    )
    progress: list[ProgressUpsertRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    history: list[ProgressUpsertRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    completed_chapters: list[CompletedChapterImportRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    favorite_scenes: list[FavoriteSceneCreateRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    downloads: list[DownloadEntryUpsertRequest] = Field(
        default_factory=list,
        max_length=SYNC_IMPORT_CATEGORY_MAX_ITEMS,
    )
    reader_preferences: ReaderPreferenceUpdateRequest | None = None
    reading_time_seconds: int = Field(default=0, ge=0)

    @model_validator(mode="after")
    def validate_total_items(self) -> LibrarySyncImportRequest:
        total_items = (
            len(self.bookmarks)
            + len(self.bookmark_links)
            + len(self.collections)
            + sum(len(collection.comics) for collection in self.collections)
            + len(self.progress)
            + len(self.history)
            + len(self.completed_chapters)
            + len(self.favorite_scenes)
            + len(self.downloads)
        )
        if total_items > SYNC_IMPORT_MAX_TOTAL_ITEMS:
            raise ValueError(
                f"Snapshot library maksimal {SYNC_IMPORT_MAX_TOTAL_ITEMS} item."
            )
        return self


class LibrarySyncImportResponse(BaseModel):
    """Ringkasan hasil import migrasi ke cloud."""

    bookmarks_upserted: int = Field(default=0, ge=0)
    bookmark_links_upserted: int = Field(default=0, ge=0)
    collections_upserted: int = Field(default=0, ge=0)
    collection_items_upserted: int = Field(default=0, ge=0)
    progress_upserted: int = Field(default=0, ge=0)
    history_upserted: int = Field(default=0, ge=0)
    completed_chapters_upserted: int = Field(default=0, ge=0)
    favorite_scenes_upserted: int = Field(default=0, ge=0)
    downloads_upserted: int = Field(default=0, ge=0)
    reader_preferences_updated: bool = False
    reading_time_seconds_imported: int = Field(default=0, ge=0)
    completion_sync_bookmark_ids: list[int] = Field(default_factory=list)
