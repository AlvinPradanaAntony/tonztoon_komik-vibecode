"""
Helper endpoint resmi Kiryuu (WordPress + REST + AJAX).

Source ini memakai WordPress + HTMX:
- katalog/detail metadata: /wp-json/wp/v2/manga
- nonce pencarian: /wp-admin/admin-ajax.php?type=search_form&action=get_nonce
- feed advanced-search: POST /wp-admin/admin-ajax.php?action=advanced_search
- chapter list: /wp-admin/admin-ajax.php?manga_id=...&page=1&action=chapter_list

REST dipakai sebagai source of truth untuk katalog/search/detail metadata.
Endpoint AJAX advanced-search tetap dipakai untuk feed frontend yang memuat
latest chapter/popular ordering sebagai HTML fragment.

Domain aktif:
- Portal resmi canonical: https://kiryuu.io / https://kiryuu.io/domain
- Domain aktif saat ini: https://v7.kiryuu.to
- Domain legacy: v5.kiryuu.to (dialihkan ke internet positif/laman labuh), kiryuu03.com, kiryuu.co, kiryuu.id
"""

from __future__ import annotations

import json
import logging
import re
import time
from typing import Any
from urllib.parse import urlencode

from scraper.utils import clean_text

logger = logging.getLogger("scraper.kiryuu")

DEFAULT_KIRYUU_BASE_URL = "https://v7.kiryuu.to"
KIRYUU_PORTAL_DOMAIN_URL = "https://kiryuu.io/domain"

_CURRENT_KIRYUU_BASE_URL: str = DEFAULT_KIRYUU_BASE_URL
_LAST_DISCOVERED_TIME: float = 0.0

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36"
)


def get_kiryuu_base_url() -> str:
    """Ambil base URL aktif saat ini untuk Kiryuu."""
    return _CURRENT_KIRYUU_BASE_URL


def set_kiryuu_base_url(url: str) -> None:
    """Set base URL Kiryuu aktif."""
    global _CURRENT_KIRYUU_BASE_URL, KIRYUU_BASE_URL, KIRYUU_AJAX_URL, KIRYUU_REST_BASE_URL, KIRYUU_ADVANCED_SEARCH_URL
    clean = url.strip().rstrip("/")
    _CURRENT_KIRYUU_BASE_URL = clean
    KIRYUU_BASE_URL = clean
    KIRYUU_AJAX_URL = f"{clean}/wp-admin/admin-ajax.php"
    KIRYUU_REST_BASE_URL = f"{clean}/wp-json/wp/v2"
    KIRYUU_ADVANCED_SEARCH_URL = f"{clean}/advanced-search/"


def discover_kiryuu_base_url(timeout: float = 5.0) -> str:
    """
    Auto-discover domain aktif Kiryuu dari portal resmi https://kiryuu.io/domain.
    Kiryuu secara berkala merotasi subdomain (kiryuu.id -> kiryuu.co -> kiryuu03.com -> v5 -> v7 -> dst)
    karena pemblokiran ISP. Halaman https://kiryuu.io/domain selalu mempublikasikan domain aktif terbaru.
    """
    global _LAST_DISCOVERED_TIME
    try:
        from scrapling.fetchers import Fetcher

        page = Fetcher.get(
            KIRYUU_PORTAL_DOMAIN_URL,
            stealthy_headers=True,
            timeout=timeout,
        )
        if getattr(page, "status", 0) == 200:
            for anchor in page.css("a[href*='kiryuu.to']"):
                href = clean_text(anchor.attrib.get("href"))
                match = re.match(r"^https?://([a-zA-Z0-9.-]*kiryuu\.to)", href)
                if match:
                    discovered = f"https://{match.group(1)}"
                    set_kiryuu_base_url(discovered)
                    _LAST_DISCOVERED_TIME = time.time()
                    return discovered
    except Exception as exc:
        logger.warning(
            "Gagal auto-discover Kiryuu base URL dari %s: %s",
            KIRYUU_PORTAL_DOMAIN_URL,
            exc,
        )
    return _CURRENT_KIRYUU_BASE_URL


def normalize_kiryuu_url(url: str | None) -> str:
    """
    Normalisasi URL atau slug Kiryuu agar selalu mengarah ke domain aktif (misal v7.kiryuu.to)
    dan protokol HTTPS. Mengganti domain lama seperti v5.kiryuu.to, kiryuu03.com, kiryuu.co, kiryuu.id.
    """
    base_url = get_kiryuu_base_url()
    if not url:
        return f"{base_url}/"
    cleaned = clean_text(url)
    if not cleaned:
        return f"{base_url}/"

    normalized = re.sub(
        r"^https?://(?:v\d+\.)?kiryuu\.(?:to|io|org|co|id|net)",
        base_url,
        cleaned,
        flags=re.IGNORECASE,
    )
    normalized = re.sub(
        r"^https?://kiryuu\d+\.com",
        base_url,
        normalized,
        flags=re.IGNORECASE,
    )

    if not normalized.startswith("http"):
        normalized = f"{base_url}/{normalized.lstrip('/')}"

    return normalized


# Module-level variables for backwards compatibility
KIRYUU_BASE_URL = DEFAULT_KIRYUU_BASE_URL
KIRYUU_AJAX_URL = f"{KIRYUU_BASE_URL}/wp-admin/admin-ajax.php"
KIRYUU_REST_BASE_URL = f"{KIRYUU_BASE_URL}/wp-json/wp/v2"
KIRYUU_ADVANCED_SEARCH_URL = f"{KIRYUU_BASE_URL}/advanced-search/"


def get_kiryuu_ajax_url() -> str:
    return f"{get_kiryuu_base_url()}/wp-admin/admin-ajax.php"


def get_kiryuu_rest_base_url() -> str:
    return f"{get_kiryuu_base_url()}/wp-json/wp/v2"


def get_kiryuu_advanced_search_url() -> str:
    return f"{get_kiryuu_base_url()}/advanced-search/"


def build_kiryuu_headers(referer_url: str | None = None) -> dict[str, str]:
    referer = normalize_kiryuu_url(referer_url) if referer_url else get_kiryuu_advanced_search_url()
    return {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Referer": referer,
    }


def build_kiryuu_nonce_url() -> str:
    return f"{get_kiryuu_ajax_url()}?{urlencode({'type': 'search_form', 'action': 'get_nonce'})}"


def build_kiryuu_advanced_search_url() -> str:
    return f"{get_kiryuu_ajax_url()}?{urlencode({'action': 'advanced_search'})}"


def build_kiryuu_chapter_list_url(manga_id: str, *, page: int = 1) -> str:
    return f"{get_kiryuu_ajax_url()}?{urlencode({'manga_id': manga_id, 'page': max(page, 1), 'action': 'chapter_list'})}"


def build_kiryuu_manga_list_url(
    *,
    page: int = 1,
    per_page: int = 24,
    order: str = "asc",
    orderby: str = "title",
) -> str:
    params: dict[str, Any] = {
        "page": max(page, 1),
        "per_page": per_page,
        "order": order,
        "orderby": orderby,
        "_embed": "1",
    }
    return f"{get_kiryuu_rest_base_url()}/manga?{urlencode(params)}"


def build_kiryuu_manga_detail_url(slug: str) -> str:
    return f"{get_kiryuu_rest_base_url()}/manga?{urlencode({'slug': slug, '_embed': '1'})}"


def build_kiryuu_advanced_search_form(
    *,
    nonce: str,
    page: int = 1,
    query: str | None = None,
    genre: list[str] | None = None,
    genre_exclude: list[str] | None = None,
    author: list[str] | None = None,
    artist: list[str] | None = None,
    comic_type: list[str] | None = None,
    status: list[str] | None = None,
    project: bool = False,
    order: str = "asc",
    orderby: str = "title",
    inclusion: str = "OR",
    exclusion: str = "OR",
) -> dict[str, Any]:
    return {
        "nonce": nonce,
        "page": str(max(page, 1)),
        "genre": json.dumps(genre or []),
        "genre_exclude": json.dumps(genre_exclude or []),
        "author": json.dumps(author or []),
        "artist": json.dumps(artist or []),
        "project": "1" if project else "0",
        "type": json.dumps(comic_type or []),
        "status": json.dumps(status or []),
        "order": order,
        "orderby": orderby,
        "query": query or "",
        "inclusion": inclusion,
        "exclusion": exclusion,
    }
