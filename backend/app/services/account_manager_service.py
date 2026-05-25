"""
Service layer untuk dashboard account manager.

Operasi Supabase Auth Admin sengaja ditempatkan di backend agar service role key
tidak pernah bocor ke HTML/JavaScript browser.
"""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime
from typing import Any

import httpx
from sqlalchemy import delete, func, literal, select, union_all
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_supabase_auth_base_url, settings
from app.models import (
    Profile,
    ReaderPreference,
    UserBookmark,
    UserCollection,
    UserCollectionComic,
    UserCompletedChapter,
    UserDownloadEntry,
    UserFavoriteScene,
    UserHistoryEntry,
    UserProgress,
    UserReadingStat,
)
from app.schemas import (
    AccountDeleteResponse,
    AccountManagerCreateRequest,
    AccountManagerListResponse,
    AccountManagerUpdateRequest,
    AccountManagerUser,
    AccountProfileData,
    AccountRelationCounts,
    AccountRelationPreview,
    AccountRelationPreviewItem,
)
from app.services.profile_service import normalize_username

_UNSET = object()
logger = logging.getLogger(__name__)


class AccountManagerConfigurationError(RuntimeError):
    """Raised when Supabase admin configuration is missing."""


class AccountManagerRequestError(RuntimeError):
    """Raised when a Supabase Admin API request fails."""

    def __init__(self, message: str, *, status_code: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _utcnow() -> datetime:
    return datetime.now(UTC)


def _require_admin_config() -> str:
    auth_base = get_supabase_auth_base_url()
    if not auth_base or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise AccountManagerConfigurationError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured.",
        )
    return auth_base


def _admin_headers() -> dict[str, str]:
    _require_admin_config()
    return {
        "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _extract_admin_error(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        return f"Supabase Admin request failed with status {response.status_code}."
    return (
        payload.get("msg")
        or payload.get("message")
        or payload.get("error_description")
        or payload.get("error")
        or f"Supabase Admin request failed with status {response.status_code}."
    )


def _normalize_auth_user_payload(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    if isinstance(data.get("user"), dict):
        return data["user"]
    return data


async def _request_admin(
    method: str,
    path: str,
    *,
    json: dict[str, Any] | None = None,
    params: dict[str, Any] | None = None,
    expected_statuses: set[int] | None = None,
) -> dict[str, Any]:
    auth_base = _require_admin_config()
    expected_statuses = expected_statuses or {200}

    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            response = await client.request(
                method,
                f"{auth_base}{path}",
                headers=_admin_headers(),
                json=json,
                params=params,
            )
        except httpx.TimeoutException as exc:
            logger.error(f"Supabase Admin request timeout ({method} {path})")
            raise AccountManagerRequestError(
                f"Request to Supabase Auth timed out after 60s: {str(exc)}",
                status_code=504
            ) from exc

    if response.status_code not in expected_statuses:
        raise AccountManagerRequestError(
            _extract_admin_error(response),
            status_code=response.status_code,
        )

    if response.status_code == 204 or not response.content:
        return {}
    return response.json()


def _metadata_role(metadata: dict[str, Any], fallback: str | None = None) -> str | None:
    return (
        metadata.get("account_role")
        or metadata.get("role")
        or metadata.get("admin_role")
        or fallback
    )


def _metadata_status(metadata: dict[str, Any]) -> str:
    return str(metadata.get("account_status") or metadata.get("status") or "active")


def _is_future_datetime(value: str | None) -> bool:
    if not value:
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed > _utcnow()


def _account_status(raw_user: dict[str, Any], app_metadata: dict[str, Any]) -> str:
    if _is_future_datetime(raw_user.get("banned_until")):
        return "suspended"
    return _metadata_status(app_metadata)


def _ban_duration_for_status(status: str | None) -> str | None:
    if status == "suspended":
        return "876000h"
    if status in {"active", "pending"}:
        return "none"
    return None


async def _get_profiles_by_user_id(
    db: AsyncSession,
    user_ids: list[uuid.UUID],
) -> dict[uuid.UUID, Profile]:
    if not user_ids:
        return {}
    result = await db.execute(select(Profile).where(Profile.id.in_(user_ids)))
    return {profile.id: profile for profile in result.scalars().all()}


async def _apply_group_counts(
    db: AsyncSession,
    counts_by_user_id: dict[uuid.UUID, AccountRelationCounts],
    *,
    model: Any,
    user_column: Any,
    field_name: str,
) -> None:
    user_ids = list(counts_by_user_id)
    result = await db.execute(
        select(user_column, func.count())
        .select_from(model)
        .where(user_column.in_(user_ids))
        .group_by(user_column),
    )
    for user_id, count in result.all():
        normalized_user_id = uuid.UUID(str(user_id))
        if normalized_user_id in counts_by_user_id:
            setattr(counts_by_user_id[normalized_user_id], field_name, int(count or 0))


async def get_relation_counts_by_user_ids(
    db: AsyncSession,
    user_ids: list[uuid.UUID],
) -> dict[uuid.UUID, AccountRelationCounts]:
    counts_by_user_id = {user_id: AccountRelationCounts() for user_id in user_ids}
    if not counts_by_user_id:
        return {}

    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=Profile,
        user_column=Profile.id,
        field_name="profiles",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=ReaderPreference,
        user_column=ReaderPreference.user_id,
        field_name="reader_preferences",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserReadingStat,
        user_column=UserReadingStat.user_id,
        field_name="user_reading_stats",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserBookmark,
        user_column=UserBookmark.user_id,
        field_name="user_bookmarks",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserCollection,
        user_column=UserCollection.user_id,
        field_name="user_collections",
    )
    collection_items = await db.execute(
        select(UserCollection.user_id, func.count(UserCollectionComic.id))
        .select_from(UserCollectionComic)
        .join(UserCollection, UserCollectionComic.collection_id == UserCollection.id)
        .where(UserCollection.user_id.in_(list(counts_by_user_id)))
        .group_by(UserCollection.user_id),
    )
    for user_id, count in collection_items.all():
        normalized_user_id = uuid.UUID(str(user_id))
        if normalized_user_id in counts_by_user_id:
            counts_by_user_id[normalized_user_id].user_collection_comics = int(count or 0)
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserProgress,
        user_column=UserProgress.user_id,
        field_name="user_progress",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserCompletedChapter,
        user_column=UserCompletedChapter.user_id,
        field_name="user_completed_chapters",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserHistoryEntry,
        user_column=UserHistoryEntry.user_id,
        field_name="user_history_entries",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserFavoriteScene,
        user_column=UserFavoriteScene.user_id,
        field_name="user_favorite_scenes",
    )
    await _apply_group_counts(
        db,
        counts_by_user_id,
        model=UserDownloadEntry,
        user_column=UserDownloadEntry.user_id,
        field_name="user_download_entries",
    )
    return counts_by_user_id


async def get_relation_counts(db: AsyncSession, user_id: uuid.UUID) -> AccountRelationCounts:
    collection_ids = select(UserCollection.id).where(UserCollection.user_id == user_id)
    query = union_all(
        select(literal("profiles"), func.count()).select_from(Profile).where(Profile.id == user_id),
        select(literal("reader_preferences"), func.count())
        .select_from(ReaderPreference)
        .where(ReaderPreference.user_id == user_id),
        select(literal("user_reading_stats"), func.count())
        .select_from(UserReadingStat)
        .where(UserReadingStat.user_id == user_id),
        select(literal("user_bookmarks"), func.count())
        .select_from(UserBookmark)
        .where(UserBookmark.user_id == user_id),
        select(literal("user_collections"), func.count())
        .select_from(UserCollection)
        .where(UserCollection.user_id == user_id),
        select(literal("user_collection_comics"), func.count())
        .select_from(UserCollectionComic)
        .where(UserCollectionComic.collection_id.in_(collection_ids)),
        select(literal("user_progress"), func.count())
        .select_from(UserProgress)
        .where(UserProgress.user_id == user_id),
        select(literal("user_completed_chapters"), func.count())
        .select_from(UserCompletedChapter)
        .where(UserCompletedChapter.user_id == user_id),
        select(literal("user_history_entries"), func.count())
        .select_from(UserHistoryEntry)
        .where(UserHistoryEntry.user_id == user_id),
        select(literal("user_favorite_scenes"), func.count())
        .select_from(UserFavoriteScene)
        .where(UserFavoriteScene.user_id == user_id),
        select(literal("user_download_entries"), func.count())
        .select_from(UserDownloadEntry)
        .where(UserDownloadEntry.user_id == user_id),
    )
    result = await db.execute(query)
    counts = AccountRelationCounts()
    for field_name, count in result.all():
        setattr(counts, field_name, int(count or 0))
    return counts


def _build_profile_data(profile: Profile | None) -> AccountProfileData | None:
    if profile is None:
        return None
    return AccountProfileData(
        username=profile.username,
        display_name=profile.display_name,
        avatar_url=profile.avatar_url,
        onboarding_completed=profile.onboarding_completed,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


async def build_account_user(
    db: AsyncSession,
    raw_user: dict[str, Any],
    *,
    profile: Profile | None = None,
    relation_counts: AccountRelationCounts | None = None,
) -> AccountManagerUser:
    user_id = uuid.UUID(str(raw_user["id"]))
    app_metadata = raw_user.get("app_metadata") or {}
    user_metadata = raw_user.get("user_metadata") or {}
    counts = relation_counts or await get_relation_counts(db, user_id)
    
    # 1. Resolve role dari metadata
    account_role = _metadata_role(app_metadata, _metadata_role(user_metadata, "reader"))
    
    # 2. Jika akun di-bypass lewat ADMIN_USER_IDS, paksa ia menjadi admin
    admin_ids_csv = settings.ADMIN_USER_IDS or ""
    allowed_admin_ids = {uid.strip() for uid in admin_ids_csv.split(",") if uid.strip()}
    if str(user_id) in allowed_admin_ids and account_role == "reader":
        account_role = "admin"

    return AccountManagerUser(
        id=user_id,
        email=raw_user.get("email"),
        phone=raw_user.get("phone"),
        role=raw_user.get("role"),
        account_role=account_role,
        account_status=_account_status(raw_user, app_metadata),
        created_at=raw_user.get("created_at"),
        updated_at=raw_user.get("updated_at"),
        last_sign_in_at=raw_user.get("last_sign_in_at"),
        email_confirmed_at=raw_user.get("email_confirmed_at"),
        banned_until=raw_user.get("banned_until"),
        app_metadata=app_metadata,
        user_metadata=user_metadata,
        profile=_build_profile_data(profile),
        relation_counts=counts,
        relation_total=counts.total,
    )


async def list_accounts(
    db: AsyncSession,
    *,
    page: int = 1,
    per_page: int = 100,
) -> AccountManagerListResponse:
    payload = await _request_admin(
        "GET",
        "/admin/users",
        params={"page": page, "per_page": per_page},
    )
    raw_users = payload.get("users") or payload.get("data", {}).get("users") or []
    user_ids = [uuid.UUID(str(user["id"])) for user in raw_users]
    profiles = await _get_profiles_by_user_id(db, user_ids)
    relation_counts_by_user_id = await get_relation_counts_by_user_ids(db, user_ids)
    users = [
        await build_account_user(
            db,
            raw_user,
            profile=profiles.get(uuid.UUID(str(raw_user["id"]))),
            relation_counts=relation_counts_by_user_id.get(
                uuid.UUID(str(raw_user["id"])),
                AccountRelationCounts(),
            ),
        )
        for raw_user in raw_users
    ]

    return AccountManagerListResponse(
        users=users,
        total=int(payload.get("total") or len(users)),
        page=page,
        per_page=per_page,
    )


async def get_auth_user(user_id: uuid.UUID) -> dict[str, Any]:
    payload = await _request_admin("GET", f"/admin/users/{user_id}")
    return _normalize_auth_user_payload(payload)


async def create_account(
    db: AsyncSession,
    payload: AccountManagerCreateRequest,
) -> AccountManagerUser:
    await assert_username_available(db, payload.username)
    user_metadata: dict[str, Any] = {
        "display_name": payload.display_name,
        "username": payload.username,
    }
    user_metadata = {key: value for key, value in user_metadata.items() if value is not None}

    raw_response = await _request_admin(
        "POST",
        "/admin/users",
        json={
            "email": str(payload.email),
            "password": payload.password,
            "email_confirm": payload.email_confirm,
            "user_metadata": user_metadata,
            "app_metadata": {
                "account_role": payload.account_role,
                "account_status": payload.account_status,
            },
        },
    )
    raw_user = _normalize_auth_user_payload(raw_response)
    user_id = uuid.UUID(str(raw_user["id"]))
    ban_duration = _ban_duration_for_status(payload.account_status)
    if ban_duration and payload.account_status == "suspended":
        raw_user = _normalize_auth_user_payload(
            await _request_admin(
                "PUT",
                f"/admin/users/{user_id}",
                json={"ban_duration": ban_duration},
            ),
        )

    try:
        profile = await upsert_profile(
            db,
            user_id,
            username=payload.username,
            display_name=payload.display_name,
            avatar_url=payload.avatar_url,
            onboarding_completed=payload.onboarding_completed,
        )
        await ensure_reader_preference(db, user_id)
    except Exception:
        try:
            await _request_admin(
                "DELETE",
                f"/admin/users/{user_id}",
                expected_statuses={200, 204},
            )
        except AccountManagerRequestError:
            pass
        raise
    return await build_account_user(
        db,
        raw_user,
        profile=profile,
        relation_counts=AccountRelationCounts(profiles=1, reader_preferences=1),
    )


async def update_account(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: AccountManagerUpdateRequest,
) -> AccountManagerUser:
    current = await get_auth_user(user_id)
    fields_set = payload.model_fields_set
    if "username" in fields_set:
        await assert_username_available(db, payload.username, user_id=user_id)

    app_metadata = dict(current.get("app_metadata") or {})
    user_metadata = dict(current.get("user_metadata") or {})

    update_body: dict[str, Any] = {}
    if payload.email is not None:
        update_body["email"] = str(payload.email)
    if payload.password is not None:
        update_body["password"] = payload.password

    if "display_name" in fields_set:
        user_metadata["display_name"] = payload.display_name
    if "username" in fields_set:
        user_metadata["username"] = payload.username
    if "account_role" in fields_set and payload.account_role is not None:
        app_metadata["account_role"] = payload.account_role
    if "account_status" in fields_set and payload.account_status is not None:
        app_metadata["account_status"] = payload.account_status
        ban_duration = _ban_duration_for_status(payload.account_status)
        if ban_duration:
            update_body["ban_duration"] = ban_duration

    if user_metadata != (current.get("user_metadata") or {}):
        update_body["user_metadata"] = user_metadata
    if app_metadata != (current.get("app_metadata") or {}):
        update_body["app_metadata"] = app_metadata

    if update_body:
        raw_response = await _request_admin(
            "PUT",
            f"/admin/users/{user_id}",
            json=update_body,
        )
        raw_user = _normalize_auth_user_payload(raw_response)
    else:
        raw_user = current

    profile = await upsert_profile(
        db,
        user_id,
        username=payload.username if "username" in fields_set else _UNSET,
        display_name=payload.display_name if "display_name" in fields_set else _UNSET,
        avatar_url=payload.avatar_url if "avatar_url" in fields_set else _UNSET,
        onboarding_completed=payload.onboarding_completed
        if "onboarding_completed" in fields_set
        else _UNSET,
    )
    return await build_account_user(
        db,
        raw_user,
        profile=profile,
        relation_counts=await get_relation_counts(db, user_id),
    )


async def assert_username_available(
    db: AsyncSession,
    username: str | None,
    *,
    user_id: uuid.UUID | None = None,
) -> None:
    normalized_username = normalize_username(username)
    if normalized_username is None:
        return

    query = select(Profile).where(Profile.normalized_username == normalized_username)
    if user_id is not None:
        query = query.where(Profile.id != user_id)
    result = await db.execute(query)
    if result.scalars().first() is not None:
        raise ValueError("Username sudah dipakai user lain.")


async def upsert_profile(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    username: Any = _UNSET,
    display_name: Any = _UNSET,
    avatar_url: Any = _UNSET,
    onboarding_completed: Any = _UNSET,
) -> Profile:
    result = await db.execute(select(Profile).where(Profile.id == user_id))
    profile = result.scalars().first()

    if profile is None:
        profile = Profile(id=user_id)
        db.add(profile)

    if username is not _UNSET:
        normalized_username = normalize_username(username)
        await assert_username_available(db, username, user_id=user_id)
        profile.username = username
        profile.normalized_username = normalized_username

    if display_name is not _UNSET:
        profile.display_name = display_name

    if avatar_url is not _UNSET:
        profile.avatar_url = avatar_url

    if onboarding_completed is not _UNSET:
        profile.onboarding_completed = onboarding_completed

    profile.updated_at = _utcnow()
    await db.commit()
    await db.refresh(profile)
    return profile


async def ensure_reader_preference(db: AsyncSession, user_id: uuid.UUID) -> None:
    result = await db.execute(
        select(ReaderPreference).where(ReaderPreference.user_id == user_id),
    )
    if result.scalars().first() is not None:
        return
    db.add(ReaderPreference(user_id=user_id))
    await db.commit()


async def get_relation_preview(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    limit: int = 5,
) -> AccountRelationPreview:
    def chapter_label(row: Any) -> str | None:
        chapter = getattr(row, "chapter", None)
        if chapter is None:
            return None
        title = getattr(chapter, "title", None)
        number = getattr(chapter, "chapter_number", None)
        if title:
            return title
        if number is not None:
            return f"Chapter {number:g}"
        return None

    def comic_title(row: Any) -> str | None:
        comic = getattr(row, "comic", None)
        return getattr(comic, "title", None) if comic is not None else None

    def preview_title(row: Any, table: str, title_attr: str) -> str:
        if table == "reader_preferences":
            return "Preferensi reader"
        if table == "user_reading_stats":
            return "Statistik membaca"
        if table in {
            "user_bookmarks",
            "user_progress",
            "user_completed_chapters",
            "user_history_entries",
            "user_favorite_scenes",
            "user_download_entries",
        }:
            return comic_title(row) or tableLabelFallback(table)
        return str(getattr(row, title_attr, tableLabelFallback(table)))

    def preview_meta(row: Any, table: str) -> str | None:
        if table == "reader_preferences":
            mode = getattr(row, "default_reading_mode", None) or "mode default"
            direction = getattr(row, "reading_direction", None) or "arah default"
            mark_read = (
                "mark read aktif"
                if getattr(row, "mark_read_on_complete", False)
                else "mark read nonaktif"
            )
            binge_mode = (
                "binge mode aktif"
                if getattr(row, "default_binge_mode", False)
                else "binge mode nonaktif"
            )
            return f"{mode} • {direction.upper()} • {mark_read} • {binge_mode}"
        if table == "user_reading_stats":
            seconds = int(getattr(row, "total_reading_seconds", 0) or 0)
            minutes = max(0, round(seconds / 60))
            return f"{minutes} menit total membaca"
        if table in {"user_progress", "user_history_entries"}:
            chapter = chapter_label(row)
            completed = "Selesai" if getattr(row, "is_completed", False) else "Belum selesai"
            return f"{chapter or 'Chapter terakhir'} • {completed}"
        if table == "user_completed_chapters":
            chapter = chapter_label(row)
            return f"{chapter or 'Chapter'} • Selesai dibaca"
        if table == "user_bookmarks":
            return "Bookmark komik"
        if table == "user_favorite_scenes":
            chapter = chapter_label(row)
            page = getattr(row, "page_item_index", None)
            return f"{chapter or 'Chapter'} • Halaman {page}" if page is not None else chapter
        if table == "user_download_entries":
            chapter = chapter_label(row)
            status = getattr(row, "status", None) or "pending"
            return f"{chapter or 'Chapter'} • {status}"
        return str(getattr(row, "updated_at", None) or getattr(row, "created_at", None) or "") or None

    def tableLabelFallback(table: str) -> str:
        return table.replace("_", " ").title()

    async def rows(model: Any, criterion: Any, table: str, title_attr: str = "id") -> list[AccountRelationPreviewItem]:
        result = await db.execute(select(model).where(criterion).limit(limit))
        items = []
        for row in result.scalars().all():
            items.append(
                AccountRelationPreviewItem(
                    id=str(getattr(row, "id", user_id)),
                    title=preview_title(row, table, title_attr),
                    meta=preview_meta(row, table),
                    table=table,
                ),
            )
        return items

    collection_ids = select(UserCollection.id).where(UserCollection.user_id == user_id)
    collection_items_result = await db.execute(
        select(UserCollectionComic, UserCollection.name)
        .join(UserCollection, UserCollectionComic.collection_id == UserCollection.id)
        .where(UserCollectionComic.collection_id.in_(collection_ids))
        .limit(limit),
    )
    profile_result = await db.execute(select(Profile).where(Profile.id == user_id).limit(1))
    profiles = [
        AccountRelationPreviewItem(
            id=str(profile.id),
            title=profile.display_name or profile.username or str(profile.id),
            meta=profile.username or "profiles",
            table="profiles",
        )
        for profile in profile_result.scalars().all()
    ]

    return AccountRelationPreview(
        profiles=profiles,
        reader_preferences=await rows(ReaderPreference, ReaderPreference.user_id == user_id, "reader_preferences", "user_id"),
        user_reading_stats=await rows(UserReadingStat, UserReadingStat.user_id == user_id, "user_reading_stats", "user_id"),
        user_bookmarks=await rows(UserBookmark, UserBookmark.user_id == user_id, "user_bookmarks", "comic_id"),
        user_collections=await rows(UserCollection, UserCollection.user_id == user_id, "user_collections", "name"),
        user_collection_comics=[
            AccountRelationPreviewItem(
                id=str(item.id),
                title=comic_title(item) or "Komik koleksi",
                meta=f"Koleksi {collection_name}",
                table="user_collection_comics",
            )
            for item, collection_name in collection_items_result.all()
        ],
        user_progress=await rows(
            UserProgress,
            UserProgress.user_id == user_id,
            "user_progress",
            "comic_id",
        ),
        user_completed_chapters=await rows(
            UserCompletedChapter,
            UserCompletedChapter.user_id == user_id,
            "user_completed_chapters",
            "comic_id",
        ),
        user_history_entries=await rows(
            UserHistoryEntry,
            UserHistoryEntry.user_id == user_id,
            "user_history_entries",
            "comic_id",
        ),
        user_favorite_scenes=await rows(
            UserFavoriteScene,
            UserFavoriteScene.user_id == user_id,
            "user_favorite_scenes",
            "comic_id",
        ),
        user_download_entries=await rows(
            UserDownloadEntry,
            UserDownloadEntry.user_id == user_id,
            "user_download_entries",
            "comic_id",
        ),
    )


async def delete_account_clean(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> AccountDeleteResponse:
    # 1. Fetch counts first (untuk response)
    counts = await get_relation_counts(db, user_id)

    # 2. Hapus dari Supabase Auth TERLEBIH DAHULU (di luar transaksi DB).
    # Ini mencegah transaksi DB terbuka terlalu lama (60s+) yang menyebabkan timeout.
    # Kita sertakan 404 sebagai expected agar jika user sudah tidak ada di Supabase,
    # kita tetap lanjut menghapus record di DB kita.
    try:
        await _request_admin(
            "DELETE",
            f"/admin/users/{user_id}",
            expected_statuses={200, 204, 404},
        )
    except Exception as exc:
        logger.exception(f"Gagal menghapus user dari Supabase Auth: {user_id}")
        # Jika hapus dari Supabase gagal total (bukan 404), kita stop di sini
        # agar tidak menghapus data lokal jika identitas aslinya masih ada.
        raise

    # 3. Hapus data lokal dalam transaksi yang cepat
    try:
        # UserCollectionComic akan terhapus otomatis oleh CASCADE saat UserCollection dihapus,
        # tapi kita bisa hapus manual jika ingin eksplisit. Di sini kita hapus koleksi langsung.
        await db.execute(delete(UserDownloadEntry).where(UserDownloadEntry.user_id == user_id))
        await db.execute(delete(UserFavoriteScene).where(UserFavoriteScene.user_id == user_id))
        await db.execute(delete(UserHistoryEntry).where(UserHistoryEntry.user_id == user_id))
        await db.execute(delete(UserCompletedChapter).where(UserCompletedChapter.user_id == user_id))
        await db.execute(delete(UserProgress).where(UserProgress.user_id == user_id))
        await db.execute(delete(UserBookmark).where(UserBookmark.user_id == user_id))
        await db.execute(delete(UserCollection).where(UserCollection.user_id == user_id))
        await db.execute(delete(UserReadingStat).where(UserReadingStat.user_id == user_id))
        await db.execute(delete(ReaderPreference).where(ReaderPreference.user_id == user_id))
        await db.execute(delete(Profile).where(Profile.id == user_id))

        await db.commit()
    except Exception:
        logger.exception(f"Error saat membersihkan data lokal untuk user {user_id}")
        await db.rollback()
        raise

    return AccountDeleteResponse(
        deleted_user_id=user_id,
        relation_counts=counts,
        relation_total=counts.total,
    )
