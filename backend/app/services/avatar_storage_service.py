"""
Avatar image optimization and Supabase Storage upload helpers.
"""

from __future__ import annotations

from io import BytesIO
from time import time_ns
from uuid import UUID

import httpx
from PIL import Image, UnidentifiedImageError

from app.config import settings
from app.services.http_client_service import get_shared_http_client


MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_AVATAR_BYTES = 260 * 1024
AVATAR_SIZE = 512
UPLOAD_MAX_ATTEMPTS = 3


class AvatarStorageError(RuntimeError):
    """Raised when avatar validation, optimization, or upload fails."""

    def __init__(self, message: str, *, status_code: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def _strip_trailing_slash(value: str) -> str:
    return value.rstrip("/")


def _public_storage_url(bucket: str, object_path: str) -> str:
    base = _strip_trailing_slash(settings.SUPABASE_URL)
    return f"{base}/storage/v1/object/public/{bucket}/{object_path}"


def _require_storage_config() -> str:
    missing = []
    if not settings.SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not settings.SUPABASE_SERVICE_ROLE_KEY:
        missing.append("SUPABASE_SERVICE_ROLE_KEY")
    if not settings.SUPABASE_AVATAR_BUCKET:
        missing.append("SUPABASE_AVATAR_BUCKET")
    if missing:
        raise AvatarStorageError(
            f"Konfigurasi upload avatar belum lengkap: {', '.join(missing)}.",
            status_code=500,
        )
    return settings.SUPABASE_AVATAR_BUCKET


def optimize_avatar_image(content: bytes) -> bytes:
    if not content:
        raise AvatarStorageError("File avatar kosong.")
    if len(content) > MAX_UPLOAD_BYTES:
        raise AvatarStorageError("Ukuran avatar maksimal 5 MB.")

    try:
        with Image.open(BytesIO(content)) as image:
            if getattr(image, "is_animated", False):
                image.seek(0)
            image = image.convert("RGBA")

            side = min(image.width, image.height)
            left = max(0, (image.width - side) // 2)
            top = max(0, (image.height - side) // 2)
            image = image.crop((left, top, left + side, top + side))
            if image.width > AVATAR_SIZE:
                image = image.resize(
                    (AVATAR_SIZE, AVATAR_SIZE),
                    Image.Resampling.LANCZOS,
                )

            working = image
            quality = 82
            data = b""
            while True:
                for current_quality in range(quality, 44, -8):
                    buffer = BytesIO()
                    working.save(
                        buffer,
                        format="WEBP",
                        quality=current_quality,
                        method=6,
                    )
                    data = buffer.getvalue()
                    if len(data) <= MAX_AVATAR_BYTES:
                        return data

                if working.width <= 320:
                    return data
                next_size = max(320, int(working.width * 0.85))
                working = working.resize(
                    (next_size, next_size),
                    Image.Resampling.LANCZOS,
                )
                quality = 74
    except UnidentifiedImageError as exc:
        raise AvatarStorageError("Format gambar avatar tidak didukung.") from exc


async def upload_avatar(*, user_id: UUID, content: bytes) -> str:
    bucket = _require_storage_config()
    optimized = optimize_avatar_image(content)
    version = time_ns()
    object_path = f"profiles/{user_id}/avatar.webp"
    storage_base = f"{_strip_trailing_slash(settings.SUPABASE_URL)}/storage/v1/object"
    upload_url = f"{storage_base}/{bucket}/{object_path}"
    headers = {
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "image/webp",
        "Cache-Control": "31536000",
        "x-upsert": "true",
    }

    client = get_shared_http_client()
    for attempt in range(UPLOAD_MAX_ATTEMPTS):
        try:
            response = await client.put(
                upload_url,
                content=optimized,
                headers=headers,
                timeout=30.0,
            )
        except httpx.RequestError as exc:
            if attempt < UPLOAD_MAX_ATTEMPTS - 1:
                continue
            raise AvatarStorageError(
                "Upload avatar ke storage gagal.",
                status_code=502,
            ) from exc

        if response.status_code in {200, 201}:
            return f"{_public_storage_url(bucket, object_path)}?v={version}"

        retryable = response.status_code in {429, 500, 502, 503, 504}
        if retryable and attempt < UPLOAD_MAX_ATTEMPTS - 1:
            continue

        message = (
            f"Upload avatar gagal status={response.status_code}: "
            f"{response.text[:200]}"
        )
        raise AvatarStorageError(
            message,
            status_code=502,
        )

    raise AvatarStorageError("Upload avatar ke storage gagal.", status_code=502)
