"""
Tonztoon Komik — Image Service

Utility functions untuk image proxy logic.
Digunakan oleh route /api/v1/images/proxy.
"""

from typing import Any
from urllib.parse import urlencode, urlparse


# Mapping domain -> Referer header yang benar
REFERER_MAP = {
    "komiku.org": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "cdnkomiku.xyz": "https://01.komiku.asia/",
    "komikcast": "https://v1.komikcast.fit/",
    "shinigami": "https://e.shinigami.asia/",
}

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

PROXY_IMAGE_PATH = "/api/v1/images/proxy"


def build_proxy_image_url(image_url: str | None) -> str | None:
    """
    Bungkus URL gambar asli ke endpoint proxy global FastAPI.

    Jika URL sudah berbentuk endpoint proxy, nilai akan dikembalikan apa adanya.
    """
    if not image_url:
        return image_url

    parsed = urlparse(image_url)
    if image_url.startswith(PROXY_IMAGE_PATH) or parsed.path.endswith(PROXY_IMAGE_PATH):
        return image_url

    if not parsed.scheme or not parsed.netloc:
        return image_url

    return f"{PROXY_IMAGE_PATH}?{urlencode({'url': image_url})}"


def wrap_chapter_image_urls(images: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    """
    Bungkus semua field `url` di array gambar chapter ke URL proxy global.
    """
    wrapped_images: list[dict[str, Any]] = []
    for image in images or []:
        wrapped_image = dict(image)
        wrapped_image["url"] = build_proxy_image_url(image.get("url"))
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
