"""
ZenRows-backed live scraper for Komiku Asia chapter images.

This service is intentionally scoped to lazy/backfill chapter image fetching.
The regular Komiku Asia scraper still owns catalog/detail parsing and can keep
using Scrapling where that is appropriate. On Hugging Face this avoids running
Xvfb/headless browser traffic from the Space while preserving the existing
chapter image contract.
"""

from __future__ import annotations

import logging
from typing import Any
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from app.config import settings
from app.services.http_client_service import get_shared_http_client
from app.services.image_service import DEFAULT_USER_AGENT

logger = logging.getLogger("service.komiku_asia_zenrows")


class KomikuAsiaZenRowsError(RuntimeError):
    """Raised when ZenRows cannot return a usable Komiku Asia page."""


class KomikuAsiaZenRowsChapterImageScraper:
    """
    Minimal scraper facade used by chapter_service.fetch_and_save_chapter_images.

    It only implements get_chapter_images(), matching the method used by the
    lazy chapter flow. Keeping this class small prevents accidental replacement
    of the full Komiku Asia catalog scraper.
    """

    SOURCE_NAME = "komiku_asia"
    BASE_URL = "https://01.komiku.asia"
    WAIT_SELECTOR = ".rd-page-image"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        api_base_url: str | None = None,
        wait_ms: int | None = None,
        timeout_seconds: float | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.api_key = (api_key if api_key is not None else settings.ZENROWS_API_KEY).strip()
        self.api_base_url = (
            api_base_url if api_base_url is not None else settings.ZENROWS_API_BASE_URL
        ).strip()
        self.wait_ms = settings.KOMIKU_ASIA_ZENROWS_WAIT_MS if wait_ms is None else wait_ms
        self.timeout_seconds = (
            settings.ZENROWS_TIMEOUT_SECONDS
            if timeout_seconds is None
            else timeout_seconds
        )
        self.client = client

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        html = await self.fetch_chapter_html(chapter_url)
        return parse_komiku_asia_chapter_images(html, base_url=self.BASE_URL)

    async def fetch_chapter_html(self, chapter_url: str) -> str:
        if not self.api_key:
            raise KomikuAsiaZenRowsError(
                "ZENROWS_API_KEY belum dikonfigurasi untuk Komiku Asia live scrape."
            )
        if not self.api_base_url:
            raise KomikuAsiaZenRowsError("ZENROWS_API_BASE_URL belum dikonfigurasi.")

        params = {
            "url": chapter_url,
            "apikey": self.api_key,
            "js_render": "true",
            "premium_proxy": "true",
            "wait_for": self.WAIT_SELECTOR,
        }
        if self.wait_ms > 0:
            params["wait"] = str(self.wait_ms)

        logger.info("ZenRows fetch Komiku Asia chapter: %s", chapter_url)
        client = self.client or get_shared_http_client()
        response = await client.get(
            self.api_base_url,
            params=params,
            headers={
                "Accept": "text/html,application/xhtml+xml",
                "User-Agent": DEFAULT_USER_AGENT,
            },
            timeout=self.timeout_seconds,
        )

        if response.status_code != 200:
            detail = response.text[:300].replace("\n", " ").strip()
            raise KomikuAsiaZenRowsError(
                f"ZenRows gagal fetch Komiku Asia chapter "
                f"(status={response.status_code}): {detail}"
            )

        return response.text


def parse_komiku_asia_chapter_images(
    html: str,
    *,
    base_url: str = KomikuAsiaZenRowsChapterImageScraper.BASE_URL,
) -> list[dict[str, Any]]:
    """Parse chapter image items from a rendered Komiku Asia chapter page."""
    soup = BeautifulSoup(html, "html.parser")
    images: list[dict[str, Any]] = []

    image_nodes = soup.select(".rd-page-image, .ts-main-image")
    if not image_nodes:
        image_nodes = [
            img
            for img in soup.select("img[src], img[data-src], img[data-lazy-src], img[data-original]")
            if img.get("src") != "/loading.gif"
            and not img.get("src", "").endswith("/loading.gif")
        ]

    for img in image_nodes:
        img_url = _extract_image_url(img)
        if not img_url:
            continue

        images.append(
            {
                "page": _extract_page_number(img, fallback=len(images) + 1),
                "url": urljoin(base_url, img_url),
            }
        )

    return images


def _extract_page_number(img, *, fallback: int) -> int:
    raw_index = img.get("data-index")
    if raw_index is None:
        return fallback

    try:
        return int(raw_index) + 1
    except (TypeError, ValueError):
        return fallback


def _extract_image_url(img) -> str | None:
    for attr in ("src", "data-src", "data-lazy-src", "data-original"):
        value = img.get(attr)
        if value:
            return value.strip()

    srcset = img.get("srcset") or img.get("data-srcset")
    if not srcset:
        return None

    first_candidate = srcset.split(",", 1)[0].strip()
    if not first_candidate:
        return None
    return first_candidate.split()[0].strip() or None
