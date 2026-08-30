"""
Tonztoon Komik — Image Service

Utility functions untuk image proxy logic.
Digunakan oleh route /api/v1/images/proxy.
"""

import asyncio
from io import BytesIO
import ipaddress
import logging
import re
import socket
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode, urljoin, urlparse

import httpx
from PIL import Image, ImageFile, ImageOps
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Comic
from app.services.http_client_service import get_image_proxy_http_client

logger = logging.getLogger("service.image")

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

PROXY_IMAGE_PATH = "/api/v1/images/proxy"
KOMIKCAST_API_BASE_URL = "https://be.komikcast.cc"
KOMIKCAST_WEB_BASE_URL = "https://v1.komikcast.fit"
KOMIKCAST_WEB_REFERER = f"{KOMIKCAST_WEB_BASE_URL}/"
KOMIKCAST_IMAGE_HOSTS = (
    "komikcast.fit",
    "komikcast.cc",
    "komikcast.to",
    "imgkc1.my.id",
    "imgkc2.my.id",
    "imgkc3.my.id",
    "imgkc.my.id",
)
KOMIKCAST_COVER_PATH_RE = re.compile(r"^/prod/series/([^/]+)/cover/")
# Some Komiku Asia JPEGs contain large EXIF blocks before the SOF marker.
# Keep the probe bounded, but allow enough of the partial response to reach it.
IMAGE_DIMENSION_PROBE_MAX_BYTES = 512 * 1024
IMAGE_DIMENSION_PROBE_CONCURRENCY = 8
IMAGE_PROXY_ALLOWED_SCHEMES = {"http", "https"}
IMAGE_PROXY_ALLOWED_PORTS = {80, 443}
IMAGE_PROXY_DEFAULT_ALLOWED_HOST_SUFFIXES = (
    "komiku.org",
    "komiku.to",
    "komiku.asia",
    "content.komiku.me",
    "cdnkomiku.xyz",
    "shinigami.asia",
    "shngm.id",
    "api.shngm.io",
    "komikcast.fit",
    "komikcast.cc",
    "komikcast.to",
    "komikcast.cz",
    "komikcast.site",
    "imgkc1.my.id",
    "imgkc2.my.id",
    "imgkc3.my.id",
    "imgkc.my.id",
    "be.komikcast.cc",
    "v1.komikcast.fit",
    "kiryuu.to",
    "kiryuu.id",
    "kiryuu.org",
    "blogspot.com",
    "blogger.googleusercontent.com",
    "googleusercontent.com",
    "yuucdn.com",
    "voratoon.com",
    "voratoon.id",
    "cvr.voratoon.id",
    "cdn.voratoon.com",
    "api.voratoon.com",
    "v1.voratoon.com",
)

# Mapping host suffix -> Referer header yang benar untuk source non-Komikcast.
REFERER_BY_HOST_SUFFIX = {
    "komiku.org": "https://komiku.org/",
    "komiku.to": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "content.komiku.me": "https://01.komiku.asia/",
    "cdnkomiku.xyz": "https://01.komiku.asia/",
    "shinigami.asia": "https://e.shinigami.asia/",
    "shngm.id": "https://e.shinigami.asia/",
    "voratoon.com": "https://v1.voratoon.com/",
    "voratoon.id": "https://v1.voratoon.com/",
}
SCRAPLING_IMAGE_FALLBACK_STATUSES = {
    # Komiku's CDN challenge is commonly returned as 403.
    "cdnkomiku.xyz": frozenset({403}),
    # Voratoon has legacy image paths that can return 404 to httpx while a
    # browser-like request may still resolve the asset.
    "cdn.voratoon.com": frozenset({403, 404}),
}


class ImageProxyValidationError(ValueError):
    """Raised when a proxied image target is not allowed."""


class ImageProxyPayloadTooLargeError(ImageProxyValidationError):
    """Raised when upstream image payload exceeds the configured size cap."""


@dataclass(slots=True)
class ImageProxyFetchResult:
    """Validated upstream image response ready to be streamed."""

    response: httpx.Response
    url: str
    content_type: str


@dataclass(slots=True)
class OptimizedImagePayload:
    """Bytes cover yang sudah diperkecil untuk dikirim ke client."""

    body: bytes
    content_type: str


def build_absolute_url(base_url: str | None, path: str | None) -> str | None:
    """Ubah path API relatif menjadi URL absolut memakai host request."""
    if not path:
        return path

    parsed = urlparse(path)
    if parsed.scheme and parsed.netloc:
        return path

    if not base_url:
        return path

    return f"{base_url.rstrip('/')}/{path.lstrip('/')}"


def is_public_supabase_storage_url(image_url: str) -> bool:
    """Cek apakah URL gambar sudah berupa URL public Supabase Storage."""
    if not settings.SUPABASE_URL:
        return False

    storage_public_prefix = (
        f"{settings.SUPABASE_URL.rstrip('/')}/storage/v1/object/public/"
    )
    return image_url.startswith(storage_public_prefix)


def build_proxy_image_url(
    image_url: str | None,
    base_url: str | None = None,
) -> str | None:
    """
    Bungkus URL gambar asli ke endpoint proxy global FastAPI.

    Jika URL sudah berbentuk endpoint proxy, nilai akan dikembalikan apa adanya.
    """
    if not image_url:
        return image_url

    parsed = urlparse(image_url)
    if image_url.startswith(PROXY_IMAGE_PATH):
        return build_absolute_url(base_url, image_url)

    if parsed.path.endswith(PROXY_IMAGE_PATH):
        return image_url

    if not parsed.scheme or not parsed.netloc:
        return image_url

    if is_public_supabase_storage_url(image_url):
        return image_url

    query_params = {"url": image_url}

    proxy_path = f"{PROXY_IMAGE_PATH}?{urlencode(query_params)}"
    return build_absolute_url(base_url, proxy_path)


def wrap_chapter_image_urls(
    images: list[dict[str, Any]] | None,
    base_url: str | None = None,
) -> list[dict[str, Any]]:
    """
    Bungkus semua field `url` di array gambar chapter ke URL proxy global.
    """
    wrapped_images: list[dict[str, Any]] = []
    for image in images or []:
        wrapped_image = dict(image)
        wrapped_image["url"] = build_proxy_image_url(
            image.get("url"),
            base_url=base_url,
        )
        wrapped_images.append(wrapped_image)
    return wrapped_images


def _host_matches_suffix(host: str, suffix: str) -> bool:
    """True jika host sama dengan suffix atau subdomain dari suffix."""
    host = host.lower()
    suffix = suffix.lower()
    return host == suffix or host.endswith(f".{suffix}")


def _normalize_hostname(host: str | None) -> str:
    if not host:
        raise ImageProxyValidationError("Image URL host is required.")

    try:
        normalized = (
            host.strip()
            .lstrip(".")
            .rstrip(".")
            .encode("idna")
            .decode("ascii")
            .lower()
        )
    except UnicodeError as exc:
        raise ImageProxyValidationError("Image URL host is invalid.") from exc

    if not normalized:
        raise ImageProxyValidationError("Image URL host is required.")
    return normalized


def _configured_image_proxy_host_suffixes() -> tuple[str, ...]:
    configured = [
        value.strip()
        for value in settings.IMAGE_PROXY_ALLOWED_HOSTS.split(",")
        if value.strip()
    ]
    suffixes = {
        _normalize_hostname(suffix)
        for suffix in (*IMAGE_PROXY_DEFAULT_ALLOWED_HOST_SUFFIXES, *configured)
    }
    return tuple(sorted(suffixes))


def get_image_proxy_allowed_host_suffixes() -> tuple[str, ...]:
    """Return built-in source image hosts plus optional env-configured hosts."""
    return _configured_image_proxy_host_suffixes()


def _host_is_allowed_for_image_proxy(host: str) -> bool:
    return any(
        _host_matches_suffix(host, suffix)
        for suffix in get_image_proxy_allowed_host_suffixes()
    )


def _is_blocked_proxy_ip(
    ip_address: ipaddress.IPv4Address | ipaddress.IPv6Address,
) -> bool:
    return (
        not ip_address.is_global
        or ip_address.is_loopback
        or ip_address.is_link_local
        or ip_address.is_private
        or ip_address.is_reserved
        or ip_address.is_multicast
        or ip_address.is_unspecified
    )


def validate_proxy_image_url(image_url: str) -> str:
    """
    Validate URL shape and allowlisted host before the backend fetches it.

    DNS resolution is handled separately so redirects can be validated per-hop.
    """
    cleaned = image_url.strip()
    parsed = urlparse(cleaned)
    if parsed.scheme.lower() not in IMAGE_PROXY_ALLOWED_SCHEMES:
        raise ImageProxyValidationError("Image URL scheme is not allowed.")
    if parsed.username or parsed.password:
        raise ImageProxyValidationError("Image URL credentials are not allowed.")

    host = _normalize_hostname(parsed.hostname)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ImageProxyValidationError("Image URL port is invalid.") from exc
    if port is not None and port not in IMAGE_PROXY_ALLOWED_PORTS:
        raise ImageProxyValidationError("Image URL port is not allowed.")

    try:
        literal_ip = ipaddress.ip_address(host)
    except ValueError:
        literal_ip = None

    if literal_ip is not None and _is_blocked_proxy_ip(literal_ip):
        raise ImageProxyValidationError("Image URL IP address is not public.")
    if not _host_is_allowed_for_image_proxy(host):
        raise ImageProxyValidationError("Image URL host is not allowed.")

    return cleaned


async def validate_proxy_image_dns(image_url: str) -> None:
    """Resolve target host and reject any non-public resolved address."""
    parsed = urlparse(image_url)
    host = _normalize_hostname(parsed.hostname)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ImageProxyValidationError("Image URL port is invalid.") from exc

    try:
        literal_ip = ipaddress.ip_address(host)
    except ValueError:
        literal_ip = None

    if literal_ip is not None:
        if _is_blocked_proxy_ip(literal_ip):
            raise ImageProxyValidationError("Image URL IP address is not public.")
        return

    try:
        infos = await asyncio.to_thread(
            socket.getaddrinfo,
            host,
            port or (443 if parsed.scheme == "https" else 80),
            type=socket.SOCK_STREAM,
        )
    except socket.gaierror as exc:
        raise ImageProxyValidationError("Image URL host cannot be resolved.") from exc

    addresses: set[str] = set()
    for info in infos:
        sockaddr = info[4]
        if not sockaddr:
            continue
        addresses.add(str(sockaddr[0]))

    if not addresses:
        raise ImageProxyValidationError("Image URL host cannot be resolved.")

    for address in addresses:
        try:
            parsed_ip = ipaddress.ip_address(address)
        except ValueError as exc:
            raise ImageProxyValidationError(
                "Image URL resolved to an invalid address."
            ) from exc
        if _is_blocked_proxy_ip(parsed_ip):
            raise ImageProxyValidationError(
                "Image URL resolved to a non-public address."
            )


def is_allowed_image_content_type(content_type: str | None) -> bool:
    if not content_type:
        return False
    media_type = content_type.split(";", 1)[0].strip().lower()
    return media_type.startswith("image/")


def validate_image_response_headers(headers: Mapping[str, str]) -> str:
    """Validate upstream content type and content length before streaming."""
    content_type = headers.get("content-type") or headers.get("Content-Type")
    if not is_allowed_image_content_type(content_type):
        raise ImageProxyValidationError("Image source returned non-image content.")

    content_length = headers.get("content-length") or headers.get("Content-Length")
    if content_length:
        try:
            expected_size = int(content_length)
        except ValueError as exc:
            raise ImageProxyValidationError(
                "Image source returned invalid content length."
            ) from exc
        if expected_size > settings.IMAGE_PROXY_MAX_BYTES:
            raise ImageProxyPayloadTooLargeError(
                "Image source exceeds the configured size limit."
            )

    return content_type or "image/jpeg"


def _is_komikcast_image_host(host: str) -> bool:
    return any(
        _host_matches_suffix(host, suffix)
        for suffix in KOMIKCAST_IMAGE_HOSTS
    )


def _extract_komikcast_cover_slug_from_path(path: str) -> str | None:
    match = KOMIKCAST_COVER_PATH_RE.search(path)
    return match.group(1) if match else None


def _looks_like_komikcast_cover_url(parsed_url) -> bool:
    return _extract_komikcast_cover_slug_from_path(parsed_url.path) is not None


def _referer_for_image_url(image_url: str) -> str:
    parsed = urlparse(image_url)
    try:
        host = _normalize_hostname(parsed.hostname)
    except ImageProxyValidationError:
        host = parsed.netloc.lower()

    if _is_komikcast_image_host(host) or _looks_like_komikcast_cover_url(parsed):
        return KOMIKCAST_WEB_REFERER

    for suffix, referer in REFERER_BY_HOST_SUFFIX.items():
        if _host_matches_suffix(host, suffix):
            return referer

    return f"{parsed.scheme}://{parsed.netloc}/"


def get_proxy_headers(image_url: str) -> dict[str, str]:
    """
    Generate headers yang tepat untuk fetch gambar dari server asli.
    Menentukan Referer berdasarkan domain URL gambar.
    """
    return {
        "Referer": _referer_for_image_url(image_url),
        "User-Agent": DEFAULT_USER_AGENT,
    }


def _should_try_scrapling_image_fallback(image_url: str, status_code: int) -> bool:
    host = _normalize_hostname(urlparse(image_url).hostname)
    return any(
        status_code in statuses and _host_matches_suffix(host, suffix)
        for suffix, statuses in SCRAPLING_IMAGE_FALLBACK_STATUSES.items()
    )


async def _fetch_image_via_scrapling(
    image_url: str,
) -> ImageProxyFetchResult | None:
    """
    Retry protected/legacy CDN images through Scrapling's browser-like headers.

    The fallback is scoped to known source CDNs and only used for their
    configured HTTP statuses.
    """
    try:
        from scrapling.fetchers import Fetcher

        page = await asyncio.to_thread(
            Fetcher.get,
            image_url,
            stealthy_headers=True,
            headers={
                **get_proxy_headers(image_url),
                "Accept": "image/avif,image/webp,image/apng,image/svg+xml,"
                "image/*,*/*;q=0.8",
            },
            timeout=30_000,
        )
    except Exception as exc:
        logger.warning("Scrapling image fallback gagal untuk %s: %s", image_url, exc)
        return None

    status = getattr(page, "status", None)
    if status != 200:
        logger.warning(
            "Scrapling image fallback mendapat status %s untuk %s",
            status,
            image_url,
        )
        return None

    body = getattr(page, "body", b"")
    if not isinstance(body, bytes) or not body:
        logger.warning("Scrapling image fallback mengembalikan body kosong untuk %s", image_url)
        return None
    if len(body) > settings.IMAGE_PROXY_MAX_BYTES:
        raise ImageProxyPayloadTooLargeError(
            "Image source exceeds the configured size limit."
        )

    source_headers = {
        str(key).lower(): str(value)
        for key, value in (getattr(page, "headers", {}) or {}).items()
    }
    content_type = source_headers.get("content-type", "")
    response_headers = {
        "content-type": content_type,
        "content-length": str(len(body)),
    }
    validate_image_response_headers(response_headers)
    response = httpx.Response(
        status_code=200,
        headers=response_headers,
        content=body,
        request=httpx.Request("GET", image_url),
    )
    logger.info("Scrapling image fallback berhasil untuk %s", image_url)
    return ImageProxyFetchResult(
        response=response,
        url=image_url,
        content_type=content_type,
    )


VORATOON_COVER_PATH_RE = re.compile(r"^/prod/series/([^/]+)/cover/")


def _extract_voratoon_cover_slug(url_str: str) -> str | None:
    try:
        parsed = urlparse(url_str)
        if any(h in parsed.netloc for h in ("voratoon", "imgkc", "komikcast")):
            match = VORATOON_COVER_PATH_RE.search(parsed.path)
            if match:
                return match.group(1)
    except Exception:
        pass
    return None


async def _fetch_fresh_voratoon_cover_url(
    client: httpx.AsyncClient,
    slug: str,
) -> str | None:
    try:
        api_url = f"https://api.voratoon.com/series/{slug}?includeMeta=true"
        headers = {
            "User-Agent": DEFAULT_USER_AGENT,
            "Accept": "application/json",
            "Referer": f"https://v1.voratoon.com/series/{slug}",
        }
        res = await client.get(api_url, headers=headers, timeout=10.0)
        if res.status_code == 200:
            payload = res.json()
            item = payload.get("data") or {}
            item_data = item.get("data") or {}
            fresh = item_data.get("coverImage") or item_data.get("cover")
            if fresh and isinstance(fresh, str):
                return fresh.strip()
    except Exception:
        logger.debug("Failed on-demand refresh of cover for slug %s", slug, exc_info=True)
    return None


async def open_validated_image_proxy_response(
    image_url: str,
    *,
    client: httpx.AsyncClient | None = None,
) -> ImageProxyFetchResult:
    """
    Open an upstream image stream after validating URL, DNS, redirects, and headers.
    Auto-refreshes expired presigned S3 cover URLs if upstream returns 403/502.
    """
    active_client = client or get_image_proxy_http_client()
    current_url = validate_proxy_image_url(image_url)
    response: httpx.Response | None = None
    refreshed_on_demand = False

    for redirect_count in range(settings.IMAGE_PROXY_MAX_REDIRECTS + 1):
        await validate_proxy_image_dns(current_url)
        request = active_client.build_request(
            "GET",
            current_url,
            headers=get_proxy_headers(current_url),
        )
        response = await active_client.send(request, stream=True)

        if _should_try_scrapling_image_fallback(current_url, response.status_code):
            scrapling_result = await _fetch_image_via_scrapling(current_url)
            if scrapling_result is not None:
                await response.aclose()
                return scrapling_result

        if response.status_code in {301, 302, 303, 307, 308}:
            location = response.headers.get("location")
            await response.aclose()
            response = None
            if not location:
                raise ImageProxyValidationError(
                    "Image source returned redirect without location."
                )
            if redirect_count >= settings.IMAGE_PROXY_MAX_REDIRECTS:
                raise ImageProxyValidationError("Image source redirect limit exceeded.")
            current_url = validate_proxy_image_url(urljoin(current_url, location))
            continue

        if response.status_code in {403, 502, 503} and not refreshed_on_demand:
            slug = _extract_voratoon_cover_slug(current_url)
            if slug:
                fresh_url = await _fetch_fresh_voratoon_cover_url(active_client, slug)
                if fresh_url and fresh_url != current_url:
                    logger.info(
                        "On-demand refresh expired cover URL for slug '%s' (status %s)",
                        slug,
                        response.status_code,
                    )
                    await response.aclose()
                    refreshed_on_demand = True
                    current_url = validate_proxy_image_url(fresh_url)
                    await validate_proxy_image_dns(current_url)
                    retry_request = active_client.build_request(
                        "GET",
                        current_url,
                        headers=get_proxy_headers(current_url),
                    )
                    response = await active_client.send(retry_request, stream=True)

        if response.status_code == 200:
            try:
                content_type = validate_image_response_headers(response.headers)
            except ImageProxyValidationError:
                await response.aclose()
                raise
        else:
            content_type = response.headers.get(
                "content-type",
                "application/octet-stream",
            )
        return ImageProxyFetchResult(
            response=response,
            url=current_url,
            content_type=content_type,
        )

    raise ImageProxyValidationError("Image source redirect limit exceeded.")


async def stream_image_response_with_limit(
    response: httpx.Response,
):
    """Yield upstream image bytes while enforcing a runtime payload cap."""
    total = 0
    try:
        async for chunk in response.aiter_bytes():
            total += len(chunk)
            if total > settings.IMAGE_PROXY_MAX_BYTES:
                raise ImageProxyPayloadTooLargeError(
                    "Image source exceeds the configured size limit."
                )
            yield chunk
    finally:
        await response.aclose()


def _resize_and_compress_cover(
    body: bytes,
    *,
    max_width: int,
    quality: int,
) -> bytes | None:
    """Resize cover tanpa upscale lalu encode WebP dengan kualitas terkontrol."""
    try:
        with Image.open(BytesIO(body)) as source:
            image = ImageOps.exif_transpose(source)
            if image.width > max_width:
                target_height = max(1, round(image.height * max_width / image.width))
                image = image.resize(
                    (max_width, target_height),
                    Image.Resampling.LANCZOS,
                )

            if image.mode not in {"RGB", "RGBA"}:
                image = image.convert("RGBA" if "A" in image.getbands() else "RGB")

            output = BytesIO()
            image.save(output, format="WEBP", quality=quality, method=4)
            optimized = output.getvalue()
            # Jangan mengganti payload jika source sudah lebih kecil/efisien.
            return optimized if len(optimized) < len(body) else None
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        logger.warning("Cover tidak dapat dioptimalkan, memakai source asli: %s", exc)
        return None


async def optimize_image_response(
    response: httpx.Response,
    *,
    content_type: str,
    max_width: int,
    quality: int,
) -> OptimizedImagePayload:
    """Baca cover, optimalkan di worker thread, lalu tutup upstream response."""
    chunks = [chunk async for chunk in stream_image_response_with_limit(response)]
    body = b"".join(chunks)

    optimized = await asyncio.to_thread(
        _resize_and_compress_cover,
        body,
        max_width=max_width,
        quality=quality,
    )
    if optimized is None:
        return OptimizedImagePayload(body=body, content_type=content_type)
    return OptimizedImagePayload(body=optimized, content_type="image/webp")


def _positive_dimension(value: Any) -> int | None:
    """Normalisasi nilai dimensi tanpa menerima bool atau angka non-positif."""
    if isinstance(value, bool):
        return None
    try:
        dimension = int(value)
    except (TypeError, ValueError):
        return None
    return dimension if dimension > 0 else None


def chapter_image_has_dimensions(image: dict[str, Any]) -> bool:
    """True jika item gambar sudah memiliki dimensi intrinsik yang valid."""
    return (
        _positive_dimension(image.get("width")) is not None
        and _positive_dimension(image.get("height")) is not None
    )


def normalize_chapter_image(image: dict[str, Any]) -> dict[str, Any]:
    """Simpan hanya kontrak JSONB reader dan pertahankan dimensi valid."""
    normalized = {
        "page": image["page"],
        "url": image["url"],
    }
    width = _positive_dimension(image.get("width"))
    height = _positive_dimension(image.get("height"))
    if width is not None and height is not None:
        normalized["width"] = width
        normalized["height"] = height
    return normalized


def _read_little_endian_uint24(data: bytes) -> int:
    return data[0] | (data[1] << 8) | (data[2] << 16)


def _parse_webp_dimensions(data: bytes) -> tuple[int, int] | None:
    """Baca dimensi WebP dari header RIFF tanpa menunggu PIL decode penuh."""
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None

    offset = 12
    while offset + 8 <= len(data):
        chunk_type = data[offset : offset + 4]
        chunk_size = int.from_bytes(data[offset + 4 : offset + 8], "little")
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        chunk_data = data[chunk_start : min(chunk_end, len(data))]
        if chunk_type == b"VP8X" and len(chunk_data) >= 10:
            width = _read_little_endian_uint24(chunk_data[4:7]) + 1
            height = _read_little_endian_uint24(chunk_data[7:10]) + 1
            return (width, height) if width > 0 and height > 0 else None

        if chunk_type == b"VP8L" and len(chunk_data) >= 5 and chunk_data[0] == 0x2F:
            bits = int.from_bytes(chunk_data[1:5], "little")
            width = (bits & 0x3FFF) + 1
            height = ((bits >> 14) & 0x3FFF) + 1
            return (width, height) if width > 0 and height > 0 else None

        if chunk_type == b"VP8 " and len(chunk_data) >= 10:
            frame_header = chunk_data[3:6]
            if frame_header == b"\x9d\x01\x2a":
                width = int.from_bytes(chunk_data[6:8], "little") & 0x3FFF
                height = int.from_bytes(chunk_data[8:10], "little") & 0x3FFF
                return (width, height) if width > 0 and height > 0 else None

        if chunk_end > len(data):
            return None
        offset = chunk_end + (chunk_size % 2)

    return None


def _parse_jpeg_dimensions(data: bytes) -> tuple[int, int] | None:
    """Baca dimensi JPEG dari marker SOF tanpa mendekode payload penuh."""
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None

    # SOF markers that carry JPEG frame dimensions. DHT/DAC and restart
    # markers are intentionally excluded because they do not carry dimensions.
    sof_markers = {
        *range(0xC0, 0xC4),
        *range(0xC5, 0xC8),
        *range(0xC9, 0xCC),
        *range(0xCD, 0xD0),
    }
    offset = 2
    while offset + 1 < len(data):
        if data[offset] != 0xFF:
            return None

        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            return None

        marker = data[offset]
        offset += 1
        if marker in {0xD9, 0xDA}:
            return None
        if marker in {0x01, *range(0xD0, 0xD9)}:
            continue
        if offset + 2 > len(data):
            return None

        segment_length = int.from_bytes(data[offset : offset + 2], "big")
        if segment_length < 2:
            return None
        if marker in sof_markers:
            if offset + 7 > len(data):
                return None
            height = int.from_bytes(data[offset + 3 : offset + 5], "big")
            width = int.from_bytes(data[offset + 5 : offset + 7], "big")
            return (width, height) if width > 0 and height > 0 else None

        offset += segment_length

    return None


def _parse_avif_dimensions(data: bytes) -> tuple[int, int] | None:
    """Baca dimensi AVIF dari box ``ispe`` pada header ISO-BMFF.

    CDN Komiku mengembalikan AVIF sebagai ``206 Partial Content``. Pillow pada
    environment scraper belum tentu memiliki decoder AVIF, padahal metadata
    ukuran intrinsik sudah berada di bagian awal file pada box ``ispe``.
    ``ispe`` dapat berada di dalam beberapa container (misalnya ``meta`` /
    ``iprp`` / ``ipco``), jadi cari box berdasarkan header ukurannya dan bukan
    hanya berdasarkan offset tetap.
    """
    if len(data) < 16 or data[4:8] != b"ftyp":
        return None

    # AVIF/HEIF brands yang lazim menyimpan image spatial properties di ispe.
    compatible_brands = data[8: min(len(data), 256)]
    if not any(
        brand in compatible_brands
        for brand in (b"avif", b"avis", b"mif1", b"msf1")
    ):
        return None

    search_from = 8
    while True:
        box_type_at = data.find(b"ispe", search_from)
        if box_type_at < 4:
            return None

        box_start = box_type_at - 4
        box_size = int.from_bytes(data[box_start:box_type_at], "big")
        if box_size == 1:
            # Extended-size boxes need 16 bytes before their payload. They are
            # not expected for this small metadata box, but reject malformed
            # candidates instead of reading arbitrary bytes as dimensions.
            search_from = box_type_at + 4
            continue

        if box_size < 20 or box_start + box_size > len(data):
            search_from = box_type_at + 4
            continue

        width = int.from_bytes(data[box_type_at + 8 : box_type_at + 12], "big")
        height = int.from_bytes(data[box_type_at + 12 : box_type_at + 16], "big")
        if width > 0 and height > 0:
            return width, height

        search_from = box_type_at + 4


def _parse_image_dimensions_from_bytes(data: bytes) -> tuple[int, int] | None:
    """Baca dimensi dari payload gambar yang sudah tersedia di memory."""
    jpeg_dimensions = _parse_jpeg_dimensions(data)
    if jpeg_dimensions is not None:
        return jpeg_dimensions

    webp_dimensions = _parse_webp_dimensions(data)
    if webp_dimensions is not None:
        return webp_dimensions

    avif_dimensions = _parse_avif_dimensions(data)
    if avif_dimensions is not None:
        return avif_dimensions

    parser = ImageFile.Parser()
    try:
        parser.feed(data[:IMAGE_DIMENSION_PROBE_MAX_BYTES])
    except (OSError, ValueError):
        return None

    if parser.image is None:
        return None
    width, height = parser.image.size
    return (width, height) if width > 0 and height > 0 else None


async def probe_image_dimensions(
    client: httpx.AsyncClient,
    image_url: str,
) -> tuple[int, int] | None:
    """Baca metadata dimensi dari awal stream tanpa mengunduh seluruh gambar."""
    headers = {
        **get_proxy_headers(image_url),
        "Range": f"bytes=0-{IMAGE_DIMENSION_PROBE_MAX_BYTES - 1}",
    }
    parser = ImageFile.Parser()
    received = 0
    header_sample = bytearray()

    try:
        async with client.stream(
            "GET",
            image_url,
            headers=headers,
            follow_redirects=True,
            timeout=10.0,
        ) as response:
            if _should_try_scrapling_image_fallback(image_url, response.status_code):
                logger.info(
                    "Probe dimensi mendapat HTTP %s untuk %s; mencoba fallback Scrapling.",
                    response.status_code,
                    image_url,
                )
                await response.aclose()
                scrapling_result = await _fetch_image_via_scrapling(image_url)
                if scrapling_result is None:
                    return None
                try:
                    return _parse_image_dimensions_from_bytes(
                        scrapling_result.response.content
                    )
                finally:
                    await scrapling_result.response.aclose()

            if response.status_code not in (200, 206):
                return None

            async for chunk in response.aiter_bytes():
                remaining = IMAGE_DIMENSION_PROBE_MAX_BYTES - received
                if remaining <= 0:
                    break
                sample = chunk[:remaining]
                if len(header_sample) < IMAGE_DIMENSION_PROBE_MAX_BYTES:
                    header_sample.extend(
                        sample[: IMAGE_DIMENSION_PROBE_MAX_BYTES - len(header_sample)]
                    )
                    jpeg_dimensions = _parse_jpeg_dimensions(bytes(header_sample))
                    if jpeg_dimensions is not None:
                        return jpeg_dimensions
                    webp_dimensions = _parse_webp_dimensions(bytes(header_sample))
                    if webp_dimensions is not None:
                        return webp_dimensions
                    avif_dimensions = _parse_avif_dimensions(bytes(header_sample))
                    if avif_dimensions is not None:
                        return avif_dimensions
                parser.feed(sample)
                received += min(len(chunk), remaining)
                if parser.image is not None:
                    width, height = parser.image.size
                    if width > 0 and height > 0:
                        return width, height
                if received >= IMAGE_DIMENSION_PROBE_MAX_BYTES:
                    break
    except (httpx.HTTPError, OSError, ValueError):
        logger.debug("Gagal membaca dimensi image %s", image_url, exc_info=True)

    return None


async def enrich_chapter_image_dimensions(
    images: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Lengkapi dimensi intrinsik image chapter secara paralel dan best-effort."""
    normalized_images = [normalize_chapter_image(image) for image in images]
    pending_indexes = [
        index
        for index, image in enumerate(normalized_images)
        if not chapter_image_has_dimensions(image)
    ]
    if not pending_indexes:
        return normalized_images

    semaphore = asyncio.Semaphore(IMAGE_DIMENSION_PROBE_CONCURRENCY)
    client = get_image_proxy_http_client()

    async def enrich(index: int) -> None:
        async with semaphore:
            image = normalized_images[index]
            dimensions = await probe_image_dimensions(client, image["url"])
            if dimensions is None:
                return
            image["width"], image["height"] = dimensions

    await asyncio.gather(*(enrich(index) for index in pending_indexes))

    return normalized_images


def get_komikcast_api_headers() -> dict[str, str]:
    """Headers API Komikcast untuk refresh signed asset URL."""
    return {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "application/json, text/plain, */*",
        "Referer": KOMIKCAST_WEB_REFERER,
        "Origin": KOMIKCAST_WEB_BASE_URL,
    }


def extract_komikcast_series_slug_from_cover_url(image_url: str) -> str | None:
    """
    Ambil slug series dari URL cover MinIO Komikcast.

    Cover Komikcast dari API berbentuk signed URL MinIO yang expired harian,
    contohnya `/prod/series/{slug}/cover/{file}.webp?...`.
    """
    parsed = urlparse(image_url)
    slug = _extract_komikcast_cover_slug_from_path(parsed.path)
    if slug and (
        _is_komikcast_image_host(parsed.netloc)
        or parsed.scheme in {"http", "https"}
    ):
        return slug
    return None


async def refresh_komikcast_cover_url(
    client: httpx.AsyncClient,
    image_url: str,
) -> str | None:
    """
    Resolve ulang signed URL cover Komikcast yang sudah kedaluwarsa.

    Database bisa menyimpan `coverImage` lama dari API Komikcast. Ketika URL itu
    expired, proxy mengambil payload series terbaru untuk mendapatkan signed URL
    baru tanpa menunggu job scraper berjalan lagi.
    """
    slug = extract_komikcast_series_slug_from_cover_url(image_url)
    if not slug:
        return None

    cover_url = await fetch_komikcast_cover_url_for_slug(client, slug)
    if not cover_url or cover_url == image_url:
        return None
    return cover_url


async def fetch_komikcast_cover_url_for_slug(
    client: httpx.AsyncClient,
    slug: str,
) -> str | None:
    """Ambil signed cover URL terbaru dari API Komikcast untuk satu slug."""
    slug = slug.strip()
    if not slug:
        return None

    response = await client.get(
        f"{KOMIKCAST_API_BASE_URL}/series/{slug}",
        params={"includeMeta": "true"},
        headers=get_komikcast_api_headers(),
        follow_redirects=True,
        timeout=15.0,
    )
    if response.status_code != 200:
        return None

    try:
        payload = response.json()
    except ValueError:
        return None
    cover_url = ((payload.get("data") or {}).get("data") or {}).get("coverImage")
    if not isinstance(cover_url, str):
        return None

    cover_url = cover_url.strip()
    if not cover_url:
        return None
    return cover_url


async def update_komikcast_cover_url_for_slug(
    db: AsyncSession,
    *,
    slug: str,
    cover_url: str,
) -> bool:
    """Simpan signed cover URL Komikcast terbaru untuk satu comic slug."""
    cover_url = cover_url.strip()
    if not slug or not cover_url:
        return False

    result = await db.execute(
        update(Comic)
        .where(Comic.source_name == "komikcast", Comic.slug == slug)
        .where(
            or_(
                Comic.cover_image_url.is_(None),
                Comic.cover_image_url != cover_url,
            )
        )
        .values(cover_image_url=cover_url, updated_at=func.now())
    )
    await db.commit()
    return bool(result.rowcount)


async def get_komikcast_cover_refresh_candidates(
    db: AsyncSession,
    *,
    limit: int,
    after_id: int = 0,
) -> list[tuple[int, str, str, str | None]]:
    """Ambil comic Komikcast yang cover URL-nya bisa direfresh dari API source."""
    stmt = (
        select(Comic.id, Comic.slug, Comic.title, Comic.cover_image_url)
        .where(Comic.source_name == "komikcast")
        .where(Comic.slug.is_not(None), Comic.slug != "")
        .where(Comic.id > max(after_id, 0))
        .order_by(Comic.id.asc())
    )
    if limit > 0:
        stmt = stmt.limit(limit)

    rows = (await db.execute(stmt)).all()
    return [(int(row[0]), str(row[1]), str(row[2]), row[3]) for row in rows]


def is_komiku_asia_cover_url(image_url: str) -> bool:
    """Cek apakah URL adalah cover WordPress Komiku Asia yang diproteksi Cloudflare."""
    parsed = urlparse(image_url)
    return (
        parsed.netloc.endswith("komiku.asia")
        and re.match(
            r"^/wp-content/uploads/\d{4}/\d{2}/[^/]+\.(?:jpe?g|png|webp|gif|avif)$",
            parsed.path,
            re.IGNORECASE,
        )
        is not None
    )
