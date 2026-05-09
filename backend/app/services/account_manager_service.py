"""
Service layer untuk dashboard account manager.

Operasi Supabase Auth Admin sengaja ditempatkan di backend agar service role key
tidak pernah bocor ke HTML/JavaScript browser.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import httpx
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_supabase_auth_base_url, settings
from app.models import (
    Profile,
    ReaderPreference,
    UserBookmark,
    UserCollection,
    UserCollectionComic,
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

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.request(
            method,
            f"{auth_base}{path}",
            headers=_admin_headers(),
            json=json,
            params=params,
        )

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


async def _count_where(db: AsyncSession, model: Any, criterion: Any) -> int:
    result = await db.execute(select(func.count()).select_from(model).where(criterion))
    return int(result.scalar_one() or 0)


async def get_relation_counts(db: AsyncSession, user_id: uuid.UUID) -> AccountRelationCounts:
    collection_ids = select(UserCollection.id).where(UserCollection.user_id == user_id)
    collection_items = await db.execute(
        select(func.count())
        .select_from(UserCollectionComic)
        .where(UserCollectionComic.collection_id.in_(collection_ids)),
    )

    return AccountRelationCounts(
        profiles=await _count_where(db, Profile, Profile.id == user_id),
        reader_preferences=await _count_where(db, ReaderPreference, ReaderPreference.user_id == user_id),
        user_reading_stats=await _count_where(db, UserReadingStat, UserReadingStat.user_id == user_id),
        user_bookmarks=await _count_where(db, UserBookmark, UserBookmark.user_id == user_id),
        user_collections=await _count_where(db, UserCollection, UserCollection.user_id == user_id),
        user_collection_comics=int(collection_items.scalar_one() or 0),
        user_progress=await _count_where(db, UserProgress, UserProgress.user_id == user_id),
        user_history_entries=await _count_where(db, UserHistoryEntry, UserHistoryEntry.user_id == user_id),
        user_favorite_scenes=await _count_where(db, UserFavoriteScene, UserFavoriteScene.user_id == user_id),
        user_download_entries=await _count_where(db, UserDownloadEntry, UserDownloadEntry.user_id == user_id),
    )


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
) -> AccountManagerUser:
    user_id = uuid.UUID(str(raw_user["id"]))
    app_metadata = raw_user.get("app_metadata") or {}
    user_metadata = raw_user.get("user_metadata") or {}
    counts = await get_relation_counts(db, user_id)
    account_role = _metadata_role(app_metadata, _metadata_role(user_metadata, "reader"))

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
    users = [
        await build_account_user(db, raw_user, profile=profiles.get(uuid.UUID(str(raw_user["id"]))))
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
    return await build_account_user(db, raw_user, profile=profile)


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
    return await build_account_user(db, raw_user, profile=profile)


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
    async def rows(model: Any, criterion: Any, table: str, title_attr: str = "id") -> list[AccountRelationPreviewItem]:
        result = await db.execute(select(model).where(criterion).limit(limit))
        items = []
        for row in result.scalars().all():
            title = str(getattr(row, title_attr, getattr(row, "id", "")))
            meta = getattr(row, "status", None) or getattr(row, "updated_at", None) or getattr(row, "created_at", None)
            items.append(
                AccountRelationPreviewItem(
                    id=str(getattr(row, "id", user_id)),
                    title=title,
                    meta=str(meta) if meta is not None else None,
                    table=table,
                ),
            )
        return items

    collection_ids = select(UserCollection.id).where(UserCollection.user_id == user_id)
    collection_items_result = await db.execute(
        select(UserCollectionComic).where(UserCollectionComic.collection_id.in_(collection_ids)).limit(limit),
    )

    return AccountRelationPreview(
        reader_preferences=await rows(ReaderPreference, ReaderPreference.user_id == user_id, "reader_preferences", "user_id"),
        user_reading_stats=await rows(UserReadingStat, UserReadingStat.user_id == user_id, "user_reading_stats", "user_id"),
        user_bookmarks=await rows(UserBookmark, UserBookmark.user_id == user_id, "user_bookmarks", "comic_id"),
        user_collections=await rows(UserCollection, UserCollection.user_id == user_id, "user_collections", "name"),
        user_collection_comics=[
            AccountRelationPreviewItem(
                id=str(item.id),
                title=f"Collection {item.collection_id}",
                meta=f"Comic {item.comic_id}",
                table="user_collection_comics",
            )
            for item in collection_items_result.scalars().all()
        ],
        user_progress=await rows(UserProgress, UserProgress.user_id == user_id, "user_progress", "comic_id"),
        user_history_entries=await rows(UserHistoryEntry, UserHistoryEntry.user_id == user_id, "user_history_entries", "comic_id"),
        user_favorite_scenes=await rows(UserFavoriteScene, UserFavoriteScene.user_id == user_id, "user_favorite_scenes", "comic_id"),
        user_download_entries=await rows(UserDownloadEntry, UserDownloadEntry.user_id == user_id, "user_download_entries", "comic_id"),
    )


async def delete_account_clean(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> AccountDeleteResponse:
    counts = await get_relation_counts(db, user_id)
    await _request_admin(
        "DELETE",
        f"/admin/users/{user_id}",
        expected_statuses={200, 204},
    )

    collection_ids = select(UserCollection.id).where(UserCollection.user_id == user_id)
    await db.execute(delete(UserCollectionComic).where(UserCollectionComic.collection_id.in_(collection_ids)))
    await db.execute(delete(UserDownloadEntry).where(UserDownloadEntry.user_id == user_id))
    await db.execute(delete(UserFavoriteScene).where(UserFavoriteScene.user_id == user_id))
    await db.execute(delete(UserHistoryEntry).where(UserHistoryEntry.user_id == user_id))
    await db.execute(delete(UserProgress).where(UserProgress.user_id == user_id))
    await db.execute(delete(UserBookmark).where(UserBookmark.user_id == user_id))
    await db.execute(delete(UserCollection).where(UserCollection.user_id == user_id))
    await db.execute(delete(UserReadingStat).where(UserReadingStat.user_id == user_id))
    await db.execute(delete(ReaderPreference).where(ReaderPreference.user_id == user_id))
    await db.execute(delete(Profile).where(Profile.id == user_id))
    await db.commit()

    return AccountDeleteResponse(
        deleted_user_id=user_id,
        relation_counts=counts,
        relation_total=counts.total,
    )
