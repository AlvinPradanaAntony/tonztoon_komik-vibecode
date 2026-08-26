"""
User library API routes.

Kontrak sementara autentikasi:
- Semua endpoint membutuhkan header `X-User-Id: <uuid>`
- Nantinya dependency ini bisa diganti dengan validasi JWT Supabase
  tanpa mengubah shape endpoint user-library.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_auth_user, get_current_user_id, is_admin_auth_user
from app.database import get_db
from app.schemas import (
    AuthenticatedUser,
    BookmarkResponse,
    BookmarkStatusUpdateRequest,
    BookmarkLinkBatchRequest,
    BookmarkLinkBatchResponse,
    BookmarkLinkCandidatePage,
    BookmarkLinkCompletionSyncRequest,
    BookmarkLinkCompletionSyncResponse,
    ComicCollectionsUpdateRequest,
    CollectionCreateRequest,
    CollectionResponse,
    CollectionSummaryResponse,
    CollectionUpdateRequest,
    CompletedChapterBatchImportRequest,
    CompletedChapterBatchResponse,
    CompletedChapterImportRequest,
    DownloadBatchRequest,
    DownloadBatchResponse,
    DownloadEntryResponse,
    DownloadEntryUpsertRequest,
    FavoriteSceneCreateRequest,
    FavoriteSceneResponse,
    HistoryItemResponse,
    LibraryComicStateResponse,
    LibrarySummaryResponse,
    LibrarySyncImportRequest,
    LibrarySyncImportResponse,
    ProgressResponse,
    ProgressUpsertRequest,
    ReadingTimeDeltaRequest,
    ReadingTimeResponse,
    ReaderPreferenceResponse,
    ReaderPreferenceUpdateRequest,
)
from app.services.library_service import (
    add_comic_to_collection,
    build_bookmark_response,
    build_collection_response,
    build_collection_summary_response,
    build_download_response,
    build_favorite_scene_response,
    build_progress_response,
    build_reading_time_response,
    build_reader_preferences_response,
    create_collection,
    delete_bookmark,
    delete_bookmark_link,
    delete_collection,
    delete_download_entry,
    delete_favorite_scene,
    enqueue_download_batch,
    add_reading_time_delta,
    get_collection_detail as load_collection_detail,
    get_library_state_for_comic,
    get_library_summary,
    get_or_create_reader_preferences,
    get_or_create_reading_stat,
    get_progress_for_comic,
    import_library_snapshot,
    list_bookmarks,
    list_bookmark_link_candidates,
    list_collection_summaries,
    list_continue_reading_responses,
    list_download_entry_responses,
    list_favorite_scenes,
    list_history_responses,
    mark_completed_chapter_batch,
    mark_chapter_completed,
    remove_comic_from_collection,
    rename_collection,
    set_bookmark,
    set_bookmark_status,
    set_comic_collections,
    set_bookmark_links,
    synchronize_completed_link_batch,
    update_reader_preferences,
    upsert_download_entry,
    upsert_favorite_scene,
    upsert_progress,
)

router = APIRouter()


def _get_request_base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


@router.get("/summary", response_model=LibrarySummaryResponse)
async def get_user_library_summary(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Ringkasan counts + continue reading + history terbaru."""
    return await get_library_summary(db, user_id, base_url=_get_request_base_url(request))


@router.get(
    "/state/{source_name}/comics/{comic_slug}",
    response_model=LibraryComicStateResponse,
)
async def get_user_library_state_for_comic(
    request: Request,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """State CTA detail komik: bookmark, koleksi, progress, downloads, dst."""
    try:
        return await get_library_state_for_comic(
            db,
            user_id,
            source_name,
            comic_slug,
            base_url=_get_request_base_url(request),
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/progress/continue-reading", response_model=list[ProgressResponse])
async def get_continue_reading(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Daftar continue reading terbaru."""
    return await list_continue_reading_responses(
        db,
        user_id,
        page_size=page_size,
        offset=(page - 1) * page_size,
        base_url=_get_request_base_url(request),
    )


@router.get(
    "/progress/{source_name}/comics/{comic_slug}",
    response_model=ProgressResponse | None,
)
async def get_progress_detail(
    request: Request,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Progress untuk satu komik."""
    progress = await get_progress_for_comic(db, user_id, source_name, comic_slug)
    return (
        build_progress_response(progress, base_url=_get_request_base_url(request))
        if progress is not None
        else None
    )


@router.put(
    "/progress/{source_name}/comics/{comic_slug}/chapters/{chapter_number}",
    response_model=ProgressResponse,
)
async def put_progress(
    request: Request,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
    payload: ProgressUpsertRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Upsert progress baca dan mirror ke history."""
    if payload.source_name != source_name or payload.comic_slug != comic_slug:
        raise HTTPException(
            status_code=400,
            detail="Payload source_name/comic_slug harus sama dengan path.",
        )
    if abs(payload.chapter_number - chapter_number) > 0.0001:
        raise HTTPException(
            status_code=400,
            detail="Payload chapter_number harus sama dengan path.",
        )

    try:
        progress = await upsert_progress(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_progress_response(progress, base_url=_get_request_base_url(request))


@router.post("/completed-chapters")
async def post_completed_chapter(
    payload: CompletedChapterImportRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Tandai chapter selesai tanpa mengubah posisi continue reading."""
    try:
        await mark_chapter_completed(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"completed": True}


@router.post(
    "/completed-chapters/batch",
    response_model=CompletedChapterBatchResponse,
)
async def post_completed_chapter_batch(
    payload: CompletedChapterBatchImportRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Bulk upsert completed chapter dan propagate linked source sekali transaksi."""
    try:
        return await mark_completed_chapter_batch(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/bookmarks", response_model=list[BookmarkResponse])
async def get_bookmarks(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    comic_type: str | None = Query(default=None, alias="type"),
    comic_status: str | None = Query(default=None, alias="status"),
    search: str | None = Query(default=None),
    sort: Literal["latest", "az", "za"] | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List bookmark komik user terbaru secara paginated."""
    items = await list_bookmarks(
        db,
        user_id,
        page_size=page_size,
        offset=(page - 1) * page_size,
        comic_type=comic_type,
        comic_status=comic_status,
        search=search,
        sort=sort,
    )
    base_url = _get_request_base_url(request)
    return [build_bookmark_response(item, has_new_chapter=hnc, base_url=base_url) for item, hnc in items]


@router.put(
    "/bookmarks/{source_name}/comics/{comic_slug}",
    response_model=BookmarkResponse,
)
async def put_bookmark(
    request: Request,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Toggle on / upsert bookmark komik."""
    try:
        bookmark = await set_bookmark(db, user_id, source_name, comic_slug)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_bookmark_response(bookmark, base_url=_get_request_base_url(request))


@router.patch(
    "/bookmarks/{source_name}/comics/{comic_slug}/status",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def patch_bookmark_status(
    source_name: str,
    comic_slug: str,
    payload: BookmarkStatusUpdateRequest,
    db: AsyncSession = Depends(get_db),
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
) -> None:
    """Ubah status bookmark; admin mengubah status komik secara global."""
    user_id = auth_user.user_id
    try:
        await set_bookmark_status(
            db,
            user_id,
            source_name,
            comic_slug,
            payload.status,
            global_scope=is_admin_auth_user(auth_user),
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/bookmarks/{source_name}/comics/{comic_slug}")
async def remove_bookmark(
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Hapus bookmark komik."""
    deleted = await delete_bookmark(db, user_id, source_name, comic_slug)
    if not deleted:
        raise HTTPException(status_code=404, detail="Bookmark tidak ditemukan.")
    return {"deleted": True}


@router.get(
    "/bookmark-links/candidates",
    response_model=BookmarkLinkCandidatePage,
)
async def get_bookmark_link_candidates(
    request: Request,
    offset: int = Query(default=0, ge=0),
    page_size: int = Query(default=5, ge=1, le=10),
    source_name: str | None = Query(default=None),
    comic_slug: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Pindai kandidat source alternatif secara eksplisit."""
    if (source_name is None) != (comic_slug is None):
        raise HTTPException(
            status_code=422,
            detail="source_name dan comic_slug harus dikirim bersamaan.",
        )
    return await list_bookmark_link_candidates(
        db,
        user_id,
        base_url=_get_request_base_url(request),
        offset=offset,
        page_size=page_size,
        source_name=source_name,
        comic_slug=comic_slug,
    )


@router.post(
    "/bookmark-links",
    response_model=BookmarkLinkBatchResponse,
)
async def post_bookmark_links(
    payload: BookmarkLinkBatchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Simpan kandidat source yang dikonfirmasi user."""
    try:
        return await set_bookmark_links(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post(
    "/bookmark-links/completed-sync",
    response_model=BookmarkLinkCompletionSyncResponse,
)
async def post_bookmark_link_completed_sync(
    payload: BookmarkLinkCompletionSyncRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Sinkronkan completed dalam batch kecil dan transaksi terpisah."""
    return await synchronize_completed_link_batch(
        db,
        user_id,
        payload.bookmark_ids,
    )


@router.delete("/bookmark-links/{source_name}/comics/{comic_slug}")
async def remove_bookmark_link(
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Putuskan source alternatif tanpa menghapus bookmark utama."""
    deleted = await delete_bookmark_link(
        db,
        user_id,
        source_name,
        comic_slug,
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Relasi source tidak ditemukan.")
    return {"deleted": True}


@router.get("/collections", response_model=list[CollectionSummaryResponse])
async def get_collections(
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List koleksi/folder user."""
    items = await list_collection_summaries(db, user_id)
    return [build_collection_summary_response(item) for item in items]


@router.post(
    "/collections",
    response_model=CollectionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def post_collection(
    request: Request,
    payload: CollectionCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Buat koleksi baru."""
    try:
        collection = await create_collection(db, user_id, payload.name)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return build_collection_response(collection, base_url=_get_request_base_url(request))


@router.get("/collections/{collection_id}", response_model=CollectionResponse)
async def get_collection_detail(
    request: Request,
    collection_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Detail isi koleksi."""
    collection = await load_collection_detail(db, user_id, collection_id)
    if collection is None:
        raise HTTPException(status_code=404, detail="Collection tidak ditemukan.")
    return build_collection_response(collection, base_url=_get_request_base_url(request))


@router.patch("/collections/{collection_id}", response_model=CollectionResponse)
async def patch_collection(
    request: Request,
    collection_id: int,
    payload: CollectionUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Rename koleksi."""
    try:
        collection = await rename_collection(db, user_id, collection_id, payload.name)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return build_collection_response(collection, base_url=_get_request_base_url(request))


@router.delete("/collections/{collection_id}")
async def remove_collection(
    collection_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Hapus satu koleksi."""
    deleted = await delete_collection(db, user_id, collection_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Collection tidak ditemukan.")
    return {"deleted": True}


@router.put(
    "/comics/{source_name}/{comic_slug}/collections",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def put_comic_collections(
    source_name: str,
    comic_slug: str,
    payload: ComicCollectionsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
) -> None:
    """Set seluruh membership koleksi satu komik dalam satu transaksi."""
    try:
        await set_comic_collections(
            db,
            user_id,
            source_name,
            comic_slug,
            set(payload.collection_ids),
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.put(
    "/collections/{collection_id}/comics/{source_name}/{comic_slug}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def put_collection_comic(
    collection_id: int,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
) -> None:
    """Tambahkan komik ke koleksi."""
    try:
        await add_comic_to_collection(
            db,
            user_id,
            collection_id,
            source_name,
            comic_slug,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete(
    "/collections/{collection_id}/comics/{source_name}/{comic_slug}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_collection_comic(
    collection_id: int,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
) -> None:
    """Hapus komik dari koleksi."""
    try:
        await remove_comic_from_collection(
            db,
            user_id,
            collection_id,
            source_name,
            comic_slug,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/favorite-scenes", response_model=list[FavoriteSceneResponse])
async def get_favorite_scenes(
    request: Request,
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List favorite scenes user."""
    items = await list_favorite_scenes(db, user_id, limit=limit)
    base_url = _get_request_base_url(request)
    return [build_favorite_scene_response(item, base_url=base_url) for item in items]


@router.post(
    "/favorite-scenes",
    response_model=FavoriteSceneResponse,
    status_code=status.HTTP_201_CREATED,
)
async def post_favorite_scene(
    request: Request,
    payload: FavoriteSceneCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Save / upsert favorite scene dari reader."""
    try:
        scene = await upsert_favorite_scene(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_favorite_scene_response(scene, base_url=_get_request_base_url(request))


@router.delete("/favorite-scenes/{scene_id}")
async def remove_favorite_scene(
    scene_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Hapus favorite scene."""
    deleted = await delete_favorite_scene(db, user_id, scene_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Favorite scene tidak ditemukan.")
    return {"deleted": True}


@router.get("/history", response_model=list[HistoryItemResponse])
async def get_history(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List riwayat baca terbaru."""
    return await list_history_responses(
        db,
        user_id,
        page_size=page_size,
        offset=(page - 1) * page_size,
        base_url=_get_request_base_url(request),
    )


@router.get("/downloads", response_model=list[DownloadEntryResponse])
async def get_downloads(
    request: Request,
    limit: int = Query(200, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List intent/status download chapter."""
    return await list_download_entry_responses(
        db,
        user_id,
        limit=limit,
        base_url=_get_request_base_url(request),
    )


@router.put(
    "/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}",
    response_model=DownloadEntryResponse,
)
async def put_download(
    request: Request,
    source_name: str,
    comic_slug: str,
    chapter_number: float,
    payload: DownloadEntryUpsertRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Upsert intent/status download per chapter."""
    if payload.source_name != source_name or payload.comic_slug != comic_slug:
        raise HTTPException(
            status_code=400,
            detail="Payload source_name/comic_slug harus sama dengan path.",
        )
    if abs(payload.chapter_number - chapter_number) > 0.0001:
        raise HTTPException(
            status_code=400,
            detail="Payload chapter_number harus sama dengan path.",
        )

    try:
        entry = await upsert_download_entry(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_download_response(entry, base_url=_get_request_base_url(request))


@router.delete("/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}")
async def remove_download(
    source_name: str,
    comic_slug: str,
    chapter_number: float,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Hapus download intent chapter."""
    deleted = await delete_download_entry(
        db,
        user_id,
        source_name,
        comic_slug,
        chapter_number,
    )
    if not deleted:
        raise HTTPException(status_code=404, detail="Download entry tidak ditemukan.")
    return {"deleted": True}


@router.post("/downloads/batch", response_model=DownloadBatchResponse)
async def post_download_batch(
    request: Request,
    payload: DownloadBatchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Enqueue download intent untuk seluruh/rentang chapter komik."""
    try:
        return await enqueue_download_batch(
            db,
            user_id,
            payload,
            base_url=_get_request_base_url(request),
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/reader-preferences", response_model=ReaderPreferenceResponse)
async def get_reader_preferences(
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Ambil reader preferences, membuat default bila belum ada."""
    preference = await get_or_create_reader_preferences(db, user_id)
    return build_reader_preferences_response(preference)


@router.get("/reading-time", response_model=ReadingTimeResponse)
async def get_reading_time(
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Ambil total waktu baca user dalam detik."""
    stat = await get_or_create_reading_stat(db, user_id)
    return build_reading_time_response(stat)


@router.post("/reading-time", response_model=ReadingTimeResponse)
async def post_reading_time_delta(
    payload: ReadingTimeDeltaRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Tambahkan delta durasi baca dari reader."""
    stat = await add_reading_time_delta(db, user_id, payload.delta_seconds)
    return build_reading_time_response(stat)


@router.put("/reader-preferences", response_model=ReaderPreferenceResponse)
async def put_reader_preferences(
    payload: ReaderPreferenceUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Upsert reader preferences user."""
    preference = await update_reader_preferences(db, user_id, payload)
    return build_reader_preferences_response(preference)


@router.post("/sync/import", response_model=LibrarySyncImportResponse)
async def post_library_sync_import(
    payload: LibrarySyncImportRequest,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Import snapshot local -> cloud untuk migrasi login pertama."""
    try:
        return await import_library_snapshot(db, user_id, payload)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
