"""Endpoint helpers for the official Komiku Asia API."""

from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote, urlencode, urlsplit

from scraper.utils import clean_text

KOMIKU_ASIA_BASE_URL = "https://01.komiku.asia"
KOMIKU_ASIA_API_BASE_URL = f"{KOMIKU_ASIA_BASE_URL}/api/v2"
DEFAULT_COMICS_PAGE_SIZE = 20


def build_komiku_asia_api_url(
    path: str,
    *,
    params: dict[str, Any] | None = None,
) -> str:
    clean_params = {
        key: value
        for key, value in (params or {}).items()
        if value is not None and value != ""
    }
    query = urlencode(clean_params, doseq=True)
    url = f"{KOMIKU_ASIA_API_BASE_URL}/{path.lstrip('/')}"
    return f"{url}?{query}" if query else url


def build_komiku_asia_comics_url(
    *,
    page: int = 1,
    per_page: int = DEFAULT_COMICS_PAGE_SIZE,
    sort: str | None = None,
    order: str | None = None,
) -> str:
    return build_komiku_asia_api_url(
        "comics",
        params={
            "sort": sort,
            "order": order,
            "page": max(page, 1),
            "perPage": per_page,
        },
    )


def build_komiku_asia_latest_updates_url(
    *,
    page: int = 1,
    per_page: int = DEFAULT_COMICS_PAGE_SIZE,
) -> str:
    return build_komiku_asia_api_url(
        "comics/latest-updates",
        params={"page": max(page, 1), "perPage": per_page},
    )


def build_komiku_asia_search_url(
    query: str,
    *,
    limit: int = DEFAULT_COMICS_PAGE_SIZE,
) -> str:
    return build_komiku_asia_api_url(
        "comics/search",
        params={"q": clean_text(query), "limit": max(limit, 1)},
    )


def build_komiku_asia_filters_url() -> str:
    return build_komiku_asia_api_url("comics/filters")


def build_komiku_asia_comic_detail_url(slug: str) -> str:
    return build_komiku_asia_api_url(f"comics/{quote(slug, safe='')}")


def build_komiku_asia_comic_chapters_url(comic_id: int | str) -> str:
    return build_komiku_asia_api_url(f"comics/{quote(str(comic_id), safe='')}/chapters")


def build_komiku_asia_chapter_detail_url(
    comic_id: int | str,
    chapter_id: int | str,
) -> str:
    return build_komiku_asia_api_url(
        f"comics/{quote(str(comic_id), safe='')}/chapters/id/"
        f"{quote(str(chapter_id), safe='')}"
    )


def extract_komiku_asia_slug(url: str) -> str:
    path = urlsplit(url).path.rstrip("/")
    match = re.search(r"/manga/([^/]+)$", path, re.IGNORECASE)
    if not match:
        raise ValueError(f"URL detail Komiku Asia tidak memiliki slug manga: {url}")
    return match.group(1)


def extract_komiku_asia_chapter_identity(url: str) -> tuple[str, int]:
    path = urlsplit(url).path.rstrip("/")
    match = re.search(
        r"/read/id/([^/]+)/ch[^/]*-(\d+)$",
        path,
        re.IGNORECASE,
    )
    if not match:
        raise ValueError(f"URL chapter Komiku Asia tidak valid: {url}")
    return match.group(1), int(match.group(2))


def build_komiku_asia_chapter_url(
    *,
    slug: str,
    chapter_number: Any,
    chapter_id: Any,
) -> str | None:
    if not slug or chapter_number is None or chapter_id is None:
        return None
    try:
        number = float(chapter_number)
    except (TypeError, ValueError):
        route_number = str(chapter_number)
    else:
        route_number = str(int(number)) if number.is_integer() else str(number)
    return (
        f"{KOMIKU_ASIA_BASE_URL}/read/id/{quote(slug, safe='')}/"
        f"ch{route_number}-{chapter_id}"
    )
