"""
Tonztoon Komik — Image Service

Utility functions untuk image proxy logic.
Digunakan oleh route /api/v1/images/proxy.
"""

import asyncio
import ipaddress
import logging
import re
import socket
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode, urljoin, urlparse

import httpx
from PIL import ImageFile
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
    "komikcast.to",
    "imgkc1.my.id",
    "imgkc2.my.id",
    "imgkc.my.id",
)
KOMIKCAST_COVER_PATH_RE = re.compile(r"^/prod/series/([^/]+)/cover/")
IMAGE_DIMENSION_PROBE_MAX_BYTES = 256 * 1024
IMAGE_DIMENSION_PROBE_CONCURRENCY = 8
IMAGE_PROXY_ALLOWED_SCHEMES = {"http", "https"}
IMAGE_PROXY_ALLOWED_PORTS = {80, 443}
IMAGE_PROXY_DEFAULT_ALLOWED_HOST_SUFFIXES = (
    "komiku.org",
    "komiku.asia",
    "cdnkomiku.xyz",
    "shinigami.asia",
    "shngm.id",
    "api.shngm.io",
    "komikcast.to",
    "imgkc1.my.id",
    "imgkc2.my.id",
    "imgkc.my.id",
    "be.komikcast.cc",
    "v1.komikcast.fit",
    "blogspot.com",
    "blogger.googleusercontent.com",
    "googleusercontent.com",
    "yuucdn.com",
)

# Mapping host suffix -> Referer header yang benar untuk source non-Komikcast.
REFERER_BY_HOST_SUFFIX = {
    "komiku.org": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "cdnkomiku.xyz": "https://01.komiku.asia/",
    "shinigami.asia": "https://e.shinigami.asia/",
    "shngm.id": "https://e.shinigami.asia/",
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


async def open_validated_image_proxy_response(
    image_url: str,
    *,
    client: httpx.AsyncClient | None = None,
) -> ImageProxyFetchResult:
    """
    Open an upstream image stream after validating URL, DNS, redirects, and headers.
    """
    active_client = client or get_image_proxy_http_client()
    current_url = validate_proxy_image_url(image_url)
    response: httpx.Response | None = None

    for redirect_count in range(settings.IMAGE_PROXY_MAX_REDIRECTS + 1):
        await validate_proxy_image_dns(current_url)
        request = active_client.build_request(
            "GET",
            current_url,
            headers=get_proxy_headers(current_url),
        )
        response = await active_client.send(request, stream=True)

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

    try:
        async with client.stream(
            "GET",
            image_url,
            headers=headers,
            follow_redirects=True,
            timeout=10.0,
        ) as response:
            if response.status_code not in (200, 206):
                return None

            async for chunk in response.aiter_bytes():
                remaining = IMAGE_DIMENSION_PROBE_MAX_BYTES - received
                if remaining <= 0:
                    break
                parser.feed(chunk[:remaining])
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
