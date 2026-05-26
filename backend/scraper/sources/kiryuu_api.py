"""
Helper endpoint resmi Kiryuu v5.

Source ini memakai WordPress + HTMX:
- katalog/detail metadata: /wp-json/wp/v2/manga
- nonce pencarian: /wp-admin/admin-ajax.php?type=search_form&action=get_nonce
- feed advanced-search: POST /wp-admin/admin-ajax.php?action=advanced_search
- chapter list: /wp-admin/admin-ajax.php?manga_id=...&page=1&action=chapter_list

REST dipakai sebagai source of truth untuk katalog/search/detail metadata.
Endpoint AJAX advanced-search tetap dipakai untuk feed frontend yang memuat
latest chapter/popular ordering sebagai HTML fragment.
"""

from __future__ import annotations

import json
from typing import Any
from urllib.parse import urlencode

KIRYUU_BASE_URL = "https://v5.kiryuu.to"
KIRYUU_AJAX_URL = f"{KIRYUU_BASE_URL}/wp-admin/admin-ajax.php"
KIRYUU_REST_BASE_URL = f"{KIRYUU_BASE_URL}/wp-json/wp/v2"
KIRYUU_ADVANCED_SEARCH_URL = f"{KIRYUU_BASE_URL}/advanced-search/"

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)


def build_kiryuu_headers(referer_url: str | None = None) -> dict[str, str]:
    return {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Referer": referer_url or KIRYUU_ADVANCED_SEARCH_URL,
    }


def build_kiryuu_nonce_url() -> str:
    return f"{KIRYUU_AJAX_URL}?{urlencode({'type': 'search_form', 'action': 'get_nonce'})}"


def build_kiryuu_advanced_search_url() -> str:
    return f"{KIRYUU_AJAX_URL}?{urlencode({'action': 'advanced_search'})}"


def build_kiryuu_chapter_list_url(manga_id: str, *, page: int = 1) -> str:
    return f"{KIRYUU_AJAX_URL}?{urlencode({'manga_id': manga_id, 'page': max(page, 1), 'action': 'chapter_list'})}"


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
    return f"{KIRYUU_REST_BASE_URL}/manga?{urlencode(params)}"


def build_kiryuu_manga_detail_url(slug: str) -> str:
    return f"{KIRYUU_REST_BASE_URL}/manga?{urlencode({'slug': slug, '_embed': '1'})}"


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
