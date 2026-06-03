"""
Push notification API routes.
"""

from __future__ import annotations

import secrets

from fastapi import APIRouter, Depends, Header, Response, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import bearer_scheme, get_current_auth_user
from app.api.errors import raise_api_error
from app.config import settings
from app.database import get_db
from app.schemas import (
    AdminAnnouncementRequest,
    AdminAnnouncementResponse,
    AuthenticatedUser,
    ChapterUpdateEventRequest,
    ChapterUpdateEventResponse,
    PushDeviceRegisterRequest,
    PushDeviceResponse,
    PushDeviceUnregisterRequest,
)
from app.services.auth_service import AuthValidationError, validate_supabase_jwt
from app.services.push_notification_service import (
    build_push_device_response,
    handle_admin_announcement,
    handle_chapter_update_event,
    register_push_device,
    unregister_push_device,
)
from app.api.v1.account_manager import require_account_manager_admin

router = APIRouter()


def _csv_settings(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def _metadata_has_admin_role(metadata: dict | None) -> bool:
    metadata = metadata or {}
    role_values = {
        metadata.get("role"),
        metadata.get("account_role"),
        metadata.get("admin_role"),
    }
    return any(
        str(value).lower() in {"admin", "owner", "superadmin"}
        for value in role_values
        if value
    )


def _is_admin_user(auth_user: AuthenticatedUser) -> bool:
    if str(auth_user.user_id) in _csv_settings(settings.ADMIN_USER_IDS):
        return True

    claims = auth_user.raw_claims or {}
    return _metadata_has_admin_role(
        claims.get("app_metadata"),
    ) or _metadata_has_admin_role(
        claims.get("user_metadata"),
    )


async def require_push_event_access(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    x_push_event_key: str | None = Header(default=None, alias="X-Push-Event-Key"),
) -> None:
    """Allow scraper/service events through API key or admin bearer token."""
    expected_key = settings.PUSH_EVENT_API_KEY.strip()
    if expected_key and x_push_event_key:
        if secrets.compare_digest(expected_key, x_push_event_key.strip()):
            return

    if credentials and credentials.scheme.lower() == "bearer":
        try:
            auth_user = await validate_supabase_jwt(credentials.credentials)
        except AuthValidationError as exc:
            raise_api_error(status.HTTP_401_UNAUTHORIZED, str(exc))
        if _is_admin_user(auth_user):
            return
        raise_api_error(
            status.HTTP_403_FORBIDDEN,
            "Akun ini tidak memiliki akses push notification event.",
            code="push_event_forbidden",
        )

    raise_api_error(
        status.HTTP_401_UNAUTHORIZED,
        "Push event API key atau admin bearer token wajib diisi.",
        code="push_event_auth_required",
    )


@router.post("/devices", response_model=PushDeviceResponse)
async def register_device(
    payload: PushDeviceRegisterRequest,
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Register or refresh an authenticated user's Android FCM token."""
    try:
        device = await register_push_device(db, auth_user.user_id, payload)
    except ValueError as exc:
        raise_api_error(
            status.HTTP_403_FORBIDDEN,
            str(exc),
            code="push_device_user_mismatch",
        )
    return build_push_device_response(device)


@router.delete("/devices", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(
    payload: PushDeviceUnregisterRequest,
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate an authenticated user's Android FCM token."""
    await unregister_push_device(db, auth_user.user_id, payload)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/events/chapter-update",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=ChapterUpdateEventResponse,
)
async def chapter_update_event(
    payload: ChapterUpdateEventRequest,
    _: None = Depends(require_push_event_access),
    db: AsyncSession = Depends(get_db),
):
    """Record a chapter update event and deliver FCM notifications."""
    return await handle_chapter_update_event(db, payload)


@router.post(
    "/admin-announcements",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=AdminAnnouncementResponse,
)
async def admin_announcement(
    payload: AdminAnnouncementRequest,
    auth_user: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Broadcast an admin announcement through FCM to active Android devices."""
    return await handle_admin_announcement(
        db,
        payload,
        sender_user_id=auth_user.user_id,
    )
