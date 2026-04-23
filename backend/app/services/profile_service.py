"""
Service layer untuk public profiles.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Profile
from app.schemas import ProfileResponse, ProfileUpdateRequest


def _utcnow() -> datetime:
    return datetime.now(UTC)


def normalize_username(username: str | None) -> str | None:
    if username is None:
        return None
    normalized = "_".join(username.replace("-", "_").split()).strip("_").lower()
    return normalized or None


def build_profile_response(profile: Profile) -> ProfileResponse:
    return ProfileResponse(
        id=profile.id,
        username=profile.username,
        display_name=profile.display_name,
        avatar_url=profile.avatar_url,
        onboarding_completed=profile.onboarding_completed,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


async def get_profile(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> Profile | None:
    result = await db.execute(
        select(Profile).where(Profile.id == user_id)
    )
    return result.scalars().first()


async def ensure_profile_for_auth_user(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    user_metadata: dict[str, Any] | None = None,
) -> Profile:
    """
    Buat profile default bila belum ada.

    Dipakai sebagai fallback bila trigger Supabase belum aktif atau backend
    berjalan di environment non-Supabase murni.
    """
    profile = await get_profile(db, user_id)
    if profile is not None:
        return profile

    user_metadata = user_metadata or {}
    display_name = (
        user_metadata.get("display_name")
        or user_metadata.get("full_name")
        or user_metadata.get("name")
    )
    username = normalize_username(user_metadata.get("username"))

    profile = Profile(
        id=user_id,
        username=username,
        normalized_username=username,
        display_name=display_name,
    )
    db.add(profile)
    await db.commit()
    await db.refresh(profile)
    return profile


async def get_or_create_profile(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    user_metadata: dict[str, Any] | None = None,
) -> Profile:
    profile = await get_profile(db, user_id)
    if profile is not None:
        return profile
    return await ensure_profile_for_auth_user(
        db,
        user_id,
        user_metadata=user_metadata,
    )


async def update_profile(
    db: AsyncSession,
    user_id: uuid.UUID,
    payload: ProfileUpdateRequest,
) -> Profile:
    profile = await get_or_create_profile(db, user_id)

    if payload.username is not None:
        normalized_username = normalize_username(payload.username)
        if normalized_username is None:
            profile.username = None
            profile.normalized_username = None
        else:
            existing = await db.execute(
                select(Profile).where(
                    Profile.normalized_username == normalized_username,
                    Profile.id != user_id,
                )
            )
            if existing.scalars().first() is not None:
                raise ValueError("Username sudah dipakai user lain.")
            profile.username = payload.username
            profile.normalized_username = normalized_username

    if payload.display_name is not None:
        profile.display_name = payload.display_name

    if payload.avatar_url is not None:
        profile.avatar_url = payload.avatar_url

    if payload.onboarding_completed is not None:
        profile.onboarding_completed = payload.onboarding_completed

    profile.updated_at = _utcnow()
    await db.commit()
    await db.refresh(profile)
    return profile
