"""
Tonztoon Komik — Image Service

Utility functions untuk image proxy logic.
Digunakan oleh route /api/v1/images/proxy.
"""

import logging
import re
from typing import Any
from urllib.parse import urlencode, urljoin, urlparse

import httpx
from scrapling.parser import Adaptor


logger = logging.getLogger("app.services.image_service")


# Mapping domain -> Referer header yang benar
REFERER_MAP = {
    "komiku.org": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "cdnkomiku.xyz": "https://01.komiku.asia/",
    "komikcast": "https://v1.komikcast.fit/",
    "komikcast.to": "https://v1.komikcast.fit/",
    "imgkc2.my.id": "https://v1.komikcast.fit/",
    "imgkc.my.id": "https://v1.komikcast.fit/",
    "shinigami": "https://e.shinigami.asia/",
    "shngm.id": "https://e.shinigami.asia/",
}

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

PROXY_IMAGE_PATH = "/api/v1/images/proxy"
KOMIKU_CANONICAL_BASE_URL = "https://komiku.org"
_KOMIKU_ASIA_COVER_CACHE: dict[str, str | None] = {}


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


def build_proxy_image_url(
    image_url: str | None,
    base_url: str | None = None,
    source_url: str | None = None,
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

    query_params = {"url": image_url}
    if source_url:
        query_params["source_url"] = source_url

    proxy_path = f"{PROXY_IMAGE_PATH}?{urlencode(query_params)}"
    return build_absolute_url(base_url, proxy_path)


def wrap_chapter_image_urls(
    images: list[dict[str, Any]] | None,
    base_url: str | None = None,
    source_url: str | None = None,
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
            source_url=source_url,
        )
        wrapped_images.append(wrapped_image)
    return wrapped_images


def get_proxy_headers(image_url: str) -> dict[str, str]:
    """
    Generate headers yang tepat untuk fetch gambar dari server asli.
    Menentukan Referer berdasarkan domain URL gambar.
    """
    referer = None
    for key, ref_url in REFERER_MAP.items():
        if key in image_url:
            referer = ref_url
            break

    if referer is None:
        parsed = urlparse(image_url)
        referer = f"{parsed.scheme}://{parsed.netloc}/"

    return {
        "Referer": referer,
        "User-Agent": DEFAULT_USER_AGENT,
    }


def is_komiku_asia_cover_url(image_url: str) -> bool:
    """Cek apakah URL adalah cover WordPress Komiku Asia yang diproteksi Cloudflare."""
    parsed = urlparse(image_url)
    return (
        parsed.netloc.endswith("komiku.asia")
        and re.match(
            r"^/wp-content/uploads/\d{4}/\d{2}/[^/]+\.(?:jpe?g|png|webp)$",
            parsed.path,
            re.IGNORECASE,
        )
        is not None
    )


def build_komiku_canonical_detail_url(source_url: str | None) -> str | None:
    """Bangun URL detail canonical komiku.org dari URL detail Komiku Asia."""
    if not source_url:
        return None

    parsed = urlparse(source_url)
    path_parts = [part for part in parsed.path.split("/") if part]
    if len(path_parts) < 2 or path_parts[0] != "manga":
        return None

    slug = path_parts[1]
    if not slug:
        return None
    slug = re.sub(r"^\d{6}-", "", slug)

    return f"{KOMIKU_CANONICAL_BASE_URL}/manga/{slug}/"


def extract_cover_url_from_komiku_html(html: bytes | str, page_url: str) -> str | None:
    """Ambil cover canonical dari HTML detail komiku.org."""
    page = Adaptor(content=html, url=page_url)
    selectors = (
        ("meta[property='og:image']", ("content",)),
        ("meta[name='twitter:image']", ("content",)),
        (".ims img", ("src", "data-src")),
    )

    for selector, attrs in selectors:
        for element in page.css(selector):
            for attr in attrs:
                value = element.attrib.get(attr)
                if value:
                    return urljoin(page_url, value)

    return None


async def resolve_komiku_asia_cover_fallback(
    image_url: str,
    source_url: str | None,
    *,
    client: httpx.AsyncClient,
) -> str | None:
    """
    Resolve cover Komiku Asia ke thumbnail canonical komiku.org.

    File `/wp-content/uploads/...` pada `01.komiku.asia` dilindungi Cloudflare
    dan gagal diambil oleh proxy HTTP biasa. Halaman canonical `komiku.org`
    menyimpan cover yang sama di `thumbnail.komiku.org`, yang bisa diproxy
    secara stabil.
    """
    if not is_komiku_asia_cover_url(image_url):
        return None

    canonical_detail_url = build_komiku_canonical_detail_url(source_url)
    if not canonical_detail_url:
        return None

    if canonical_detail_url in _KOMIKU_ASIA_COVER_CACHE:
        return _KOMIKU_ASIA_COVER_CACHE[canonical_detail_url]

    try:
        response = await client.get(
            canonical_detail_url,
            headers={
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Referer": f"{KOMIKU_CANONICAL_BASE_URL}/",
                "User-Agent": DEFAULT_USER_AGENT,
            },
        )
        if response.status_code != 200:
            logger.warning(
                "Gagal resolve cover canonical Komiku Asia %s: status=%s",
                canonical_detail_url,
                response.status_code,
            )
            return None

        cover_url = extract_cover_url_from_komiku_html(
            response.content,
            str(response.url),
        )
        if cover_url:
            _KOMIKU_ASIA_COVER_CACHE[canonical_detail_url] = cover_url
        return cover_url
    except Exception as exc:
        logger.warning(
            "Gagal resolve cover canonical Komiku Asia %s: %s: %s",
            canonical_detail_url,
            type(exc).__name__,
            exc,
        )
        return None
