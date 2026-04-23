"""
Service layer untuk domain user library dan progress sync.
"""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import UTC, datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import (
    Chapter,
    Comic,
    ReaderPreference,
    UserBookmark,
    UserCollection,
    UserCollectionComic,
    UserDownloadEntry,
    UserFavoriteScene,
    UserHistoryEntry,
    UserProgress,
)
from app.schemas.library import (
    BookmarkResponse,
    CollectionResponse,
    CollectionSummaryResponse,
    DownloadBatchRequest,
    DownloadBatchResponse,
    DownloadEntryResponse,
    DownloadEntryUpsertRequest,
    FavoriteSceneCreateRequest,
    FavoriteSceneResponse,
    HistoryItemResponse,
    LibraryChapterRef,
    LibraryComicRef,
    LibraryComicStateResponse,
    LibrarySummaryCounts,
    LibrarySummaryResponse,
    LibrarySyncImportRequest,
    LibrarySyncImportResponse,
    ProgressResponse,
    ProgressUpsertRequest,
    ReaderPreferenceResponse,
    ReaderPreferenceUpdateRequest,
)
from app.services.image_service import build_proxy_image_url

CHAPTER_NUMBER_TOLERANCE = 0.0001


def _utcnow() -> datetime:
    return datetime.now(UTC)


def normalize_collection_name(name: str) -> str:
    """Normalisasi nama koleksi untuk uniqueness case-insensitive."""
    return " ".join(name.split()).strip().casefold()


def build_comic_ref(comic: Comic) -> LibraryComicRef:
    """Bangun snapshot ringan komik untuk response library."""
    return LibraryComicRef(
        comic_id=comic.id,
        source_name=comic.source_name,
        slug=comic.slug,
        title=comic.title,
        cover_image_url=build_proxy_image_url(comic.cover_image_url),
        author=comic.author,
        status=comic.status,
        type=comic.type,
        rating=comic.rating,
        total_view=comic.total_view,
    )


def build_chapter_ref(chapter: Chapter) -> LibraryChapterRef:
    """Bangun snapshot ringan chapter untuk response library."""
    return LibraryChapterRef(
        chapter_id=chapter.id,
        chapter_number=chapter.chapter_number,
        title=chapter.title,
        release_date=chapter.release_date,
        total_images=len(chapter.images) if chapter.images else 0,
    )


def build_reader_preferences_response(preference: ReaderPreference) -> ReaderPreferenceResponse:
    """Serialisasi reader preference ORM -> schema."""
    return ReaderPreferenceResponse(
        default_reading_mode=preference.default_reading_mode,
        reading_direction=preference.reading_direction,
        auto_next=preference.auto_next,
        mark_read_on_complete=preference.mark_read_on_complete,
        default_binge_mode=preference.default_binge_mode,
        updated_at=preference.updated_at,
    )


def build_progress_response(progress: UserProgress) -> ProgressResponse:
    """Serialisasi progress ORM -> schema."""
    return ProgressResponse(
        id=progress.id,
        comic=build_comic_ref(progress.comic),
        chapter=build_chapter_ref(progress.chapter),
        reading_mode=progress.reading_mode,
        scroll_offset=progress.scroll_offset,
        page_index=progress.page_index,
        last_read_page_item_index=progress.last_read_page_item_index,
        total_page_items=progress.total_page_items,
        is_completed=progress.is_completed,
        last_read_at=progress.last_read_at,
        updated_at=progress.updated_at,
    )


def build_history_response(entry: UserHistoryEntry) -> HistoryItemResponse:
    """Serialisasi history ORM -> schema."""
    return HistoryItemResponse(
        id=entry.id,
        comic=build_comic_ref(entry.comic),
        chapter=build_chapter_ref(entry.chapter),
        reading_mode=entry.reading_mode,
        scroll_offset=entry.scroll_offset,
        page_index=entry.page_index,
        last_read_page_item_index=entry.last_read_page_item_index,
        total_page_items=entry.total_page_items,
        last_read_at=entry.last_read_at,
        updated_at=entry.updated_at,
    )


def build_bookmark_response(bookmark: UserBookmark) -> BookmarkResponse:
    """Serialisasi bookmark ORM -> schema."""
    return BookmarkResponse(
        id=bookmark.id,
        comic=build_comic_ref(bookmark.comic),
        created_at=bookmark.created_at,
        updated_at=bookmark.updated_at,
    )


def build_collection_summary_response(collection: UserCollection) -> CollectionSummaryResponse:
    """Ringkasan collection untuk list dan picker."""
    return CollectionSummaryResponse(
        id=collection.id,
        name=collection.name,
        total_items=len(collection.items),
        created_at=collection.created_at,
        updated_at=collection.updated_at,
    )


def build_collection_response(collection: UserCollection) -> CollectionResponse:
    """Detail collection dengan daftar komik."""
    items = [build_comic_ref(item.comic) for item in collection.items]
    return CollectionResponse(
        id=collection.id,
        name=collection.name,
        total_items=len(items),
        created_at=collection.created_at,
        updated_at=collection.updated_at,
        items=items,
    )


def build_favorite_scene_response(scene: UserFavoriteScene) -> FavoriteSceneResponse:
    """Serialisasi favorite scene ORM -> schema."""
    return FavoriteSceneResponse(
        id=scene.id,
        comic=build_comic_ref(scene.comic),
        chapter=build_chapter_ref(scene.chapter),
        page_item_index=scene.page_item_index,
        image_url=build_proxy_image_url(scene.image_url),
        note=scene.note,
        created_at=scene.created_at,
        updated_at=scene.updated_at,
    )


def build_download_response(entry: UserDownloadEntry) -> DownloadEntryResponse:
    """Serialisasi download intent ORM -> schema."""
    return DownloadEntryResponse(
        id=entry.id,
        comic=build_comic_ref(entry.comic),
        chapter=build_chapter_ref(entry.chapter),
        status=entry.status,
        source_device_id=entry.source_device_id,
        last_error=entry.last_error,
        requested_at=entry.requested_at,
        downloaded_at=entry.downloaded_at,
        updated_at=entry.updated_at,
    )


async def get_comic_by_public_key(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
) -> Comic | None:
    """Ambil comic berdasarkan identitas publik source + slug."""
    result = await db.execute(
        select(Comic).where(
            Comic.source_name == source_name,
            Comic.slug == comic_slug,
        )
    )
    return result.scalars().first()


async def get_chapter_by_public_key(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> Chapter | None:
    """Ambil chapter berdasarkan identitas publik source + comic + chapter."""
    result = await db.execute(
        select(Chapter)
        .join(Comic, Comic.id == Chapter.comic_id)
        .where(
            Comic.source_name == source_name,
            Comic.slug == comic_slug,
            Chapter.chapter_number >= chapter_number - CHAPTER_NUMBER_TOLERANCE,
            Chapter.chapter_number <= chapter_number + CHAPTER_NUMBER_TOLERANCE,
        )
    )
    return result.scalars().first()


async def resolve_comic_or_raise(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
) -> Comic:
    """Resolve comic atau raise LookupError jika tidak ada."""
    comic = await get_comic_by_public_key(db, source_name, comic_slug)
    if comic is None:
        raise LookupError(f"Comic {source_name}/{comic_slug} tidak ditemukan.")
    return comic


async def resolve_chapter_or_raise(
    db: AsyncSession,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> Chapter:
    """Resolve chapter atau raise LookupError jika tidak ada."""
    chapter = await get_chapter_by_public_key(db, source_name, comic_slug, chapter_number)
    if chapter is None:
        raise LookupError(
            f"Chapter {chapter_number} untuk {source_name}/{comic_slug} tidak ditemukan."
        )
    return chapter


async def get_or_create_reader_preferences(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> ReaderPreference:
    """Ambil preferensi reader, buat default jika belum ada."""
    preference = await db.get(ReaderPreference, user_id)
    if preference is None:
        preference = ReaderPreference(user_id=user_id)
        db.add(preference)
        await db.commit()
        await db.refresh(preference)
    return preference


async def update_reader_preferences(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: ReaderPreferenceUpdateRequest,
) -> ReaderPreference:
    """Upsert reader preferences user."""
    preference = await db.get(ReaderPreference, user_id)
    if preference is None:
        preference = ReaderPreference(user_id=user_id)
        db.add(preference)

    preference.default_reading_mode = payload.default_reading_mode
    preference.reading_direction = payload.reading_direction
    preference.auto_next = payload.auto_next
    preference.mark_read_on_complete = payload.mark_read_on_complete
    preference.default_binge_mode = payload.default_binge_mode
    preference.updated_at = _utcnow()

    await db.commit()
    await db.refresh(preference)
    return preference


async def list_bookmarks(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[UserBookmark]:
    """List bookmark user terbaru."""
    result = await db.execute(
        select(UserBookmark)
        .where(UserBookmark.user_id == user_id)
        .order_by(UserBookmark.updated_at.desc(), UserBookmark.id.desc())
    )
    return result.scalars().all()


async def set_bookmark(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
) -> UserBookmark:
    """Upsert bookmark komik."""
    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    result = await db.execute(
        select(UserBookmark).where(
            UserBookmark.user_id == user_id,
            UserBookmark.comic_id == comic.id,
        )
    )
    bookmark = result.scalars().first()
    if bookmark is None:
        bookmark = UserBookmark(user_id=user_id, comic_id=comic.id)
        db.add(bookmark)
    bookmark.updated_at = _utcnow()
    await db.commit()
    await db.refresh(bookmark)
    return bookmark


async def delete_bookmark(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
) -> bool:
    """Hapus bookmark komik jika ada."""
    comic = await get_comic_by_public_key(db, source_name, comic_slug)
    if comic is None:
        return False

    result = await db.execute(
        delete(UserBookmark)
        .where(
            UserBookmark.user_id == user_id,
            UserBookmark.comic_id == comic.id,
        )
        .returning(UserBookmark.id)
    )
    deleted_id = result.scalar_one_or_none()
    await db.commit()
    return deleted_id is not None


async def _load_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
) -> UserCollection | None:
    result = await db.execute(
        select(UserCollection)
        .options(selectinload(UserCollection.items).selectinload(UserCollectionComic.comic))
        .where(
            UserCollection.user_id == user_id,
            UserCollection.id == collection_id,
        )
    )
    return result.scalars().first()


async def list_collections(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[UserCollection]:
    """List semua collection user."""
    result = await db.execute(
        select(UserCollection)
        .options(selectinload(UserCollection.items).selectinload(UserCollectionComic.comic))
        .where(UserCollection.user_id == user_id)
        .order_by(UserCollection.updated_at.desc(), UserCollection.id.desc())
    )
    return result.scalars().unique().all()


async def create_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    name: str,
) -> UserCollection:
    """Buat collection baru dengan nama unik case-insensitive."""
    normalized_name = normalize_collection_name(name)
    existing = await db.execute(
        select(UserCollection).where(
            UserCollection.user_id == user_id,
            UserCollection.normalized_name == normalized_name,
        )
    )
    if existing.scalars().first() is not None:
        raise ValueError("Collection dengan nama tersebut sudah ada.")

    collection = UserCollection(
        user_id=user_id,
        name=name,
        normalized_name=normalized_name,
    )
    db.add(collection)
    await db.commit()
    return await _load_collection(db, user_id, collection.id)


async def get_or_create_collection_by_name(
    db: AsyncSession,
    user_id: uuid.UUID,
    name: str,
) -> UserCollection:
    """Ambil collection berdasarkan nama atau buat baru."""
    normalized_name = normalize_collection_name(name)
    result = await db.execute(
        select(UserCollection).where(
            UserCollection.user_id == user_id,
            UserCollection.normalized_name == normalized_name,
        )
    )
    collection = result.scalars().first()
    if collection is not None:
        return await _load_collection(db, user_id, collection.id)
    return await create_collection(db, user_id, name)


async def rename_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
    new_name: str,
) -> UserCollection:
    """Ubah nama collection dengan guard uniqueness."""
    collection = await _load_collection(db, user_id, collection_id)
    if collection is None:
        raise LookupError("Collection tidak ditemukan.")

    normalized_name = normalize_collection_name(new_name)
    result = await db.execute(
        select(UserCollection).where(
            UserCollection.user_id == user_id,
            UserCollection.normalized_name == normalized_name,
            UserCollection.id != collection_id,
        )
    )
    if result.scalars().first() is not None:
        raise ValueError("Collection dengan nama tersebut sudah ada.")

    collection.name = new_name
    collection.normalized_name = normalized_name
    collection.updated_at = _utcnow()
    await db.commit()
    return await _load_collection(db, user_id, collection_id)


async def delete_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
) -> bool:
    """Hapus satu collection user."""
    result = await db.execute(
        delete(UserCollection)
        .where(
            UserCollection.user_id == user_id,
            UserCollection.id == collection_id,
        )
        .returning(UserCollection.id)
    )
    deleted_id = result.scalar_one_or_none()
    await db.commit()
    return deleted_id is not None


async def add_comic_to_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
    source_name: str,
    comic_slug: str,
) -> UserCollection:
    """Tambahkan komik ke collection jika belum ada."""
    collection = await _load_collection(db, user_id, collection_id)
    if collection is None:
        raise LookupError("Collection tidak ditemukan.")

    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    exists = any(item.comic_id == comic.id for item in collection.items)
    if not exists:
        db.add(UserCollectionComic(collection_id=collection_id, comic_id=comic.id))
        collection.updated_at = _utcnow()
        await db.commit()
    return await _load_collection(db, user_id, collection_id)


async def remove_comic_from_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
    source_name: str,
    comic_slug: str,
) -> UserCollection:
    """Hapus komik dari collection bila ada."""
    collection = await _load_collection(db, user_id, collection_id)
    if collection is None:
        raise LookupError("Collection tidak ditemukan.")

    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    await db.execute(
        delete(UserCollectionComic).where(
            UserCollectionComic.collection_id == collection_id,
            UserCollectionComic.comic_id == comic.id,
        )
    )
    collection.updated_at = _utcnow()
    await db.commit()
    return await _load_collection(db, user_id, collection_id)


async def upsert_history_from_progress(
    db: AsyncSession,
    user_id: uuid.UUID,
    chapter: Chapter,
    payload: ProgressUpsertRequest,
) -> UserHistoryEntry:
    """Sinkronkan history per comic berdasarkan progress terbaru."""
    result = await db.execute(
        select(UserHistoryEntry).where(
            UserHistoryEntry.user_id == user_id,
            UserHistoryEntry.comic_id == chapter.comic_id,
        )
    )
    history_entry = result.scalars().first()
    if history_entry is None:
        history_entry = UserHistoryEntry(
            user_id=user_id,
            comic_id=chapter.comic_id,
            chapter_id=chapter.id,
        )
        db.add(history_entry)

    history_entry.chapter_id = chapter.id
    history_entry.reading_mode = payload.reading_mode
    history_entry.scroll_offset = payload.scroll_offset
    history_entry.page_index = payload.page_index
    history_entry.last_read_page_item_index = payload.last_read_page_item_index
    history_entry.total_page_items = payload.total_page_items
    history_entry.last_read_at = _utcnow()
    history_entry.updated_at = history_entry.last_read_at
    return history_entry


async def upsert_progress(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: ProgressUpsertRequest,
) -> UserProgress:
    """Upsert posisi baca terakhir lalu mirror ke history."""
    chapter = await resolve_chapter_or_raise(
        db,
        payload.source_name,
        payload.comic_slug,
        payload.chapter_number,
    )

    result = await db.execute(
        select(UserProgress).where(
            UserProgress.user_id == user_id,
            UserProgress.comic_id == chapter.comic_id,
        )
    )
    progress = result.scalars().first()
    if progress is None:
        progress = UserProgress(
            user_id=user_id,
            comic_id=chapter.comic_id,
            chapter_id=chapter.id,
        )
        db.add(progress)

    progress.chapter_id = chapter.id
    progress.reading_mode = payload.reading_mode
    progress.scroll_offset = payload.scroll_offset
    progress.page_index = payload.page_index
    progress.last_read_page_item_index = payload.last_read_page_item_index
    progress.total_page_items = payload.total_page_items
    progress.is_completed = payload.is_completed
    progress.last_read_at = _utcnow()
    progress.updated_at = progress.last_read_at

    await upsert_history_from_progress(db, user_id, chapter, payload)

    await db.commit()

    progress_result = await db.execute(
        select(UserProgress)
        .where(UserProgress.id == progress.id)
        .options(
            selectinload(UserProgress.comic),
            selectinload(UserProgress.chapter),
        )
    )
    return progress_result.scalars().first()


async def list_continue_reading(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 20,
) -> list[UserProgress]:
    """List continue reading terbaru."""
    result = await db.execute(
        select(UserProgress)
        .where(UserProgress.user_id == user_id)
        .order_by(UserProgress.last_read_at.desc(), UserProgress.id.desc())
        .limit(limit)
    )
    return result.scalars().all()


async def get_progress_for_comic(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
) -> UserProgress | None:
    """Ambil progress untuk satu komik."""
    comic = await get_comic_by_public_key(db, source_name, comic_slug)
    if comic is None:
        return None
    result = await db.execute(
        select(UserProgress).where(
            UserProgress.user_id == user_id,
            UserProgress.comic_id == comic.id,
        )
    )
    return result.scalars().first()


async def list_history(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 50,
) -> list[UserHistoryEntry]:
    """List history terbaru."""
    result = await db.execute(
        select(UserHistoryEntry)
        .where(UserHistoryEntry.user_id == user_id)
        .order_by(UserHistoryEntry.last_read_at.desc(), UserHistoryEntry.id.desc())
        .limit(limit)
    )
    return result.scalars().all()


async def list_favorite_scenes(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 100,
) -> list[UserFavoriteScene]:
    """List favorite scenes user."""
    result = await db.execute(
        select(UserFavoriteScene)
        .where(UserFavoriteScene.user_id == user_id)
        .order_by(UserFavoriteScene.updated_at.desc(), UserFavoriteScene.id.desc())
        .limit(limit)
    )
    return result.scalars().all()


async def upsert_favorite_scene(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: FavoriteSceneCreateRequest,
) -> UserFavoriteScene:
    """Upsert favorite scene per chapter+page item."""
    chapter = await resolve_chapter_or_raise(
        db,
        payload.source_name,
        payload.comic_slug,
        payload.chapter_number,
    )
    result = await db.execute(
        select(UserFavoriteScene).where(
            UserFavoriteScene.user_id == user_id,
            UserFavoriteScene.chapter_id == chapter.id,
            UserFavoriteScene.page_item_index == payload.page_item_index,
        )
    )
    scene = result.scalars().first()
    if scene is None:
        scene = UserFavoriteScene(
            user_id=user_id,
            comic_id=chapter.comic_id,
            chapter_id=chapter.id,
            page_item_index=payload.page_item_index,
        )
        db.add(scene)

    scene.image_url = payload.image_url
    scene.note = payload.note
    scene.updated_at = _utcnow()
    await db.commit()

    refresh_result = await db.execute(
        select(UserFavoriteScene).where(UserFavoriteScene.id == scene.id)
    )
    return refresh_result.scalars().first()


async def delete_favorite_scene(
    db: AsyncSession,
    user_id: uuid.UUID,
    scene_id: int,
) -> bool:
    """Hapus favorite scene user."""
    result = await db.execute(
        delete(UserFavoriteScene)
        .where(
            UserFavoriteScene.user_id == user_id,
            UserFavoriteScene.id == scene_id,
        )
        .returning(UserFavoriteScene.id)
    )
    deleted_id = result.scalar_one_or_none()
    await db.commit()
    return deleted_id is not None


async def list_download_entries(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 200,
) -> list[UserDownloadEntry]:
    """List download intents user."""
    result = await db.execute(
        select(UserDownloadEntry)
        .where(UserDownloadEntry.user_id == user_id)
        .order_by(UserDownloadEntry.updated_at.desc(), UserDownloadEntry.id.desc())
        .limit(limit)
    )
    return result.scalars().all()


async def upsert_download_entry(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: DownloadEntryUpsertRequest,
) -> UserDownloadEntry:
    """Upsert status download intent per chapter."""
    chapter = await resolve_chapter_or_raise(
        db,
        payload.source_name,
        payload.comic_slug,
        payload.chapter_number,
    )

    result = await db.execute(
        select(UserDownloadEntry).where(
            UserDownloadEntry.user_id == user_id,
            UserDownloadEntry.chapter_id == chapter.id,
        )
    )
    entry = result.scalars().first()
    if entry is None:
        entry = UserDownloadEntry(
            user_id=user_id,
            comic_id=chapter.comic_id,
            chapter_id=chapter.id,
        )
        db.add(entry)

    entry.status = payload.status
    entry.source_device_id = payload.source_device_id
    entry.last_error = payload.last_error
    if payload.status == "completed":
        entry.downloaded_at = _utcnow()
    elif payload.status in {"pending", "downloading", "failed", "cancelled", "missing"}:
        entry.downloaded_at = None
    entry.updated_at = _utcnow()

    await db.commit()
    refresh_result = await db.execute(
        select(UserDownloadEntry).where(UserDownloadEntry.id == entry.id)
    )
    return refresh_result.scalars().first()


async def delete_download_entry(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
) -> bool:
    """Hapus download intent chapter."""
    chapter = await get_chapter_by_public_key(db, source_name, comic_slug, chapter_number)
    if chapter is None:
        return False
    result = await db.execute(
        delete(UserDownloadEntry)
        .where(
            UserDownloadEntry.user_id == user_id,
            UserDownloadEntry.chapter_id == chapter.id,
        )
        .returning(UserDownloadEntry.id)
    )
    deleted_id = result.scalar_one_or_none()
    await db.commit()
    return deleted_id is not None


async def enqueue_download_batch(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: DownloadBatchRequest,
) -> DownloadBatchResponse:
    """Enqueue download intent untuk banyak chapter sekaligus."""
    comic = await resolve_comic_or_raise(db, payload.source_name, payload.comic_slug)
    stmt = select(Chapter).where(Chapter.comic_id == comic.id)
    chapters_result = await db.execute(stmt.order_by(Chapter.chapter_number.desc()))
    chapters = chapters_result.scalars().all()

    if payload.chapter_numbers:
        requested_numbers = set(payload.chapter_numbers)
        filtered = [
            chapter
            for chapter in chapters
            if any(
                abs(chapter.chapter_number - requested_number) <= CHAPTER_NUMBER_TOLERANCE
                for requested_number in requested_numbers
            )
        ]
    else:
        filtered = chapters

    if not filtered:
        raise LookupError("Tidak ada chapter yang cocok untuk download batch.")

    created_total = 0
    updated_total = 0
    requested_chapter_numbers: list[float] = []

    for chapter in filtered:
        requested_chapter_numbers.append(chapter.chapter_number)
        result = await db.execute(
            select(UserDownloadEntry).where(
                UserDownloadEntry.user_id == user_id,
                UserDownloadEntry.chapter_id == chapter.id,
            )
        )
        entry = result.scalars().first()
        if entry is None:
            entry = UserDownloadEntry(
                user_id=user_id,
                comic_id=comic.id,
                chapter_id=chapter.id,
            )
            db.add(entry)
            created_total += 1
        else:
            updated_total += 1

        entry.status = payload.status
        entry.source_device_id = payload.source_device_id
        entry.last_error = None
        entry.updated_at = _utcnow()
        entry.downloaded_at = _utcnow() if payload.status == "completed" else None

    await db.commit()
    return DownloadBatchResponse(
        comic=build_comic_ref(comic),
        requested_total=len(filtered),
        created_total=created_total,
        updated_total=updated_total,
        chapter_numbers=sorted(requested_chapter_numbers, reverse=True),
    )


async def get_library_summary(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> LibrarySummaryResponse:
    """Ringkasan utama library untuk home/library screen."""
    bookmark_count = (
        await db.execute(
            select(func.count(UserBookmark.id)).where(UserBookmark.user_id == user_id)
        )
    ).scalar_one()
    collection_count = (
        await db.execute(
            select(func.count(UserCollection.id)).where(UserCollection.user_id == user_id)
        )
    ).scalar_one()
    favorite_scene_count = (
        await db.execute(
            select(func.count(UserFavoriteScene.id)).where(UserFavoriteScene.user_id == user_id)
        )
    ).scalar_one()
    history_count = (
        await db.execute(
            select(func.count(UserHistoryEntry.id)).where(UserHistoryEntry.user_id == user_id)
        )
    ).scalar_one()
    download_count = (
        await db.execute(
            select(func.count(UserDownloadEntry.id)).where(UserDownloadEntry.user_id == user_id)
        )
    ).scalar_one()
    progress_count = (
        await db.execute(
            select(func.count(UserProgress.id)).where(UserProgress.user_id == user_id)
        )
    ).scalar_one()

    continue_reading = await list_continue_reading(db, user_id, limit=10)
    history = await list_history(db, user_id, limit=10)
    collections = await list_collections(db, user_id)
    preferences = await db.get(ReaderPreference, user_id)

    return LibrarySummaryResponse(
        counts=LibrarySummaryCounts(
            bookmarks=bookmark_count or 0,
            collections=collection_count or 0,
            favorite_scenes=favorite_scene_count or 0,
            history=history_count or 0,
            downloads=download_count or 0,
            continue_reading=progress_count or 0,
        ),
        continue_reading=[build_progress_response(item) for item in continue_reading],
        recent_history=[build_history_response(item) for item in history],
        collections=[build_collection_summary_response(item) for item in collections],
        reader_preferences=(
            build_reader_preferences_response(preferences)
            if preferences is not None
            else None
        ),
    )


async def get_library_state_for_comic(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
) -> LibraryComicStateResponse:
    """State terpadu satu komik untuk CTA detail page."""
    comic = await resolve_comic_or_raise(db, source_name, comic_slug)

    bookmark_result = await db.execute(
        select(UserBookmark).where(
            UserBookmark.user_id == user_id,
            UserBookmark.comic_id == comic.id,
        )
    )
    bookmark = bookmark_result.scalars().first()

    progress_result = await db.execute(
        select(UserProgress).where(
            UserProgress.user_id == user_id,
            UserProgress.comic_id == comic.id,
        )
    )
    progress = progress_result.scalars().first()

    history_result = await db.execute(
        select(UserHistoryEntry).where(
            UserHistoryEntry.user_id == user_id,
            UserHistoryEntry.comic_id == comic.id,
        )
    )
    history = history_result.scalars().first()

    collection_rows = await db.execute(
        select(UserCollection)
        .join(UserCollectionComic, UserCollectionComic.collection_id == UserCollection.id)
        .options(selectinload(UserCollection.items).selectinload(UserCollectionComic.comic))
        .where(
            UserCollection.user_id == user_id,
            UserCollectionComic.comic_id == comic.id,
        )
        .order_by(UserCollection.updated_at.desc())
    )
    collections = collection_rows.scalars().unique().all()

    favorite_scene_count = (
        await db.execute(
            select(func.count(UserFavoriteScene.id)).where(
                UserFavoriteScene.user_id == user_id,
                UserFavoriteScene.comic_id == comic.id,
            )
        )
    ).scalar_one()

    download_rows = await db.execute(
        select(UserDownloadEntry)
        .where(
            UserDownloadEntry.user_id == user_id,
            UserDownloadEntry.comic_id == comic.id,
        )
        .order_by(UserDownloadEntry.updated_at.desc(), UserDownloadEntry.id.desc())
    )
    download_entries = download_rows.scalars().all()
    download_status_counts = dict(Counter(entry.status for entry in download_entries))

    return LibraryComicStateResponse(
        comic=build_comic_ref(comic),
        bookmarked=bookmark is not None,
        collections=[build_collection_summary_response(item) for item in collections],
        progress=build_progress_response(progress) if progress is not None else None,
        history=build_history_response(history) if history is not None else None,
        favorite_scene_count=favorite_scene_count or 0,
        download_status_counts=download_status_counts,
        download_entries=[build_download_response(entry) for entry in download_entries],
    )


async def import_library_snapshot(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: LibrarySyncImportRequest,
) -> LibrarySyncImportResponse:
    """Batch import snapshot local -> cloud untuk migrasi pertama."""
    response = LibrarySyncImportResponse()

    for bookmark_payload in payload.bookmarks:
        await set_bookmark(
            db,
            user_id,
            bookmark_payload.source_name,
            bookmark_payload.comic_slug,
        )
        response.bookmarks_upserted += 1

    for collection_payload in payload.collections:
        collection = await get_or_create_collection_by_name(
            db,
            user_id,
            collection_payload.name,
        )
        response.collections_upserted += 1
        for comic_payload in collection_payload.comics:
            before_count = len(collection.items)
            collection = await add_comic_to_collection(
                db,
                user_id,
                collection.id,
                comic_payload.source_name,
                comic_payload.comic_slug,
            )
            after_count = len(collection.items)
            if after_count > before_count:
                response.collection_items_upserted += 1

    for progress_payload in payload.progress:
        await upsert_progress(db, user_id, progress_payload)
        response.progress_upserted += 1

    for scene_payload in payload.favorite_scenes:
        await upsert_favorite_scene(db, user_id, scene_payload)
        response.favorite_scenes_upserted += 1

    for download_payload in payload.downloads:
        await upsert_download_entry(db, user_id, download_payload)
        response.downloads_upserted += 1

    if payload.reader_preferences is not None:
        await update_reader_preferences(db, user_id, payload.reader_preferences)
        response.reader_preferences_updated = True

    return response
