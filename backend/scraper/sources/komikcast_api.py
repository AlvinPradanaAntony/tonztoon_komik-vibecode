"""
Shared helper untuk endpoint API Komikcast yang dipakai lintas scraper.
"""

from __future__ import annotations

import asyncio
import json
import re
from datetime import datetime
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

KOMIKCAST_BASE_URL = "https://v1.komikcast.fit"
KOMIKCAST_API_BASE_URL = "https://be.komikcast.cc"
DEFAULT_SERIES_INDEX_TAKE = 12
DEFAULT_SERIES_INDEX_TAKE_CHAPTER = 2
DEFAULT_POPULAR_TAKE = 20


def _clean_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def build_komikcast_api_headers() -> dict[str, str]:
    return {
        "User-Agent": "Mozilla/5.0",
        "Accept": "application/json, text/plain, */*",
        "Referer": f"{KOMIKCAST_BASE_URL}/",
        "Origin": KOMIKCAST_BASE_URL,
    }


async def fetch_komikcast_api_json(api_url: str) -> dict[str, Any]:
    def do_request() -> dict[str, Any]:
        request = Request(api_url, headers=build_komikcast_api_headers())
        with urlopen(request, timeout=45) as response:
            payload = response.read().decode("utf-8", errors="ignore")
        return json.loads(payload)

    data = await asyncio.to_thread(do_request)
    if data.get("status") != 200:
        raise RuntimeError(f"Gagal mengambil data API Komikcast: {api_url}")
    return data


def extract_komikcast_series_slug(url: str) -> str:
    match = re.search(r"/series/([^/?#]+)", url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak slug series Komikcast dari URL: {url}")
    return match.group(1)


def extract_komikcast_chapter_identity(chapter_url: str) -> tuple[str, str]:
    match = re.search(r"/series/([^/?#]+)/chapter/([^/?#]+)", chapter_url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak chapter identity dari URL: {chapter_url}")
    return match.group(1), match.group(2)


def parse_komikcast_iso_datetime(value: str | None) -> datetime | None:
    cleaned = _clean_text(value)
    if not cleaned:
        return None

    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


def sum_komikcast_chapter_views(chapter_items: list[dict[str, Any]]) -> int | None:
    total = 0
    seen = False

    for chapter in chapter_items:
        views_total = ((chapter.get("views") or {}).get("total"))
        if views_total is None:
            continue
        seen = True
        total += int(views_total)

    return total if seen else None


def coalesce_komikcast_total_view(
    *,
    item_data: dict[str, Any],
    item_metadata: dict[str, Any],
    item_data_metadata: dict[str, Any],
) -> int | None:
    candidates = (
        item_data.get("totalViews"),
        (item_metadata.get("views") or {}).get("total"),
        item_data_metadata.get("totalViewsComputed"),
        item_data_metadata.get("historyViews"),
        item_data_metadata.get("analyticsViews"),
    )

    for value in candidates:
        if value is None:
            continue
        try:
            return int(value)
        except (TypeError, ValueError):
            continue
    return None


def build_komikcast_series_index_params(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    take_chapter: int = DEFAULT_SERIES_INDEX_TAKE_CHAPTER,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "takeChapter": take_chapter,
        "includeMeta": str(include_meta).lower(),
        "sort": sort,
        "sortOrder": sort_order,
        "take": take,
        "page": max(page, 1),
    }

    cleaned_query = _clean_text(query)
    if cleaned_query:
        params["filter"] = f'title=like="{cleaned_query}",nativeTitle=like="{cleaned_query}"'

    return params


def build_komikcast_series_index_url(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    take_chapter: int = DEFAULT_SERIES_INDEX_TAKE_CHAPTER,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> str:
    params = build_komikcast_series_index_params(
        page=page,
        query=query,
        take=take,
        take_chapter=take_chapter,
        sort=sort,
        sort_order=sort_order,
        include_meta=include_meta,
    )
    return f"{KOMIKCAST_API_BASE_URL}/series?{urlencode(params, doseq=True)}"


def build_komikcast_popular_url(
    *,
    page: int = 1,
    take: int = DEFAULT_POPULAR_TAKE,
) -> str:
    params = {
        "take": take,
        "page": max(page, 1),
    }
    return f"{KOMIKCAST_API_BASE_URL}/series/most-read?{urlencode(params)}"


def build_komikcast_series_detail_url(
    series_slug: str,
    *,
    include_meta: bool = True,
) -> str:
    params = {"includeMeta": str(include_meta).lower()}
    return f"{KOMIKCAST_API_BASE_URL}/series/{series_slug}?{urlencode(params)}"


def build_komikcast_series_chapters_url(series_slug: str) -> str:
    return f"{KOMIKCAST_API_BASE_URL}/series/{series_slug}/chapters"


def build_komikcast_chapter_detail_url(series_slug: str, chapter_number: str) -> str:
    return f"{KOMIKCAST_API_BASE_URL}/series/{series_slug}/chapters/{chapter_number}"
