"""
Service layer untuk domain user library dan progress sync.
"""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import UTC, datetime

from sqlalchemy import (
    Float,
    String,
    and_,
    case,
    column,
    delete,
    exists,
    func,
    literal,
    or_,
    select,
    update,
    union_all,
    values,
)
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import defaultload, noload, selectinload

from app.models import (
    Chapter,
    Comic,
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
from app.schemas.library import (
    BookmarkResponse,
    BookmarkLinkBatchRequest,
    BookmarkLinkBatchResponse,
    BookmarkLinkCandidate,
    BookmarkLinkCandidateGroup,
    BookmarkLinkCandidatePage,
    BookmarkLinkCompletionSyncResponse,
    CompletedChapterBatchImportRequest,
    CompletedChapterBatchResponse,
    CompletedChapterImportRequest,
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
    ReadingTimeResponse,
    ReaderPreferenceResponse,
    ReaderPreferenceUpdateRequest,
)
from app.services.image_service import build_proxy_image_url

CHAPTER_NUMBER_TOLERANCE = 0.0001
BULK_DML_CHUNK_SIZE = 500


def _utcnow() -> datetime:
    return datetime.now(UTC)


def normalize_collection_name(name: str) -> str:
    """Normalisasi nama koleksi untuk uniqueness case-insensitive."""
    return " ".join(name.split()).strip().casefold()


def build_comic_ref(
    comic: Comic,
    base_url: str | None = None,
    has_new_chapter: bool = False,
    status_override: str | None = None,
) -> LibraryComicRef:
    """Bangun snapshot ringan komik untuk response library."""
    return LibraryComicRef(
        comic_id=comic.id,
        source_name=comic.source_name,
        slug=comic.slug,
        title=comic.title,
        cover_image_url=build_proxy_image_url(
            comic.cover_image_url,
            base_url=base_url,
        ),
        author=comic.author,
        status=status_override if status_override is not None else comic.status,
        type=comic.type,
        rating=comic.rating,
        total_view=comic.total_view,
        has_new_chapter=has_new_chapter,
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
        mark_read_on_complete=preference.mark_read_on_complete,
        default_binge_mode=preference.default_binge_mode,
        auto_scroll_enabled=preference.auto_scroll_enabled,
        auto_scroll_speed=preference.auto_scroll_speed,
        updated_at=preference.updated_at,
    )


def build_reading_time_response(stat: UserReadingStat) -> ReadingTimeResponse:
    """Serialisasi akumulasi waktu baca user."""
    return ReadingTimeResponse(
        total_reading_seconds=stat.total_reading_seconds,
        updated_at=stat.updated_at,
    )


def build_progress_response(
    progress: UserProgress,
    base_url: str | None = None,
) -> ProgressResponse:
    """Serialisasi progress ORM -> schema."""
    return ProgressResponse(
        id=progress.id,
        comic=build_comic_ref(progress.comic, base_url=base_url),
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


def build_history_response(
    entry: UserHistoryEntry,
    base_url: str | None = None,
) -> HistoryItemResponse:
    """Serialisasi history ORM -> schema."""
    return HistoryItemResponse(
        id=entry.id,
        comic=build_comic_ref(entry.comic, base_url=base_url),
        chapter=build_chapter_ref(entry.chapter),
        reading_mode=entry.reading_mode,
        scroll_offset=entry.scroll_offset,
        page_index=entry.page_index,
        last_read_page_item_index=entry.last_read_page_item_index,
        total_page_items=entry.total_page_items,
        last_read_at=entry.last_read_at,
        updated_at=entry.updated_at,
    )


def build_history_projection_response(
    row,
    base_url: str | None = None,
) -> HistoryItemResponse:
    """Serialisasi row projection history tanpa memuat blob chapter penuh."""
    return HistoryItemResponse(
        id=row.id,
        comic=LibraryComicRef(
            comic_id=row.comic_id,
            source_name=row.source_name,
            slug=row.comic_slug,
            title=row.comic_title,
            cover_image_url=build_proxy_image_url(
                row.cover_image_url,
                base_url=base_url,
            ),
            author=row.author,
            status=row.status,
            type=row.type,
            rating=row.rating,
            total_view=row.total_view,
        ),
        chapter=LibraryChapterRef(
            chapter_id=row.chapter_id,
            chapter_number=row.chapter_number,
            title=row.chapter_title,
            release_date=row.release_date,
        ),
        reading_mode=row.reading_mode,
        scroll_offset=row.scroll_offset,
        page_index=row.page_index,
        last_read_page_item_index=row.last_read_page_item_index,
        total_page_items=row.total_page_items,
        is_completed=row.is_completed,
        last_read_at=row.last_read_at,
        updated_at=row.updated_at,
    )


def build_bookmark_response(
    bookmark: UserBookmark,
    base_url: str | None = None,
    has_new_chapter: bool = False,
) -> BookmarkResponse:
    """Serialisasi bookmark ORM -> schema."""
    return BookmarkResponse(
        id=bookmark.id,
        comic=build_comic_ref(
            bookmark.comic,
            base_url=base_url,
            has_new_chapter=has_new_chapter,
            status_override=bookmark.status_override,
        ),
        linked_comics=[
            build_comic_ref(link.comic, base_url=base_url)
            for link in bookmark.__dict__.get("links", ())
        ],
        created_at=bookmark.created_at,
        updated_at=bookmark.updated_at,
    )


def build_collection_summary_response(collection) -> CollectionSummaryResponse:
    """Ringkasan collection untuk list dan picker."""
    return CollectionSummaryResponse(
        id=collection.id,
        name=collection.name,
        total_items=collection.total_items,
        created_at=collection.created_at,
        updated_at=collection.updated_at,
    )


def build_collection_response(
    collection: UserCollection,
    base_url: str | None = None,
) -> CollectionResponse:
    """Detail collection dengan daftar komik."""
    items = [build_comic_ref(item.comic, base_url=base_url) for item in collection.items]
    return CollectionResponse(
        id=collection.id,
        name=collection.name,
        total_items=len(items),
        created_at=collection.created_at,
        updated_at=collection.updated_at,
        items=items,
    )


def build_favorite_scene_response(
    scene: UserFavoriteScene,
    base_url: str | None = None,
) -> FavoriteSceneResponse:
    """Serialisasi favorite scene ORM -> schema."""
    return FavoriteSceneResponse(
        id=scene.id,
        comic=build_comic_ref(scene.comic, base_url=base_url),
        chapter=build_chapter_ref(scene.chapter),
        page_item_index=scene.page_item_index,
        image_url=build_proxy_image_url(
            scene.image_url,
            base_url=base_url,
        ),
        note=scene.note,
        created_at=scene.created_at,
        updated_at=scene.updated_at,
    )


def build_download_response(
    entry: UserDownloadEntry,
    base_url: str | None = None,
) -> DownloadEntryResponse:
    """Serialisasi download intent ORM -> schema."""
    return DownloadEntryResponse(
        id=entry.id,
        comic=build_comic_ref(entry.comic, base_url=base_url),
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
    preference.mark_read_on_complete = payload.mark_read_on_complete
    preference.default_binge_mode = payload.default_binge_mode
    preference.auto_scroll_enabled = payload.auto_scroll_enabled
    preference.auto_scroll_speed = payload.auto_scroll_speed
    preference.updated_at = _utcnow()

    await db.commit()
    await db.refresh(preference)
    return preference


async def get_or_create_reading_stat(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> UserReadingStat:
    """Ambil total waktu baca user, buat row default jika belum ada."""
    stat = await db.get(UserReadingStat, user_id)
    if stat is None:
        stat = UserReadingStat(
            user_id=user_id,
            total_reading_seconds=0,
            updated_at=_utcnow(),
        )
        db.add(stat)
        await db.commit()
        await db.refresh(stat)
    return stat


async def add_reading_time_delta(
    db: AsyncSession,
    user_id: uuid.UUID,
    delta_seconds: int,
) -> UserReadingStat:
    """Tambah durasi baca secara atomic agar aman untuk multi-device."""
    delta = max(0, int(delta_seconds))
    if delta == 0:
        return await get_or_create_reading_stat(db, user_id)

    now = _utcnow()
    statement = (
        insert(UserReadingStat)
        .values(
            user_id=user_id,
            total_reading_seconds=delta,
            updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=[UserReadingStat.user_id],
            set_={
                "total_reading_seconds": UserReadingStat.total_reading_seconds
                + delta,
                "updated_at": now,
            },
        )
        .returning(UserReadingStat)
    )
    result = await db.execute(statement)
    await db.commit()
    return result.scalars().first()


async def list_bookmarks(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    page_size: int = 20,
    offset: int = 0,
    comic_type: str | None = None,
    comic_status: str | None = None,
    sort: str | None = None,
) -> list[tuple[UserBookmark, bool]]:
    """List bookmark user dengan filter tipe/status dan urutan terpilih."""
    progress_subq = (
        select(func.max(Chapter.chapter_number))
        .select_from(UserProgress)
        .join(Chapter, Chapter.id == UserProgress.chapter_id)
        .where(
            UserProgress.user_id == user_id,
            UserProgress.comic_id == UserBookmark.comic_id
        )
        .correlate(UserBookmark)
        .scalar_subquery()
    )

    completed_subq = (
        select(func.max(Chapter.chapter_number))
        .select_from(UserCompletedChapter)
        .join(Chapter, Chapter.id == UserCompletedChapter.chapter_id)
        .where(
            UserCompletedChapter.user_id == user_id,
            UserCompletedChapter.comic_id == UserBookmark.comic_id
        )
        .correlate(UserBookmark)
        .scalar_subquery()
    )

    has_new_chapter_expr = exists(
        select(1)
        .select_from(Chapter)
        .where(
            Chapter.comic_id == UserBookmark.comic_id,
            Chapter.chapter_number > func.greatest(
                func.coalesce(progress_subq, -1.0),
                func.coalesce(completed_subq, -1.0)
            )
        )
        .correlate(UserBookmark)
    ).label("has_new_chapter")

    effective_status = func.lower(
        func.trim(func.coalesce(UserBookmark.status_override, Comic.status))
    )
    statement = (
        select(UserBookmark, has_new_chapter_expr)
        .join(Comic, Comic.id == UserBookmark.comic_id)
        .options(
            defaultload(UserBookmark.comic).noload(Comic.genres),
            selectinload(UserBookmark.links).selectinload(
                UserBookmarkLink.comic
            ).noload(Comic.genres),
        )
        .where(UserBookmark.user_id == user_id)
    )

    comic_types = [
        value.strip().lower()
        for value in (comic_type or "").split(",")
        if value.strip()
    ]
    comic_statuses = [
        ("completed" if value.strip().lower() == "selesai" else value.strip().lower())
        for value in (comic_status or "").split(",")
        if value.strip()
    ]
    if comic_types:
        statement = statement.where(func.lower(func.trim(Comic.type)).in_(comic_types))
    if comic_statuses:
        statement = statement.where(effective_status.in_(comic_statuses))

    if sort == "az":
        order_by = (func.lower(Comic.title).asc(), UserBookmark.id.desc())
    elif sort == "za":
        order_by = (func.lower(Comic.title).desc(), UserBookmark.id.desc())
    elif sort == "latest":
        # "Update terbaru" is a new-chapter-only view.  Keep the same
        # primary-source has_new_chapter expression used in the response so
        # pagination never includes bookmarks without the New badge.
        statement = statement.where(has_new_chapter_expr)
        order_by = (
            has_new_chapter_expr.desc(),
            UserBookmark.created_at.desc(),
            UserBookmark.id.desc(),
        )
    else:
        order_by = (
            has_new_chapter_expr.desc(),
            UserBookmark.created_at.desc(),
            UserBookmark.id.desc(),
        )

    result = await db.execute(
        statement.order_by(*order_by).limit(page_size).offset(offset)
    )
    return list(result.all())


def _bookmark_match_score(primary: Comic, candidate: Comic):
    primary_title = primary.title.casefold()
    primary_aliases = (primary.alternative_titles or "").casefold()
    candidate_aliases = func.coalesce(candidate.alternative_titles, "")
    return func.greatest(
        func.similarity(candidate.title, primary_title),
        func.similarity(candidate_aliases, primary_title),
        func.similarity(candidate.title, primary_aliases),
    )


def _bookmark_link_candidate_statement(
    bookmark: UserBookmark,
    user_id: uuid.UUID,
    *,
    minimum_confidence: float,
):
    score = _bookmark_match_score(bookmark.comic, Comic)
    indexed_matches = [
        Comic.title.op("%")(bookmark.comic.title),
        Comic.alternative_titles.op("%")(bookmark.comic.title),
    ]
    if bookmark.comic.alternative_titles:
        indexed_matches.append(
            Comic.title.op("%")(bookmark.comic.alternative_titles)
        )

    bookmarked_ids = select(UserBookmark.comic_id).where(
        UserBookmark.user_id == user_id
    )
    linked_ids = select(UserBookmarkLink.comic_id).where(
        UserBookmarkLink.user_id == user_id
    )
    linked_sources = (
        select(Comic.source_name)
        .join(UserBookmarkLink, UserBookmarkLink.comic_id == Comic.id)
        .where(
            UserBookmarkLink.user_id == user_id,
            UserBookmarkLink.bookmark_id == bookmark.id,
        )
    )
    return (
        select(Comic, score.label("confidence"))
        .options(noload(Comic.genres))
        .where(
            Comic.source_name != bookmark.comic.source_name,
            Comic.source_name.not_in(linked_sources),
            Comic.id.not_in(bookmarked_ids),
            Comic.id.not_in(linked_ids),
            or_(*indexed_matches),
            score >= minimum_confidence,
        )
        .order_by(score.desc(), Comic.title)
        .limit(24)
    )


async def list_bookmark_link_candidates(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    base_url: str | None = None,
    minimum_confidence: float = 0.38,
    candidates_per_source: int = 2,
    page_size: int = 5,
    offset: int = 0,
    source_name: str | None = None,
    comic_slug: str | None = None,
) -> BookmarkLinkCandidatePage:
    """Cari kandidat source alternatif hanya saat diminta user."""
    scoped = source_name is not None and comic_slug is not None
    if scoped:
        result = await db.execute(
            select(UserBookmark)
            .join(UserBookmark.comic)
            .options(
                defaultload(UserBookmark.comic).noload(Comic.genres),
                selectinload(UserBookmark.links).selectinload(
                    UserBookmarkLink.comic
                ).noload(Comic.genres),
            )
            .where(
                UserBookmark.user_id == user_id,
                Comic.source_name == source_name,
                Comic.slug == comic_slug,
            )
            .limit(1)
        )
        bookmark = result.scalars().first()
        bookmarks = [bookmark] if bookmark is not None else []
    else:
        bookmarks_result = await list_bookmarks(
            db,
            user_id,
            page_size=page_size + 1,
            offset=offset,
        )
        bookmarks = [b for b, _ in bookmarks_result]
    if not bookmarks:
        return BookmarkLinkCandidatePage(
            next_offset=offset,
        )

    has_more = not scoped and len(bookmarks) > page_size
    scanned_bookmarks = bookmarks if scoped else bookmarks[:page_size]
    groups: list[BookmarkLinkCandidateGroup] = []

    for bookmark in scanned_bookmarks:
        result = await db.execute(
            _bookmark_link_candidate_statement(
                bookmark,
                user_id,
                minimum_confidence=minimum_confidence,
            )
        )
        per_source: dict[str, list[BookmarkLinkCandidate]] = {}
        for candidate, confidence in result.all():
            source_candidates = per_source.setdefault(
                candidate.source_name,
                [],
            )
            if len(source_candidates) >= candidates_per_source:
                continue
            source_candidates.append(
                BookmarkLinkCandidate(
                    comic=build_comic_ref(candidate, base_url=base_url),
                    confidence=max(0, min(1, float(confidence or 0))),
                )
            )
        candidates = [
            candidate
            for source_candidates in per_source.values()
            for candidate in source_candidates
        ]
        if candidates:
            groups.append(
                BookmarkLinkCandidateGroup(
                    bookmark=build_comic_ref(
                        bookmark.comic,
                        base_url=base_url,
                    ),
                    candidates=candidates,
                )
            )
    return BookmarkLinkCandidatePage(
        items=groups,
        scanned_total=len(scanned_bookmarks),
        next_offset=offset + len(scanned_bookmarks),
        has_more=has_more,
    )


async def set_bookmark_links(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: BookmarkLinkBatchRequest,
) -> BookmarkLinkBatchResponse:
    """Simpan relasi source secara set-based lalu jadwalkan completed sync."""
    if not payload.links:
        return BookmarkLinkBatchResponse()

    selector_keys = {
        _comic_selector_key(item.bookmark)
        for item in payload.links
    }
    selector_keys.update(
        _comic_selector_key(item.linked_comic)
        for item in payload.links
    )
    comic_ids = await _resolve_comic_selector_ids(db, selector_keys)

    bookmark_comic_ids = {
        comic_ids[_comic_selector_key(item.bookmark)]
        for item in payload.links
    }
    bookmark_result = await db.execute(
        select(UserBookmark.id, UserBookmark.comic_id).where(
            UserBookmark.user_id == user_id,
            UserBookmark.comic_id.in_(bookmark_comic_ids),
        )
    )
    bookmark_ids = {
        row.comic_id: row.id
        for row in bookmark_result.all()
    }
    missing_bookmark_ids = bookmark_comic_ids - bookmark_ids.keys()
    if missing_bookmark_ids:
        raise LookupError("Bookmark utama tidak ditemukan atau sudah dihapus.")

    linked_comic_ids = {
        comic_ids[_comic_selector_key(item.linked_comic)]
        for item in payload.links
    }
    direct_bookmark_result = await db.execute(
        select(UserBookmark.comic_id).where(
            UserBookmark.user_id == user_id,
            UserBookmark.comic_id.in_(linked_comic_ids),
        )
    )
    if direct_bookmark_result.scalars().first() is not None:
        raise ValueError(
            "Komik source tujuan sudah tersimpan sebagai bookmark langsung."
        )

    now = _utcnow()
    rows_by_linked_comic: dict[int, dict] = {}
    affected_pairs: dict[str, set[int]] = {}
    for item in payload.links:
        bookmark_comic_id = comic_ids[_comic_selector_key(item.bookmark)]
        linked_comic_id = comic_ids[_comic_selector_key(item.linked_comic)]
        if bookmark_comic_id == linked_comic_id:
            continue
        if item.bookmark.source_name == item.linked_comic.source_name:
            raise ValueError("Source utama dan source terhubung harus berbeda.")

        bookmark_id = bookmark_ids[bookmark_comic_id]
        affected_bookmark_ids = affected_pairs.setdefault(
            item.linked_comic.source_name,
            set(),
        )
        if bookmark_id in affected_bookmark_ids:
            raise ValueError(
                "Hanya satu komik dapat dipilih per source tujuan."
            )
        affected_bookmark_ids.add(bookmark_id)
        rows_by_linked_comic[linked_comic_id] = {
            "user_id": user_id,
            "bookmark_id": bookmark_id,
            "comic_id": linked_comic_id,
            "confidence": item.confidence,
            "updated_at": now,
        }

    for source_name, affected_bookmark_ids in affected_pairs.items():
        await db.execute(
            delete(UserBookmarkLink).where(
                UserBookmarkLink.user_id == user_id,
                UserBookmarkLink.bookmark_id.in_(affected_bookmark_ids),
                UserBookmarkLink.comic_id.in_(
                    select(Comic.id).where(
                        Comic.source_name == source_name
                    )
                ),
            )
        )

    for chunk in _chunked(list(rows_by_linked_comic.values())):
        statement = insert(UserBookmarkLink).values(chunk)
        await db.execute(
            statement.on_conflict_do_update(
                index_elements=[
                    UserBookmarkLink.user_id,
                    UserBookmarkLink.comic_id,
                ],
                set_={
                    "bookmark_id": statement.excluded.bookmark_id,
                    "confidence": statement.excluded.confidence,
                    "updated_at": statement.excluded.updated_at,
                },
            )
        )

    await db.commit()
    return BookmarkLinkBatchResponse(
        linked_total=len(rows_by_linked_comic),
        completion_sync_bookmark_ids=sorted(
            {
                row["bookmark_id"]
                for row in rows_by_linked_comic.values()
            }
        ),
    )


async def synchronize_completed_link_batch(
    db: AsyncSession,
    user_id: uuid.UUID,
    bookmark_ids: list[int],
) -> BookmarkLinkCompletionSyncResponse:
    """Sinkronkan completed untuk maksimal beberapa grup per transaksi."""
    owned_result = await db.execute(
        select(UserBookmark.id)
        .join(
            UserBookmarkLink,
            and_(
                UserBookmarkLink.bookmark_id == UserBookmark.id,
                UserBookmarkLink.user_id == user_id,
            ),
        )
        .where(
            UserBookmark.user_id == user_id,
            UserBookmark.id.in_(bookmark_ids),
        )
        .distinct()
    )
    owned_ids = sorted(set(owned_result.scalars().all()))
    if not owned_ids:
        return BookmarkLinkCompletionSyncResponse()

    completed_propagated = await _synchronize_existing_completed_for_links(
        db,
        user_id,
        bookmark_ids=owned_ids,
    )
    return BookmarkLinkCompletionSyncResponse(
        processed_groups=len(owned_ids),
        completed_propagated=completed_propagated,
    )


async def delete_bookmark_link(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
) -> bool:
    """Putuskan satu source alternatif tanpa menghapus bookmark utama."""
    comic = await get_comic_by_public_key(db, source_name, comic_slug)
    if comic is None:
        return False
    result = await db.execute(
        delete(UserBookmarkLink)
        .where(
            UserBookmarkLink.user_id == user_id,
            UserBookmarkLink.comic_id == comic.id,
        )
        .returning(UserBookmarkLink.id)
    )
    deleted_id = result.scalar_one_or_none()
    await db.commit()
    return deleted_id is not None


async def _upsert_completed_chapter_rows(
    db: AsyncSession,
    user_id: uuid.UUID,
    chapter_rows: list[tuple[int, int]],
    *,
    completed_at: datetime,
) -> int:
    unique_rows = {
        chapter_id: {
            "user_id": user_id,
            "comic_id": comic_id,
            "chapter_id": chapter_id,
            "completed_at": completed_at,
        }
        for chapter_id, comic_id in chapter_rows
    }
    await _bulk_upsert(
        db,
        UserCompletedChapter,
        list(unique_rows.values()),
        index_elements=[
            UserCompletedChapter.user_id,
            UserCompletedChapter.comic_id,
            UserCompletedChapter.chapter_id,
        ],
        update_columns=("completed_at",),
    )
    return len(unique_rows)


async def _bookmark_group_comic_ids(
    db: AsyncSession,
    user_id: uuid.UUID,
    comic_id: int,
) -> set[int]:
    bookmark_result = await db.execute(
        select(UserBookmark.id, UserBookmark.comic_id)
        .outerjoin(
            UserBookmarkLink,
            and_(
                UserBookmarkLink.bookmark_id == UserBookmark.id,
                UserBookmarkLink.user_id == user_id,
            ),
        )
        .where(
            UserBookmark.user_id == user_id,
            or_(
                UserBookmark.comic_id == comic_id,
                UserBookmarkLink.comic_id == comic_id,
            ),
        )
        .limit(1)
    )
    bookmark_row = bookmark_result.first()
    if bookmark_row is None:
        return set()

    linked_result = await db.execute(
        select(UserBookmarkLink.comic_id).where(
            UserBookmarkLink.user_id == user_id,
            UserBookmarkLink.bookmark_id == bookmark_row.id,
        )
    )
    return {
        bookmark_row.comic_id,
        *linked_result.scalars().all(),
    }


async def _group_chapters_for_number(
    db: AsyncSession,
    comic_ids: set[int],
    chapter_number: float,
) -> list[tuple[int, int]]:
    if not comic_ids:
        return []
    result = await db.execute(
        select(
            Chapter.id.label("chapter_id"),
            Chapter.comic_id.label("comic_id"),
        ).where(
            Chapter.comic_id.in_(comic_ids),
            Chapter.chapter_number
            >= chapter_number - CHAPTER_NUMBER_TOLERANCE,
            Chapter.chapter_number
            <= chapter_number + CHAPTER_NUMBER_TOLERANCE,
        )
    )
    return [(row.chapter_id, row.comic_id) for row in result.all()]


async def _synchronize_existing_completed_for_links(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    bookmark_ids: list[int] | None = None,
    commit: bool = True,
) -> int:
    """Samakan completed lama untuk semua grup dalam satu statement."""
    now = _utcnow()
    result = await db.execute(
        _completed_link_backfill_statement(
            user_id,
            completed_at=now,
            bookmark_ids=bookmark_ids,
        )
    )
    if commit:
        await db.commit()
    return int(result.scalar_one())


def _completed_link_backfill_statement(
    user_id: uuid.UUID,
    *,
    completed_at: datetime,
    bookmark_ids: list[int] | None = None,
):
    hub_members = (
        select(
            UserBookmark.id.label("group_id"),
            UserBookmark.comic_id.label("comic_id"),
        )
        .join(
            UserBookmarkLink,
            UserBookmarkLink.bookmark_id == UserBookmark.id,
        )
        .where(
            UserBookmark.user_id == user_id,
            UserBookmarkLink.user_id == user_id,
        )
    )
    spoke_members = select(
        UserBookmarkLink.bookmark_id.label("group_id"),
        UserBookmarkLink.comic_id.label("comic_id"),
    ).where(UserBookmarkLink.user_id == user_id)
    if bookmark_ids is not None:
        hub_members = hub_members.where(UserBookmark.id.in_(bookmark_ids))
        spoke_members = spoke_members.where(
            UserBookmarkLink.bookmark_id.in_(bookmark_ids)
        )
    group_members = hub_members.union(spoke_members).cte(
        "bookmark_group_members"
    )

    completed_numbers = (
        select(
            group_members.c.group_id,
            Chapter.chapter_number,
        )
        .join(Chapter, Chapter.comic_id == group_members.c.comic_id)
        .join(
            UserCompletedChapter,
            and_(
                UserCompletedChapter.chapter_id == Chapter.id,
                UserCompletedChapter.comic_id
                == group_members.c.comic_id,
                UserCompletedChapter.user_id == user_id,
            ),
        )
        .distinct()
        .cte("completed_numbers_by_group")
    )

    target_chapters = (
        select(
            literal(user_id).label("user_id"),
            Chapter.comic_id.label("comic_id"),
            Chapter.id.label("chapter_id"),
            literal(completed_at).label("completed_at"),
        )
        .select_from(group_members)
        .join(
            completed_numbers,
            completed_numbers.c.group_id == group_members.c.group_id,
        )
        .join(
            Chapter,
            and_(
                Chapter.comic_id == group_members.c.comic_id,
                Chapter.chapter_number
                >= completed_numbers.c.chapter_number
                - CHAPTER_NUMBER_TOLERANCE,
                Chapter.chapter_number
                <= completed_numbers.c.chapter_number
                + CHAPTER_NUMBER_TOLERANCE,
            ),
        )
        .distinct()
    )
    statement = insert(UserCompletedChapter).from_select(
        [
            UserCompletedChapter.user_id,
            UserCompletedChapter.comic_id,
            UserCompletedChapter.chapter_id,
            UserCompletedChapter.completed_at,
        ],
        target_chapters,
    )
    inserted = statement.on_conflict_do_nothing(
        index_elements=[
            UserCompletedChapter.user_id,
            UserCompletedChapter.comic_id,
            UserCompletedChapter.chapter_id,
        ]
    ).returning(literal(1).label("inserted")).cte("inserted_completed")
    return select(func.count()).select_from(inserted)


async def _exact_counterpart_chapters(
    db: AsyncSession,
    user_id: uuid.UUID,
    chapter: Chapter,
) -> list[tuple[int, int]]:
    """Cari chapter bernomor sama pada seluruh grup bookmark multi-source."""
    group_comic_ids = await _bookmark_group_comic_ids(
        db,
        user_id,
        chapter.comic_id,
    )
    group_comic_ids.discard(chapter.comic_id)
    return await _group_chapters_for_number(
        db,
        group_comic_ids,
        chapter.chapter_number,
    )


async def _propagate_completed_chapter(
    db: AsyncSession,
    user_id: uuid.UUID,
    chapter: Chapter,
    *,
    completed_at: datetime,
) -> int:
    counterparts = await _exact_counterpart_chapters(
        db,
        user_id,
        chapter,
    )
    return await _upsert_completed_chapter_rows(
        db,
        user_id,
        counterparts,
        completed_at=completed_at,
    )


def _chapter_total_images_expression():
    return case(
        (
            func.jsonb_typeof(Chapter.images) == "array",
            func.jsonb_array_length(Chapter.images),
        ),
        else_=0,
    )


def _comic_projection_columns():
    return (
        Comic.id.label("comic_id"),
        Comic.source_name.label("source_name"),
        Comic.slug.label("comic_slug"),
        Comic.title.label("comic_title"),
        Comic.cover_image_url.label("cover_image_url"),
        Comic.author.label("author"),
        Comic.status.label("comic_status"),
        Comic.type.label("comic_type"),
        Comic.rating.label("rating"),
        Comic.total_view.label("total_view"),
    )


def _chapter_projection_columns():
    return (
        Chapter.id.label("chapter_id"),
        Chapter.chapter_number.label("chapter_number"),
        Chapter.title.label("chapter_title"),
        Chapter.release_date.label("release_date"),
        _chapter_total_images_expression().label("total_images"),
    )


def _build_comic_ref_from_projection(row, base_url: str | None = None) -> LibraryComicRef:
    return LibraryComicRef(
        comic_id=row.comic_id,
        source_name=row.source_name,
        slug=row.comic_slug,
        title=row.comic_title,
        cover_image_url=build_proxy_image_url(row.cover_image_url, base_url=base_url),
        author=row.author,
        status=row.comic_status,
        type=row.comic_type,
        rating=row.rating,
        total_view=row.total_view,
    )


def _build_chapter_ref_from_projection(row) -> LibraryChapterRef:
    return LibraryChapterRef(
        chapter_id=row.chapter_id,
        chapter_number=row.chapter_number,
        title=row.chapter_title,
        release_date=row.release_date,
        total_images=row.total_images,
    )


def build_progress_projection_response(
    row,
    base_url: str | None = None,
) -> ProgressResponse:
    return ProgressResponse(
        id=row.id,
        comic=_build_comic_ref_from_projection(row, base_url=base_url),
        chapter=_build_chapter_ref_from_projection(row),
        reading_mode=row.reading_mode,
        scroll_offset=row.scroll_offset,
        page_index=row.page_index,
        last_read_page_item_index=row.last_read_page_item_index,
        total_page_items=row.total_page_items,
        is_completed=row.is_completed,
        last_read_at=row.last_read_at,
        updated_at=row.updated_at,
    )


def build_download_projection_response(
    row,
    base_url: str | None = None,
) -> DownloadEntryResponse:
    return DownloadEntryResponse(
        id=row.id,
        comic=_build_comic_ref_from_projection(row, base_url=base_url),
        chapter=_build_chapter_ref_from_projection(row),
        status=row.download_status,
        source_device_id=row.source_device_id,
        last_error=row.last_error,
        requested_at=row.requested_at,
        downloaded_at=row.downloaded_at,
        updated_at=row.updated_at,
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


async def set_bookmark_status(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
    status: str,
    *,
    global_scope: bool = False,
) -> None:
    """Set status bookmark personal, atau status komik global untuk admin."""
    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    bookmark = (
        await db.execute(
            select(UserBookmark)
            .options(selectinload(UserBookmark.links).selectinload(UserBookmarkLink.comic))
            .where(
                UserBookmark.user_id == user_id,
                UserBookmark.comic_id == comic.id,
            )
        )
    ).scalars().first()
    if bookmark is None:
        raise LookupError("Bookmark tidak ditemukan.")

    if global_scope:
        # A global admin status follows the complete multi-source bookmark group.
        group_comic_ids = {
            comic.id,
            *(link.comic_id for link in bookmark.links),
        }
        await db.execute(
            update(Comic)
            .where(Comic.id.in_(group_comic_ids))
            .values(status=status, updated_at=_utcnow())
        )
        await db.execute(
            update(UserBookmark)
            .where(UserBookmark.comic_id.in_(group_comic_ids))
            .values(status_override=None, updated_at=_utcnow())
        )
        comic.status = status
        for link in bookmark.links:
            link.comic.status = status
        bookmark.status_override = None
    else:
        bookmark.status_override = status
    bookmark.updated_at = _utcnow()
    await db.commit()


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


async def get_collection_detail(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
) -> UserCollection | None:
    """Load detail satu collection beserta item secara eksplisit."""
    return await _load_collection(db, user_id, collection_id)


def _collection_summary_statement(
    user_id: uuid.UUID,
    comic_id: int | None = None,
):
    statement = (
        select(
            UserCollection.id.label("id"),
            UserCollection.name.label("name"),
            UserCollection.created_at.label("created_at"),
            UserCollection.updated_at.label("updated_at"),
            func.count(UserCollectionComic.id).label("total_items"),
        )
        .outerjoin(
            UserCollectionComic,
            UserCollectionComic.collection_id == UserCollection.id,
        )
        .where(UserCollection.user_id == user_id)
        .group_by(
            UserCollection.id,
            UserCollection.name,
            UserCollection.created_at,
            UserCollection.updated_at,
        )
        .order_by(UserCollection.updated_at.desc(), UserCollection.id.desc())
    )
    if comic_id is not None:
        membership_comics = UserCollectionComic.__table__.alias("membership_comics")
        membership = (
            select(membership_comics.c.id)
            .where(
                membership_comics.c.collection_id == UserCollection.id,
                membership_comics.c.comic_id == comic_id,
            )
            .exists()
        )
        statement = statement.where(membership)
    return statement


async def list_collection_summaries(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    comic_id: int | None = None,
):
    """List collection summary dengan aggregate count tanpa load item."""
    result = await db.execute(
        _collection_summary_statement(user_id, comic_id=comic_id)
    )
    return result.all()


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
) -> None:
    """Tambahkan komik ke collection jika belum ada."""
    collection_exists = (
        await db.execute(
            select(UserCollection.id).where(
                UserCollection.user_id == user_id,
                UserCollection.id == collection_id,
            )
        )
    ).scalars().first()
    if collection_exists is None:
        raise LookupError("Collection tidak ditemukan.")

    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    inserted_id = (
        await db.execute(
            insert(UserCollectionComic)
            .values(collection_id=collection_id, comic_id=comic.id)
            .on_conflict_do_nothing(
                index_elements=[
                    UserCollectionComic.collection_id,
                    UserCollectionComic.comic_id,
                ]
            )
            .returning(UserCollectionComic.id)
        )
    ).scalar_one_or_none()
    if inserted_id is not None:
        await db.execute(
            update(UserCollection)
            .where(UserCollection.id == collection_id)
            .values(updated_at=_utcnow())
        )
        await db.commit()


async def remove_comic_from_collection(
    db: AsyncSession,
    user_id: uuid.UUID,
    collection_id: int,
    source_name: str,
    comic_slug: str,
) -> None:
    """Hapus komik dari collection bila ada."""
    collection_exists = (
        await db.execute(
            select(UserCollection.id).where(
                UserCollection.user_id == user_id,
                UserCollection.id == collection_id,
            )
        )
    ).scalars().first()
    if collection_exists is None:
        raise LookupError("Collection tidak ditemukan.")

    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    deleted_id = (
        await db.execute(
            delete(UserCollectionComic)
            .where(
                UserCollectionComic.collection_id == collection_id,
                UserCollectionComic.comic_id == comic.id,
            )
            .returning(UserCollectionComic.id)
        )
    ).scalar_one_or_none()
    if deleted_id is not None:
        await db.execute(
            update(UserCollection)
            .where(UserCollection.id == collection_id)
            .values(updated_at=_utcnow())
        )
        await db.commit()


async def set_comic_collections(
    db: AsyncSession,
    user_id: uuid.UUID,
    source_name: str,
    comic_slug: str,
    selected_collection_ids: set[int],
) -> None:
    """Set membership koleksi komik dengan bulk write dalam satu transaksi."""
    comic = await resolve_comic_or_raise(db, source_name, comic_slug)
    selected_ids = set(selected_collection_ids)
    if selected_ids:
        owned_ids = set(
            (
                await db.execute(
                    select(UserCollection.id).where(
                        UserCollection.user_id == user_id,
                        UserCollection.id.in_(selected_ids),
                    )
                )
            ).scalars().all()
        )
        if owned_ids != selected_ids:
            raise LookupError("Satu atau lebih collection tidak ditemukan.")

    current_ids = set(
        (
            await db.execute(
                select(UserCollectionComic.collection_id)
                .join(
                    UserCollection,
                    UserCollection.id == UserCollectionComic.collection_id,
                )
                .where(
                    UserCollection.user_id == user_id,
                    UserCollectionComic.comic_id == comic.id,
                )
            )
        ).scalars().all()
    )
    added_ids = selected_ids.difference(current_ids)
    removed_ids = current_ids.difference(selected_ids)
    changed_ids = added_ids | removed_ids
    if not changed_ids:
        return

    if added_ids:
        await db.execute(
            insert(UserCollectionComic)
            .values(
                [
                    {"collection_id": collection_id, "comic_id": comic.id}
                    for collection_id in added_ids
                ]
            )
            .on_conflict_do_nothing(
                index_elements=[
                    UserCollectionComic.collection_id,
                    UserCollectionComic.comic_id,
                ]
            )
        )
    if removed_ids:
        await db.execute(
            delete(UserCollectionComic).where(
                UserCollectionComic.collection_id.in_(removed_ids),
                UserCollectionComic.comic_id == comic.id,
            )
        )
    await db.execute(
        update(UserCollection)
        .where(
            UserCollection.user_id == user_id,
            UserCollection.id.in_(changed_ids),
        )
        .values(updated_at=_utcnow())
    )
    await db.commit()


async def upsert_history_from_progress(
    db: AsyncSession,
    user_id: uuid.UUID,
    chapter: Chapter,
    payload: ProgressUpsertRequest,
) -> UserHistoryEntry:
    """Sinkronkan history per chapter berdasarkan progress terbaru."""
    result = await db.execute(
        select(UserHistoryEntry).where(
            UserHistoryEntry.user_id == user_id,
            UserHistoryEntry.chapter_id == chapter.id,
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

    history_entry.comic_id = chapter.comic_id
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

    if payload.is_completed:
        completed_statement = (
            insert(UserCompletedChapter)
            .values(
                user_id=user_id,
                comic_id=chapter.comic_id,
                chapter_id=chapter.id,
                completed_at=progress.last_read_at,
            )
            .on_conflict_do_update(
                index_elements=[
                    UserCompletedChapter.user_id,
                    UserCompletedChapter.comic_id,
                    UserCompletedChapter.chapter_id,
                ],
                set_={"completed_at": progress.last_read_at},
            )
        )
        await db.execute(completed_statement)
        await _propagate_completed_chapter(
            db,
            user_id,
            chapter,
            completed_at=progress.last_read_at,
        )

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


async def mark_chapter_completed(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: CompletedChapterImportRequest,
) -> None:
    """Tandai chapter selesai tanpa mengubah posisi continue reading."""
    chapter = await resolve_chapter_or_raise(
        db,
        payload.source_name,
        payload.comic_slug,
        payload.chapter_number,
    )
    now = _utcnow()
    completed_statement = (
        insert(UserCompletedChapter)
        .values(
            user_id=user_id,
            comic_id=chapter.comic_id,
            chapter_id=chapter.id,
            completed_at=now,
        )
        .on_conflict_do_update(
            index_elements=[
                UserCompletedChapter.user_id,
                UserCompletedChapter.comic_id,
                UserCompletedChapter.chapter_id,
            ],
            set_={"completed_at": now},
        )
    )
    await db.execute(completed_statement)
    await _propagate_completed_chapter(
        db,
        user_id,
        chapter,
        completed_at=now,
    )
    await db.commit()


async def mark_completed_chapter_batch(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: CompletedChapterBatchImportRequest,
) -> CompletedChapterBatchResponse:
    """Upsert completed chapter dan propagation linked source secara set-based."""
    selector_keys = {
        _chapter_selector_key(item)
        for item in payload.chapters
    }
    if not selector_keys:
        return CompletedChapterBatchResponse()

    resolved_chapters = await _resolve_chapter_selector_ids(db, selector_keys)
    completed_at = _utcnow()
    chapter_rows = list(resolved_chapters.values())
    completed_synced = await _upsert_completed_chapter_rows(
        db,
        user_id,
        chapter_rows,
        completed_at=completed_at,
    )

    comic_ids = {comic_id for _, comic_id in chapter_rows}
    bookmark_result = await db.execute(
        select(UserBookmark.id)
        .outerjoin(
            UserBookmarkLink,
            and_(
                UserBookmarkLink.bookmark_id == UserBookmark.id,
                UserBookmarkLink.user_id == user_id,
            ),
        )
        .where(
            UserBookmark.user_id == user_id,
            or_(
                UserBookmark.comic_id.in_(comic_ids),
                UserBookmarkLink.comic_id.in_(comic_ids),
            ),
        )
        .distinct()
    )
    bookmark_ids = sorted(set(bookmark_result.scalars().all()))
    completed_propagated = 0
    if bookmark_ids:
        completed_propagated = await _synchronize_existing_completed_for_links(
            db,
            user_id,
            bookmark_ids=bookmark_ids,
            commit=False,
        )

    await db.commit()
    return CompletedChapterBatchResponse(
        completed_synced=completed_synced,
        completed_propagated=completed_propagated,
    )


def _progress_projection_statement(user_id: uuid.UUID):
    return (
        select(
            UserProgress.id.label("id"),
            UserProgress.reading_mode.label("reading_mode"),
            UserProgress.scroll_offset.label("scroll_offset"),
            UserProgress.page_index.label("page_index"),
            UserProgress.last_read_page_item_index.label("last_read_page_item_index"),
            UserProgress.total_page_items.label("total_page_items"),
            UserProgress.is_completed.label("is_completed"),
            UserProgress.last_read_at.label("last_read_at"),
            UserProgress.updated_at.label("updated_at"),
            *_comic_projection_columns(),
            *_chapter_projection_columns(),
        )
        .join(Comic, Comic.id == UserProgress.comic_id)
        .join(Chapter, Chapter.id == UserProgress.chapter_id)
        .where(UserProgress.user_id == user_id)
    )


async def list_continue_reading_responses(
    db: AsyncSession,
    user_id: uuid.UUID,
    page_size: int = 20,
    offset: int = 0,
    base_url: str | None = None,
) -> list[ProgressResponse]:
    """List continue reading dengan projection ringan tanpa JSONB images."""
    result = await db.execute(
        _progress_projection_statement(user_id)
        .order_by(UserProgress.last_read_at.desc(), UserProgress.id.desc())
        .offset(offset)
        .limit(page_size)
    )
    return [
        build_progress_projection_response(row, base_url=base_url)
        for row in result.all()
    ]


async def list_continue_reading(
    db: AsyncSession,
    user_id: uuid.UUID,
    page_size: int = 20,
    offset: int = 0,
) -> list[UserProgress]:
    """List continue reading terbaru."""
    result = await db.execute(
        select(UserProgress)
        .where(UserProgress.user_id == user_id)
        .order_by(UserProgress.last_read_at.desc(), UserProgress.id.desc())
        .offset(offset)
        .limit(page_size)
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
    *,
    page_size: int = 50,
    offset: int = 0,
) -> list[UserHistoryEntry]:
    """List history terbaru."""
    result = await db.execute(
        select(UserHistoryEntry)
        .where(UserHistoryEntry.user_id == user_id)
        .order_by(UserHistoryEntry.last_read_at.desc(), UserHistoryEntry.id.desc())
        .offset(offset)
        .limit(page_size)
    )
    return result.scalars().all()


async def list_history_responses(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    page_size: int = 20,
    offset: int = 0,
    base_url: str | None = None,
    comic_id: int | None = None,
) -> list[HistoryItemResponse]:
    """List history terbaru memakai projection ringan untuk UI list."""
    is_completed = (
        select(UserCompletedChapter.id)
        .where(
            UserCompletedChapter.user_id == UserHistoryEntry.user_id,
            UserCompletedChapter.chapter_id == UserHistoryEntry.chapter_id,
        )
        .exists()
    )
    statement = (
        select(
            UserHistoryEntry.id.label("id"),
            UserHistoryEntry.reading_mode.label("reading_mode"),
            UserHistoryEntry.scroll_offset.label("scroll_offset"),
            UserHistoryEntry.page_index.label("page_index"),
            UserHistoryEntry.last_read_page_item_index.label(
                "last_read_page_item_index"
            ),
            UserHistoryEntry.total_page_items.label("total_page_items"),
            UserHistoryEntry.last_read_at.label("last_read_at"),
            UserHistoryEntry.updated_at.label("updated_at"),
            Comic.id.label("comic_id"),
            Comic.source_name.label("source_name"),
            Comic.slug.label("comic_slug"),
            Comic.title.label("comic_title"),
            Comic.cover_image_url.label("cover_image_url"),
            Comic.author.label("author"),
            Comic.status.label("status"),
            Comic.type.label("type"),
            Comic.rating.label("rating"),
            Comic.total_view.label("total_view"),
            Chapter.id.label("chapter_id"),
            Chapter.chapter_number.label("chapter_number"),
            Chapter.title.label("chapter_title"),
            Chapter.release_date.label("release_date"),
            is_completed.label("is_completed"),
        )
        .join(Comic, Comic.id == UserHistoryEntry.comic_id)
        .join(Chapter, Chapter.id == UserHistoryEntry.chapter_id)
        .where(UserHistoryEntry.user_id == user_id)
        .order_by(UserHistoryEntry.last_read_at.desc(), UserHistoryEntry.id.desc())
        .offset(offset)
        .limit(page_size)
    )
    if comic_id is not None:
        statement = statement.where(UserHistoryEntry.comic_id == comic_id)
    result = await db.execute(statement)
    return [
        build_history_projection_response(row, base_url=base_url)
        for row in result.all()
    ]


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


def _download_projection_statement(user_id: uuid.UUID):
    return (
        select(
            UserDownloadEntry.id.label("id"),
            UserDownloadEntry.status.label("download_status"),
            UserDownloadEntry.source_device_id.label("source_device_id"),
            UserDownloadEntry.last_error.label("last_error"),
            UserDownloadEntry.requested_at.label("requested_at"),
            UserDownloadEntry.downloaded_at.label("downloaded_at"),
            UserDownloadEntry.updated_at.label("updated_at"),
            *_comic_projection_columns(),
            *_chapter_projection_columns(),
        )
        .join(Comic, Comic.id == UserDownloadEntry.comic_id)
        .join(Chapter, Chapter.id == UserDownloadEntry.chapter_id)
        .where(UserDownloadEntry.user_id == user_id)
    )


async def list_download_entry_responses(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    limit: int | None = 200,
    comic_id: int | None = None,
    base_url: str | None = None,
) -> list[DownloadEntryResponse]:
    """List download intents dengan projection ringan tanpa JSONB images."""
    statement = _download_projection_statement(user_id)
    if comic_id is not None:
        statement = statement.where(UserDownloadEntry.comic_id == comic_id)
    statement = statement.order_by(
        UserDownloadEntry.updated_at.desc(),
        UserDownloadEntry.id.desc(),
    )
    if limit is not None:
        statement = statement.limit(limit)
    result = await db.execute(statement)
    return [
        build_download_projection_response(row, base_url=base_url)
        for row in result.all()
    ]


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


def _download_batch_upsert_statement(rows: list[dict]):
    statement = insert(UserDownloadEntry).values(rows)
    return statement.on_conflict_do_update(
        index_elements=[
            UserDownloadEntry.user_id,
            UserDownloadEntry.chapter_id,
        ],
        set_={
            "comic_id": statement.excluded.comic_id,
            "status": statement.excluded.status,
            "source_device_id": statement.excluded.source_device_id,
            "last_error": statement.excluded.last_error,
            "updated_at": statement.excluded.updated_at,
            "downloaded_at": statement.excluded.downloaded_at,
        },
    )


async def enqueue_download_batch(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: DownloadBatchRequest,
    base_url: str | None = None,
) -> DownloadBatchResponse:
    """Enqueue download intent dengan lookup sekali dan bulk upsert."""
    comic = await resolve_comic_or_raise(db, payload.source_name, payload.comic_slug)
    stmt = select(
        Chapter.id.label("chapter_id"),
        Chapter.comic_id.label("comic_id"),
        Chapter.chapter_number.label("chapter_number"),
    ).where(Chapter.comic_id == comic.id)
    chapters_result = await db.execute(stmt.order_by(Chapter.chapter_number.desc()))
    chapters = chapters_result.all()

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

    chapter_ids = [chapter.chapter_id for chapter in filtered]
    existing_result = await db.execute(
        select(UserDownloadEntry.chapter_id).where(
            UserDownloadEntry.user_id == user_id,
            UserDownloadEntry.chapter_id.in_(chapter_ids),
        )
    )
    existing_chapter_ids = set(existing_result.scalars().all())
    now = _utcnow()
    rows = [
        {
            "user_id": user_id,
            "comic_id": chapter.comic_id,
            "chapter_id": chapter.chapter_id,
            "status": payload.status,
            "source_device_id": payload.source_device_id,
            "last_error": None,
            "updated_at": now,
            "downloaded_at": now if payload.status == "completed" else None,
        }
        for chapter in filtered
    ]

    for offset in range(0, len(rows), BULK_DML_CHUNK_SIZE):
        await db.execute(
            _download_batch_upsert_statement(
                rows[offset : offset + BULK_DML_CHUNK_SIZE]
            )
        )

    await db.commit()
    created_total = len(set(chapter_ids) - existing_chapter_ids)
    updated_total = len(existing_chapter_ids)
    return DownloadBatchResponse(
        comic=build_comic_ref(comic, base_url=base_url),
        requested_total=len(filtered),
        created_total=created_total,
        updated_total=updated_total,
        chapter_numbers=sorted(
            [chapter.chapter_number for chapter in filtered],
            reverse=True,
        ),
    )


async def _get_library_summary_counts(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> LibrarySummaryCounts:
    statements = (
        ("bookmarks", UserBookmark),
        ("collections", UserCollection),
        ("favorite_scenes", UserFavoriteScene),
        ("history", UserHistoryEntry),
        ("downloads", UserDownloadEntry),
        ("continue_reading", UserProgress),
    )
    result = await db.execute(
        union_all(
            *[
                select(
                    literal(key).label("key"),
                    func.count(model.id).label("total"),
                ).where(model.user_id == user_id)
                for key, model in statements
            ]
        )
    )
    counts = {row.key: row.total for row in result.all()}
    status_expression = func.lower(
        func.trim(func.coalesce(UserBookmark.status_override, Comic.status))
    )
    status_result = await db.execute(
        select(status_expression, func.count(UserBookmark.id))
        .join(Comic, Comic.id == UserBookmark.comic_id)
        .where(
            UserBookmark.user_id == user_id,
            func.coalesce(UserBookmark.status_override, Comic.status).is_not(None),
        )
        .group_by(status_expression)
    )
    counts["bookmark_status_counts"] = {
        status: total
        for status, total in status_result.all()
        if status
    }
    return LibrarySummaryCounts(**counts)


async def get_library_summary(
    db: AsyncSession,
    user_id: uuid.UUID,
    base_url: str | None = None,
) -> LibrarySummaryResponse:
    """Ringkasan utama library untuk home/library screen."""
    counts = await _get_library_summary_counts(db, user_id)
    continue_reading = await list_continue_reading_responses(
        db,
        user_id,
        page_size=10,
        base_url=base_url,
    )
    history = await list_history_responses(
        db,
        user_id,
        page_size=10,
        base_url=base_url,
    )
    collections = await list_collection_summaries(db, user_id)
    preferences = await db.get(ReaderPreference, user_id)
    reading_stat = await db.get(UserReadingStat, user_id)

    return LibrarySummaryResponse(
        counts=counts,
        reading_time_seconds=(
            reading_stat.total_reading_seconds if reading_stat is not None else 0
        ),
        continue_reading=continue_reading,
        recent_history=history,
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
    base_url: str | None = None,
) -> LibraryComicStateResponse:
    """State terpadu satu komik untuk CTA detail page."""
    comic = await resolve_comic_or_raise(db, source_name, comic_slug)

    direct_bookmark = (
        await db.execute(
            select(UserBookmark)
            .options(
                selectinload(UserBookmark.links).selectinload(
                    UserBookmarkLink.comic
                )
            )
            .where(
                UserBookmark.user_id == user_id,
                UserBookmark.comic_id == comic.id,
            )
        )
    ).scalars().first()
    linked_entry = None
    if direct_bookmark is None:
        linked_entry = (
            await db.execute(
                select(UserBookmarkLink)
                .options(
                    selectinload(UserBookmarkLink.bookmark)
                    .selectinload(UserBookmark.links)
                    .selectinload(UserBookmarkLink.comic),
                    selectinload(UserBookmarkLink.bookmark).selectinload(
                        UserBookmark.comic
                    ),
                )
                .where(
                    UserBookmarkLink.user_id == user_id,
                    UserBookmarkLink.comic_id == comic.id,
                )
            )
        ).scalars().first()
    bookmark = direct_bookmark or (
        linked_entry.bookmark if linked_entry is not None else None
    )
    bookmark_relation = (
        "direct"
        if direct_bookmark is not None
        else "linked"
        if linked_entry is not None
        else "none"
    )
    linked_comics: list[LibraryComicRef] = []
    if bookmark is not None:
        if bookmark.comic_id != comic.id:
            linked_comics.append(
                build_comic_ref(bookmark.comic, base_url=base_url)
            )
        linked_comics.extend(
            build_comic_ref(link.comic, base_url=base_url)
            for link in bookmark.links
            if link.comic_id != comic.id
        )

    overview = (
        await db.execute(
            select(
                exists(
                    select(UserBookmark.id).where(
                        UserBookmark.user_id == user_id,
                        UserBookmark.comic_id == comic.id,
                    )
                ).label("bookmarked"),
                select(func.count(UserFavoriteScene.id))
                .where(
                    UserFavoriteScene.user_id == user_id,
                    UserFavoriteScene.comic_id == comic.id,
                )
                .scalar_subquery()
                .label("favorite_scene_count"),
            )
        )
    ).one()
    progress_row = (
        await db.execute(
            _progress_projection_statement(user_id).where(
                UserProgress.comic_id == comic.id
            )
        )
    ).first()
    history_items = await list_history_responses(
        db,
        user_id,
        page_size=1,
        comic_id=comic.id,
        base_url=base_url,
    )
    collections = await list_collection_summaries(
        db,
        user_id,
        comic_id=comic.id,
    )
    download_entries = await list_download_entry_responses(
        db,
        user_id,
        limit=None,
        comic_id=comic.id,
        base_url=base_url,
    )
    download_status_counts = dict(Counter(entry.status for entry in download_entries))

    completed_rows = await db.execute(
        select(Chapter.chapter_number)
        .join(UserCompletedChapter, UserCompletedChapter.chapter_id == Chapter.id)
        .where(
            UserCompletedChapter.user_id == user_id,
            UserCompletedChapter.comic_id == comic.id,
        )
        .order_by(Chapter.chapter_number.desc())
    )
    completed_chapter_numbers = [float(number) for number in completed_rows.scalars().all()]

    return LibraryComicStateResponse(
        comic=build_comic_ref(
            comic,
            base_url=base_url,
            status_override=direct_bookmark.status_override
            if direct_bookmark is not None
            else None,
        ),
        bookmarked=bookmark is not None,
        bookmark_relation=bookmark_relation,
        bookmark_origin=(
            build_comic_ref(
                bookmark.comic,
                base_url=base_url,
                status_override=bookmark.status_override,
            )
            if bookmark is not None
            else None
        ),
        linked_comics=linked_comics,
        collections=[build_collection_summary_response(item) for item in collections],
        progress=(
            build_progress_projection_response(progress_row, base_url=base_url)
            if progress_row is not None
            else None
        ),
        history=history_items[0] if history_items else None,
        completed_chapter_numbers=completed_chapter_numbers,
        favorite_scene_count=overview.favorite_scene_count or 0,
        download_status_counts=download_status_counts,
        download_entries=download_entries,
    )


def _chunked(items: list, size: int = BULK_DML_CHUNK_SIZE):
    for offset in range(0, len(items), size):
        yield items[offset : offset + size]


async def _bulk_upsert(
    db: AsyncSession,
    model,
    rows: list[dict],
    *,
    index_elements: list,
    update_columns: tuple[str, ...],
) -> None:
    for chunk in _chunked(rows):
        statement = insert(model).values(chunk)
        await db.execute(
            statement.on_conflict_do_update(
                index_elements=index_elements,
                set_={
                    name: getattr(statement.excluded, name)
                    for name in update_columns
                },
            )
        )


def _comic_selector_key(payload) -> tuple[str, str]:
    return payload.source_name, payload.comic_slug


def _chapter_selector_key(payload) -> tuple[str, str, float]:
    return payload.source_name, payload.comic_slug, float(payload.chapter_number)


async def _resolve_comic_selector_ids(
    db: AsyncSession,
    selector_keys: set[tuple[str, str]],
) -> dict[tuple[str, str], int]:
    resolved: dict[tuple[str, str], int] = {}
    for chunk in _chunked(sorted(selector_keys)):
        selector_values = (
            values(
                column("source_name", String),
                column("comic_slug", String),
                name="requested_comics",
            )
            .data(chunk)
            .alias("requested_comics")
        )
        result = await db.execute(
            select(
                selector_values.c.source_name,
                selector_values.c.comic_slug,
                Comic.id.label("comic_id"),
            ).join(
                Comic,
                and_(
                    Comic.source_name == selector_values.c.source_name,
                    Comic.slug == selector_values.c.comic_slug,
                ),
            )
        )
        for row in result.all():
            resolved[(row.source_name, row.comic_slug)] = row.comic_id

    missing = selector_keys - resolved.keys()
    if missing:
        source_name, comic_slug = sorted(missing)[0]
        raise LookupError(f"Comic {source_name}/{comic_slug} tidak ditemukan.")
    return resolved


async def _resolve_chapter_selector_ids(
    db: AsyncSession,
    selector_keys: set[tuple[str, str, float]],
) -> dict[tuple[str, str, float], tuple[int, int]]:
    resolved: dict[tuple[str, str, float], tuple[int, int]] = {}
    for chunk in _chunked(sorted(selector_keys)):
        selector_values = (
            values(
                column("source_name", String),
                column("comic_slug", String),
                column("chapter_number", Float),
                name="requested_chapters",
            )
            .data(chunk)
            .alias("requested_chapters")
        )
        result = await db.execute(
            select(
                selector_values.c.source_name,
                selector_values.c.comic_slug,
                selector_values.c.chapter_number.label("requested_chapter_number"),
                Chapter.id.label("chapter_id"),
                Chapter.comic_id.label("comic_id"),
            )
            .join(
                Comic,
                and_(
                    Comic.source_name == selector_values.c.source_name,
                    Comic.slug == selector_values.c.comic_slug,
                ),
            )
            .join(
                Chapter,
                and_(
                    Chapter.comic_id == Comic.id,
                    Chapter.chapter_number
                    >= selector_values.c.chapter_number - CHAPTER_NUMBER_TOLERANCE,
                    Chapter.chapter_number
                    <= selector_values.c.chapter_number + CHAPTER_NUMBER_TOLERANCE,
                ),
            )
            .order_by(Chapter.id)
        )
        for row in result.all():
            key = (
                row.source_name,
                row.comic_slug,
                float(row.requested_chapter_number),
            )
            resolved.setdefault(key, (row.chapter_id, row.comic_id))

    missing = selector_keys - resolved.keys()
    if missing:
        source_name, comic_slug, chapter_number = sorted(missing)[0]
        raise LookupError(
            f"Chapter {chapter_number} untuk {source_name}/{comic_slug} tidak ditemukan."
        )
    return resolved


async def import_library_snapshot(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: LibrarySyncImportRequest,
) -> LibrarySyncImportResponse:
    """Import snapshot memakai satu transaction atomic dan bulk DML."""
    now = _utcnow()
    comic_selector_keys = {
        _comic_selector_key(item)
        for item in payload.bookmarks
    }
    comic_selector_keys.update(
        _comic_selector_key(item.bookmark)
        for item in payload.bookmark_links
    )
    comic_selector_keys.update(
        _comic_selector_key(item.linked_comic)
        for item in payload.bookmark_links
    )
    comic_selector_keys.update(
        _comic_selector_key(item)
        for collection in payload.collections
        for item in collection.comics
    )
    chapter_payloads = [
        *payload.progress,
        *payload.history,
        *payload.completed_chapters,
        *payload.favorite_scenes,
        *payload.downloads,
    ]
    chapter_selector_keys = {
        _chapter_selector_key(item)
        for item in chapter_payloads
    }

    async with db.begin():
        comic_ids = await _resolve_comic_selector_ids(db, comic_selector_keys)
        chapter_ids = await _resolve_chapter_selector_ids(db, chapter_selector_keys)

        bookmark_rows = {
            comic_ids[_comic_selector_key(item)]: {
                "user_id": user_id,
                "comic_id": comic_ids[_comic_selector_key(item)],
                "updated_at": now,
            }
            for item in [
                *payload.bookmarks,
                *(link.bookmark for link in payload.bookmark_links),
            ]
        }
        await _bulk_upsert(
            db,
            UserBookmark,
            list(bookmark_rows.values()),
            index_elements=[UserBookmark.user_id, UserBookmark.comic_id],
            update_columns=("updated_at",),
        )
        bookmark_ids: dict[int, int] = {}
        if bookmark_rows:
            bookmark_id_rows = await db.execute(
                select(UserBookmark.id, UserBookmark.comic_id).where(
                    UserBookmark.user_id == user_id,
                    UserBookmark.comic_id.in_(bookmark_rows.keys()),
                )
            )
            bookmark_ids = {
                row.comic_id: row.id
                for row in bookmark_id_rows.all()
            }
        bookmark_link_rows = [
            {
                "user_id": user_id,
                "bookmark_id": bookmark_ids[
                    comic_ids[_comic_selector_key(item.bookmark)]
                ],
                "comic_id": comic_ids[
                    _comic_selector_key(item.linked_comic)
                ],
                "confidence": item.confidence,
                "updated_at": now,
            }
            for item in payload.bookmark_links
        ]
        await _bulk_upsert(
            db,
            UserBookmarkLink,
            bookmark_link_rows,
            index_elements=[
                UserBookmarkLink.user_id,
                UserBookmarkLink.comic_id,
            ],
            update_columns=(
                "bookmark_id",
                "confidence",
                "updated_at",
            ),
        )

        collection_payloads = {
            normalize_collection_name(item.name): item
            for item in payload.collections
        }
        collection_rows = [
            {
                "user_id": user_id,
                "name": item.name,
                "normalized_name": normalized_name,
                "updated_at": now,
            }
            for normalized_name, item in collection_payloads.items()
        ]
        collection_ids: dict[str, int] = {}
        for chunk in _chunked(collection_rows):
            statement = insert(UserCollection).values(chunk)
            result = await db.execute(
                statement.on_conflict_do_update(
                    index_elements=[
                        UserCollection.user_id,
                        UserCollection.normalized_name,
                    ],
                    set_={
                        "name": statement.excluded.name,
                        "updated_at": statement.excluded.updated_at,
                    },
                ).returning(UserCollection.id, UserCollection.normalized_name)
            )
            collection_ids.update(
                {
                    row.normalized_name: row.id
                    for row in result.all()
                }
            )

        collection_item_rows = {
            (
                collection_ids[normalized_name],
                comic_ids[_comic_selector_key(comic)],
            ): {
                "collection_id": collection_ids[normalized_name],
                "comic_id": comic_ids[_comic_selector_key(comic)],
            }
            for normalized_name, collection in collection_payloads.items()
            for comic in collection.comics
        }
        collection_items_upserted = 0
        for chunk in _chunked(list(collection_item_rows.values())):
            statement = (
                insert(UserCollectionComic)
                .values(chunk)
                .on_conflict_do_nothing(
                    index_elements=[
                        UserCollectionComic.collection_id,
                        UserCollectionComic.comic_id,
                    ]
                )
                .returning(UserCollectionComic.id)
            )
            collection_items_upserted += len((await db.execute(statement)).all())

        progress_rows: dict[int, dict] = {}
        history_rows: dict[int, dict] = {}
        completed_rows: dict[tuple[int, int], dict] = {}
        for item in payload.progress:
            chapter_id, comic_id = chapter_ids[_chapter_selector_key(item)]
            shared = {
                "user_id": user_id,
                "comic_id": comic_id,
                "chapter_id": chapter_id,
                "reading_mode": item.reading_mode,
                "scroll_offset": item.scroll_offset,
                "page_index": item.page_index,
                "last_read_page_item_index": item.last_read_page_item_index,
                "total_page_items": item.total_page_items,
                "last_read_at": now,
                "updated_at": now,
            }
            progress_rows[comic_id] = {**shared, "is_completed": item.is_completed}
            history_rows[chapter_id] = shared
            if item.is_completed:
                completed_rows[(comic_id, chapter_id)] = {
                    "user_id": user_id,
                    "comic_id": comic_id,
                    "chapter_id": chapter_id,
                    "completed_at": now,
                }

        for item in payload.history:
            chapter_id, comic_id = chapter_ids[_chapter_selector_key(item)]
            history_rows[chapter_id] = {
                "user_id": user_id,
                "comic_id": comic_id,
                "chapter_id": chapter_id,
                "reading_mode": item.reading_mode,
                "scroll_offset": item.scroll_offset,
                "page_index": item.page_index,
                "last_read_page_item_index": item.last_read_page_item_index,
                "total_page_items": item.total_page_items,
                "last_read_at": now,
                "updated_at": now,
            }

        for item in payload.completed_chapters:
            chapter_id, comic_id = chapter_ids[_chapter_selector_key(item)]
            completed_rows[(comic_id, chapter_id)] = {
                "user_id": user_id,
                "comic_id": comic_id,
                "chapter_id": chapter_id,
                "completed_at": now,
            }

        await _bulk_upsert(
            db,
            UserProgress,
            list(progress_rows.values()),
            index_elements=[UserProgress.user_id, UserProgress.comic_id],
            update_columns=(
                "chapter_id",
                "reading_mode",
                "scroll_offset",
                "page_index",
                "last_read_page_item_index",
                "total_page_items",
                "is_completed",
                "last_read_at",
                "updated_at",
            ),
        )
        await _bulk_upsert(
            db,
            UserHistoryEntry,
            list(history_rows.values()),
            index_elements=[UserHistoryEntry.user_id, UserHistoryEntry.chapter_id],
            update_columns=(
                "comic_id",
                "reading_mode",
                "scroll_offset",
                "page_index",
                "last_read_page_item_index",
                "total_page_items",
                "last_read_at",
                "updated_at",
            ),
        )
        await _bulk_upsert(
            db,
            UserCompletedChapter,
            list(completed_rows.values()),
            index_elements=[
                UserCompletedChapter.user_id,
                UserCompletedChapter.comic_id,
                UserCompletedChapter.chapter_id,
            ],
            update_columns=("completed_at",),
        )
        favorite_rows: dict[tuple[int, int], dict] = {}
        for item in payload.favorite_scenes:
            chapter_id, comic_id = chapter_ids[_chapter_selector_key(item)]
            favorite_rows[(chapter_id, item.page_item_index)] = {
                "user_id": user_id,
                "comic_id": comic_id,
                "chapter_id": chapter_id,
                "page_item_index": item.page_item_index,
                "image_url": item.image_url,
                "note": item.note,
                "updated_at": now,
            }
        await _bulk_upsert(
            db,
            UserFavoriteScene,
            list(favorite_rows.values()),
            index_elements=[
                UserFavoriteScene.user_id,
                UserFavoriteScene.chapter_id,
                UserFavoriteScene.page_item_index,
            ],
            update_columns=("comic_id", "image_url", "note", "updated_at"),
        )

        download_rows: dict[int, dict] = {}
        for item in payload.downloads:
            chapter_id, comic_id = chapter_ids[_chapter_selector_key(item)]
            download_rows[chapter_id] = {
                "user_id": user_id,
                "comic_id": comic_id,
                "chapter_id": chapter_id,
                "status": item.status,
                "source_device_id": item.source_device_id,
                "last_error": item.last_error,
                "downloaded_at": now if item.status == "completed" else None,
                "updated_at": now,
            }
        await _bulk_upsert(
            db,
            UserDownloadEntry,
            list(download_rows.values()),
            index_elements=[UserDownloadEntry.user_id, UserDownloadEntry.chapter_id],
            update_columns=(
                "comic_id",
                "status",
                "source_device_id",
                "last_error",
                "downloaded_at",
                "updated_at",
            ),
        )

        if payload.reader_preferences is not None:
            preference = payload.reader_preferences
            await _bulk_upsert(
                db,
                ReaderPreference,
                [
                    {
                        "user_id": user_id,
                        "default_reading_mode": preference.default_reading_mode,
                        "reading_direction": preference.reading_direction,
                        "mark_read_on_complete": preference.mark_read_on_complete,
                        "default_binge_mode": preference.default_binge_mode,
                        "auto_scroll_enabled": preference.auto_scroll_enabled,
                        "auto_scroll_speed": preference.auto_scroll_speed,
                        "updated_at": now,
                    }
                ],
                index_elements=[ReaderPreference.user_id],
                update_columns=(
                    "default_reading_mode",
                    "reading_direction",
                    "mark_read_on_complete",
                    "default_binge_mode",
                    "auto_scroll_enabled",
                    "auto_scroll_speed",
                    "updated_at",
                ),
            )

        if payload.reading_time_seconds > 0:
            statement = insert(UserReadingStat).values(
                user_id=user_id,
                total_reading_seconds=payload.reading_time_seconds,
                updated_at=now,
            )
            await db.execute(
                statement.on_conflict_do_update(
                    index_elements=[UserReadingStat.user_id],
                    set_={
                        "total_reading_seconds": UserReadingStat.total_reading_seconds
                        + payload.reading_time_seconds,
                        "updated_at": now,
                    },
                )
            )

    return LibrarySyncImportResponse(
        bookmarks_upserted=len(bookmark_rows),
        bookmark_links_upserted=len(bookmark_link_rows),
        collections_upserted=len(collection_rows),
        collection_items_upserted=collection_items_upserted,
        progress_upserted=len(progress_rows),
        history_upserted=len(history_rows),
        completed_chapters_upserted=len(completed_rows),
        favorite_scenes_upserted=len(favorite_rows),
        downloads_upserted=len(download_rows),
        reader_preferences_updated=payload.reader_preferences is not None,
        reading_time_seconds_imported=payload.reading_time_seconds,
        completion_sync_bookmark_ids=sorted(
            {
                row["bookmark_id"]
                for row in bookmark_link_rows
            }
        ),
    )
