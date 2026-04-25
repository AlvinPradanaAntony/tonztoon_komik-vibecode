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

from app.api.deps import get_current_user_id
from app.database import get_db
from app.schemas import (
    BookmarkResponse,
    CollectionCreateRequest,
    CollectionResponse,
    CollectionSummaryResponse,
    CollectionUpdateRequest,
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
    build_history_response,
    build_progress_response,
    build_reader_preferences_response,
    create_collection,
    delete_bookmark,
    delete_collection,
    delete_download_entry,
    delete_favorite_scene,
    enqueue_download_batch,
    get_library_state_for_comic,
    get_library_summary,
    get_or_create_reader_preferences,
    get_progress_for_comic,
    import_library_snapshot,
    list_bookmarks,
    list_collections,
    list_continue_reading,
    list_download_entries,
    list_favorite_scenes,
    list_history,
    remove_comic_from_collection,
    rename_collection,
    set_bookmark,
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
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Daftar continue reading terbaru."""
    items = await list_continue_reading(db, user_id, limit=limit)
    base_url = _get_request_base_url(request)
    return [build_progress_response(item, base_url=base_url) for item in items]


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


@router.get("/bookmarks", response_model=list[BookmarkResponse])
async def get_bookmarks(
    request: Request,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List semua bookmark komik user."""
    items = await list_bookmarks(db, user_id)
    base_url = _get_request_base_url(request)
    return [build_bookmark_response(item, base_url=base_url) for item in items]


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


@router.get("/collections", response_model=list[CollectionSummaryResponse])
async def get_collections(
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List koleksi/folder user."""
    items = await list_collections(db, user_id)
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
    collections = await list_collections(db, user_id)
    collection = next((item for item in collections if item.id == collection_id), None)
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
    "/collections/{collection_id}/comics/{source_name}/{comic_slug}",
    response_model=CollectionResponse,
)
async def put_collection_comic(
    request: Request,
    collection_id: int,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Tambahkan komik ke koleksi."""
    try:
        collection = await add_comic_to_collection(
            db,
            user_id,
            collection_id,
            source_name,
            comic_slug,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_collection_response(collection, base_url=_get_request_base_url(request))


@router.delete(
    "/collections/{collection_id}/comics/{source_name}/{comic_slug}",
    response_model=CollectionResponse,
)
async def delete_collection_comic(
    request: Request,
    collection_id: int,
    source_name: str,
    comic_slug: str,
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """Hapus komik dari koleksi."""
    try:
        collection = await remove_comic_from_collection(
            db,
            user_id,
            collection_id,
            source_name,
            comic_slug,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return build_collection_response(collection, base_url=_get_request_base_url(request))


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
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List riwayat baca terbaru."""
    items = await list_history(db, user_id, limit=limit)
    base_url = _get_request_base_url(request)
    return [build_history_response(item, base_url=base_url) for item in items]


@router.get("/downloads", response_model=list[DownloadEntryResponse])
async def get_downloads(
    request: Request,
    limit: int = Query(200, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    user_id: UUID = Depends(get_current_user_id),
):
    """List intent/status download chapter."""
    items = await list_download_entries(db, user_id, limit=limit)
    base_url = _get_request_base_url(request)
    return [build_download_response(item, base_url=base_url) for item in items]


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
