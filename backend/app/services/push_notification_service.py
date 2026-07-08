"""
Service layer for push notification devices, events, and FCM delivery.
"""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

import httpx
import jwt
from sqlalchemy import distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import BACKEND_DIR, settings
from app.models import (
    Comic,
    Profile,
    PushNotificationEvent,
    UserBookmark,
    UserPushDevice,
)
from app.schemas import (
    AdminAnnouncementRequest,
    AdminAnnouncementResponse,
    ChapterUpdateEventRequest,
    ChapterUpdateEventResponse,
    PushDeviceRegisterRequest,
    PushDeviceResponse,
    PushDeviceUnregisterRequest,
)
from app.services.http_client_service import get_shared_http_client
from app.services.profile_service import get_or_create_profile

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"

_access_token: str | None = None
_access_token_expires_at: datetime | None = None


class PushNotificationConfigurationError(RuntimeError):
    """Raised when FCM credentials are not configured."""


def _utcnow() -> datetime:
    return datetime.now(UTC)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _chapter_label(value: float) -> str:
    return str(int(value)) if value == int(value) else str(value)


def build_push_device_response(device: UserPushDevice) -> PushDeviceResponse:
    return PushDeviceResponse(
        id=device.id,
        provider=device.provider,
        platform=device.platform,
        token_hash=device.token_hash,
        active=device.active,
        created_at=device.created_at,
        updated_at=device.updated_at,
        last_seen_at=device.last_seen_at,
    )


async def register_push_device(
    db: AsyncSession,
    user_id: UUID,
    payload: PushDeviceRegisterRequest,
) -> UserPushDevice:
    """Upsert an authenticated user's FCM device token."""
    if payload.user_id != user_id:
        raise ValueError("user_id tidak sesuai dengan bearer token.")

    await get_or_create_profile(db, user_id)

    token_hash = _token_hash(payload.token)
    now = _utcnow()
    result = await db.execute(
        select(UserPushDevice).where(
            UserPushDevice.provider == payload.provider,
            UserPushDevice.token_hash == token_hash,
        )
    )
    device = result.scalars().first()
    if device is None:
        device = UserPushDevice(
            user_id=user_id,
            provider=payload.provider,
            platform=payload.platform,
            token=payload.token,
            token_hash=token_hash,
            active=True,
            last_seen_at=now,
        )
        db.add(device)
    else:
        device.user_id = user_id
        device.platform = payload.platform
        device.token = payload.token
        device.active = True
        device.updated_at = now
        device.last_seen_at = now

    await db.commit()
    await db.refresh(device)
    return device


async def unregister_push_device(
    db: AsyncSession,
    user_id: UUID,
    payload: PushDeviceUnregisterRequest,
) -> None:
    """Deactivate a token for the current user. Idempotent by design."""
    token_hash = _token_hash(payload.token)
    result = await db.execute(
        select(UserPushDevice).where(
            UserPushDevice.provider == payload.provider,
            UserPushDevice.platform == payload.platform,
            UserPushDevice.token_hash == token_hash,
            UserPushDevice.user_id == user_id,
        )
    )
    device = result.scalars().first()
    if device is None:
        return

    device.active = False
    device.updated_at = _utcnow()
    await db.commit()


async def handle_chapter_update_event(
    db: AsyncSession,
    payload: ChapterUpdateEventRequest,
) -> ChapterUpdateEventResponse:
    """Record a chapter update and notify active devices of bookmarked users."""
    comic_id = await _resolve_chapter_event_comic_id(db, payload)
    existing = await db.execute(
        select(PushNotificationEvent).where(
            PushNotificationEvent.event_id == payload.event_id
        )
    )
    if existing.scalars().first() is not None:
        counts = await _chapter_target_counts(db, comic_id)
        return ChapterUpdateEventResponse(
            event_id=payload.event_id,
            matched_users=counts[0],
            target_devices=counts[1],
            queued_messages=0,
            duplicate=True,
        )

    devices = await _list_chapter_target_devices(db, comic_id)
    matched_users = len({device.user_id for device in devices})
    event = PushNotificationEvent(
        event_id=payload.event_id,
        kind="chapter_update",
        source_name=payload.source_name,
        comic_slug=payload.comic_slug,
        chapter_number=payload.latest_chapter_number,
        payload=payload.model_dump(mode="json"),
    )
    db.add(event)
    await db.commit()

    queued_messages = await _send_chapter_update_to_devices(db, payload, devices)
    return ChapterUpdateEventResponse(
        event_id=payload.event_id,
        matched_users=matched_users,
        target_devices=len(devices),
        queued_messages=queued_messages,
        duplicate=False,
    )


async def handle_admin_announcement(
    db: AsyncSession,
    payload: AdminAnnouncementRequest,
    *,
    sender_user_id: UUID,
) -> AdminAnnouncementResponse:
    """Record and broadcast an admin-created FCM announcement."""
    event_id = payload.event_id or f"admin:{uuid4()}"
    existing = await db.execute(
        select(PushNotificationEvent).where(
            PushNotificationEvent.event_id == event_id
        )
    )
    if existing.scalars().first() is not None:
        counts = await _broadcast_target_counts(db)
        return AdminAnnouncementResponse(
            event_id=event_id,
            matched_users=counts[0],
            target_devices=counts[1],
            queued_messages=0,
            failed_messages=0,
            duplicate=True,
        )

    devices = await _list_broadcast_target_devices(db)
    matched_users = len({device.user_id for device in devices})
    event = PushNotificationEvent(
        event_id=event_id,
        kind="admin_announcement",
        payload={
            **payload.model_dump(mode="json"),
            "event_id": event_id,
            "sender_user_id": str(sender_user_id),
        },
    )
    db.add(event)
    await db.commit()

    queued_messages, failed_messages = await _send_admin_announcement_to_devices(
        db,
        payload,
        devices,
        event_id=event_id,
    )
    event.payload = {
        **(event.payload or {}),
        "delivery": {
            "target_devices": len(devices),
            "queued_messages": queued_messages,
            "failed_messages": failed_messages,
        },
    }
    await db.commit()
    return AdminAnnouncementResponse(
        event_id=event_id,
        matched_users=matched_users,
        target_devices=len(devices),
        queued_messages=queued_messages,
        failed_messages=failed_messages,
        duplicate=False,
    )


async def _resolve_chapter_event_comic_id(
    db: AsyncSession,
    payload: ChapterUpdateEventRequest,
) -> int | None:
    statement = select(Comic.id).where(
        Comic.source_name == payload.source_name,
        Comic.slug == payload.comic_slug,
    )
    if payload.comic_id is not None:
        statement = statement.where(Comic.id == payload.comic_id)

    result = await db.execute(statement)
    return result.scalar_one_or_none()


def _chapter_target_device_statement(comic_id: int):
    return (
        select(UserPushDevice)
        .join(Profile, Profile.id == UserPushDevice.user_id)
        .join(UserBookmark, UserBookmark.user_id == UserPushDevice.user_id)
        .where(
            UserBookmark.comic_id == comic_id,
            UserPushDevice.provider == "fcm",
            UserPushDevice.platform == "android",
            UserPushDevice.active.is_(True),
            Profile.push_notifications_enabled.is_(True),
        )
    )


async def _chapter_target_counts(
    db: AsyncSession,
    comic_id: int | None,
) -> tuple[int, int]:
    if comic_id is None:
        return 0, 0

    target_devices = _chapter_target_device_statement(comic_id).subquery()
    result = await db.execute(
        select(
            func.count(distinct(target_devices.c.user_id)),
            func.count(target_devices.c.id),
        )
    )
    row = result.one()
    return int(row[0] or 0), int(row[1] or 0)


async def _list_chapter_target_devices(
    db: AsyncSession,
    comic_id: int | None,
) -> list[UserPushDevice]:
    if comic_id is None:
        logger.warning(
            "Chapter push target comic not found; event will be recorded without delivery."
        )
        return []

    result = await db.execute(_chapter_target_device_statement(comic_id))
    return list(result.scalars().all())


async def _broadcast_target_counts(db: AsyncSession) -> tuple[int, int]:
    target_devices = _broadcast_target_device_statement().subquery()
    result = await db.execute(
        select(
            func.count(distinct(target_devices.c.user_id)),
            func.count(target_devices.c.id),
        )
    )
    row = result.one()
    return int(row[0] or 0), int(row[1] or 0)


def _broadcast_target_device_statement():
    return (
        select(UserPushDevice)
        .join(Profile, Profile.id == UserPushDevice.user_id)
        .where(
            UserPushDevice.provider == "fcm",
            UserPushDevice.platform == "android",
            UserPushDevice.active.is_(True),
            Profile.push_notifications_enabled.is_(True),
        )
    )


async def _list_broadcast_target_devices(db: AsyncSession) -> list[UserPushDevice]:
    result = await db.execute(_broadcast_target_device_statement())
    return list(result.scalars().all())


async def _send_chapter_update_to_devices(
    db: AsyncSession,
    payload: ChapterUpdateEventRequest,
    devices: list[UserPushDevice],
) -> int:
    if not devices:
        return 0

    try:
        sender = FcmHttpV1Sender()
    except PushNotificationConfigurationError as exc:
        logger.warning(
            "FCM is not configured; push event recorded without delivery: %s",
            exc,
        )
        return 0

    title = "Chapter baru tersedia"
    chapter = _chapter_label(payload.latest_chapter_number)
    body = f"{payload.comic_title} Chapter {chapter} baru saja rilis."
    route = f"/comic/{payload.source_name}/{payload.comic_slug}"
    data = {
        "id": payload.event_id,
        "kind": "chapter_update",
        "category": "Update",
        "route": route,
        "source_name": payload.source_name,
        "comic_slug": payload.comic_slug,
        "chapter_number": chapter,
    }

    queued = 0
    for device in devices:
        try:
            await sender.send(token=device.token, title=title, body=body, data=data)
            queued += 1
        except FcmInvalidTokenError:
            device.active = False
            device.updated_at = _utcnow()
        except Exception as exc:  # noqa: BLE001
            logger.warning("FCM delivery failed for device %s: %s", device.id, exc)

    await db.commit()
    return queued


async def _send_admin_announcement_to_devices(
    db: AsyncSession,
    payload: AdminAnnouncementRequest,
    devices: list[UserPushDevice],
    *,
    event_id: str,
) -> tuple[int, int]:
    if not devices:
        return 0, 0

    try:
        sender = FcmHttpV1Sender()
    except PushNotificationConfigurationError as exc:
        logger.warning(
            "FCM is not configured; admin announcement recorded without delivery: %s",
            exc,
        )
        return 0, len(devices)

    data = {
        "id": event_id,
        "kind": "admin_announcement",
        "category": payload.category,
        "route": payload.action_route or "/notifications",
    }

    queued = 0
    failed = 0
    for device in devices:
        try:
            await sender.send(
                token=device.token,
                title=payload.title,
                body=payload.message,
                data=data,
            )
            queued += 1
        except FcmInvalidTokenError:
            device.active = False
            device.updated_at = _utcnow()
            failed += 1
        except Exception as exc:  # noqa: BLE001
            failed += 1
            logger.warning(
                "Admin announcement FCM delivery failed for device %s: %s",
                device.id,
                exc,
            )

    await db.commit()
    return queued, failed


class FcmInvalidTokenError(RuntimeError):
    """Raised when FCM reports a registration token can no longer be used."""


class FcmHttpV1Sender:
    """Minimal Firebase Cloud Messaging HTTP v1 sender using service account JWT."""

    def __init__(self) -> None:
        self._service_account = _load_service_account()
        self._project_id = settings.FCM_PROJECT_ID or self._service_account.get(
            "project_id",
            "",
        )
        if not self._project_id:
            raise PushNotificationConfigurationError(
                "FCM_PROJECT_ID belum dikonfigurasi.",
            )

    async def send(
        self,
        *,
        token: str,
        title: str,
        body: str,
        data: dict[str, str],
    ) -> None:
        access_token = await _get_fcm_access_token(self._service_account)
        response = await get_shared_http_client().post(
            (
                "https://fcm.googleapis.com/v1/projects/"
                f"{self._project_id}/messages:send"
            ),
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": data,
                    "android": {
                        "priority": "HIGH",
                        "notification": {
                            "channel_id": "comic_updates",
                            "click_action": "FLUTTER_NOTIFICATION_CLICK",
                        },
                    },
                }
            },
        )
        if response.status_code < 400:
            return

        if _is_invalid_fcm_token(response):
            raise FcmInvalidTokenError(response.text)
        response.raise_for_status()


def _load_service_account() -> dict[str, Any]:
    raw_json = settings.FCM_SERVICE_ACCOUNT_JSON.strip()
    if raw_json:
        try:
            return json.loads(raw_json)
        except json.JSONDecodeError as exc:
            raise PushNotificationConfigurationError(
                "FCM_SERVICE_ACCOUNT_JSON bukan JSON valid.",
            ) from exc

    file_path = settings.FCM_SERVICE_ACCOUNT_FILE.strip()
    if file_path:
        path = Path(file_path)
        candidate_paths = [path]
        if not path.is_absolute():
            candidate_paths.extend([BACKEND_DIR / path, BACKEND_DIR.parent / path])

        try:
            for candidate_path in candidate_paths:
                if candidate_path.exists():
                    return json.loads(candidate_path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise PushNotificationConfigurationError(
                "FCM_SERVICE_ACCOUNT_FILE tidak dapat dibaca.",
            ) from exc
        except json.JSONDecodeError as exc:
            raise PushNotificationConfigurationError(
                "FCM_SERVICE_ACCOUNT_FILE bukan JSON valid.",
            ) from exc

        raise PushNotificationConfigurationError(
            "FCM_SERVICE_ACCOUNT_FILE tidak dapat ditemukan.",
        )

    raise PushNotificationConfigurationError(
        "FCM_SERVICE_ACCOUNT_JSON atau FCM_SERVICE_ACCOUNT_FILE belum dikonfigurasi.",
    )


async def _get_fcm_access_token(service_account: dict[str, Any]) -> str:
    global _access_token, _access_token_expires_at

    now = _utcnow()
    if (
        _access_token
        and _access_token_expires_at
        and _access_token_expires_at > now
    ):
        return _access_token

    client_email = service_account.get("client_email")
    private_key = service_account.get("private_key")
    if not client_email or not private_key:
        raise PushNotificationConfigurationError(
            "Service account FCM harus memiliki client_email dan private_key.",
        )

    issued_at = int(now.timestamp())
    assertion = jwt.encode(
        {
            "iss": client_email,
            "scope": FCM_SCOPE,
            "aud": GOOGLE_OAUTH_TOKEN_URL,
            "iat": issued_at,
            "exp": issued_at + 3600,
        },
        private_key,
        algorithm="RS256",
    )
    response = await get_shared_http_client().post(
        GOOGLE_OAUTH_TOKEN_URL,
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        },
    )
    response.raise_for_status()
    payload = response.json()
    access_token = payload.get("access_token")
    expires_in = int(payload.get("expires_in") or 3600)
    if not access_token:
        raise PushNotificationConfigurationError(
            "Google OAuth tidak mengembalikan access_token.",
        )

    _access_token = access_token
    _access_token_expires_at = now + timedelta(seconds=max(60, expires_in - 120))
    return access_token


def _is_invalid_fcm_token(response: httpx.Response) -> bool:
    try:
        payload = response.json()
    except ValueError:
        return False

    status_value = payload.get("error", {}).get("status")
    if status_value == "NOT_FOUND":
        return True
    if status_value == "INVALID_ARGUMENT":
        response_text = response.text.lower()
        return "registration token" in response_text or "token" in response_text
    return "UNREGISTERED" in response.text
