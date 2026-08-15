"""
Shared helper untuk endpoint API Voratoon yang dipakai lintas scraper.
"""

from __future__ import annotations

import asyncio
import json
import re
from datetime import datetime
from typing import Any
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from scraper.utils import clean_text

VORATOON_BASE_URL = "https://v1.voratoon.com"
VORATOON_API_BASE_URL = "https://api.voratoon.com"
DEFAULT_SERIES_INDEX_TAKE = 24
DEFAULT_POPULAR_TAKE = 20
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36"
)


def build_voratoon_api_headers(referer_url: str | None = None) -> dict[str, str]:
    referer = referer_url or f"{VORATOON_BASE_URL}/"
    return {
        "User-Agent": DEFAULT_USER_AGENT,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Referer": referer,
        "Origin": VORATOON_BASE_URL,
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "cross-site",
    }


async def fetch_voratoon_api_json(api_url: str, *, referer_url: str | None = None) -> dict[str, Any]:
    def do_request() -> dict[str, Any]:
        request = Request(api_url, headers=build_voratoon_api_headers(referer_url))
        try:
            with urlopen(request, timeout=45) as response:
                payload = response.read().decode("utf-8", errors="ignore")
        except HTTPError as exc:
            body = exc.read().decode("utf-8", errors="ignore")[:500]
            raise RuntimeError(
                f"Voratoon API HTTP {exc.code} untuk {api_url}: {body}"
            ) from exc
        return json.loads(payload)

    data = await asyncio.to_thread(do_request)
    if data.get("status") not in (200, None):
        raise RuntimeError(f"Gagal mengambil data API Voratoon: {api_url}")
    return data


def extract_voratoon_series_slug(url: str) -> str:
    match = re.search(r"/series/([^/?#]+)", url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak slug series Voratoon dari URL: {url}")
    return match.group(1)


def extract_voratoon_chapter_identity(chapter_url: str) -> tuple[str, str]:
    match = re.search(r"/series/([^/?#]+)/chapter/([^/?#]+)", chapter_url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak chapter identity dari URL: {chapter_url}")
    return match.group(1), match.group(2)


def parse_voratoon_iso_datetime(value: str | None) -> datetime | None:
    cleaned = clean_text(value)
    if not cleaned:
        return None

    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


MAX_INT32 = 2_147_483_647


def coalesce_voratoon_total_view(
    *,
    item_data: dict[str, Any],
    item_metadata: dict[str, Any],
    item_data_metadata: dict[str, Any],
) -> int | None:
    candidates = (
        item_data.get("totalViews"),
        (item_metadata.get("views") or {}).get("total"),
        item_data_metadata.get("historyViews"),
        item_data_metadata.get("analyticsViews"),
        item_data_metadata.get("monthlyViews"),
        item_data_metadata.get("totalViewsComputed"),
    )

    for value in candidates:
        if value is None:
            continue
        try:
            val = int(value)
            return min(val, MAX_INT32) if val > 0 else 0
        except (TypeError, ValueError):
            continue
    return None


def build_voratoon_series_index_params(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "includeMeta": str(include_meta).lower(),
        "sort": sort,
        "sortOrder": sort_order,
        "take": take,
        "page": max(page, 1),
    }

    cleaned_query = clean_text(query)
    if cleaned_query:
        params["filter"] = f'title=like="{cleaned_query}",nativeTitle=like="{cleaned_query}"'

    return params


def build_voratoon_series_index_url(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> str:
    params = build_voratoon_series_index_params(
        page=page,
        query=query,
        take=take,
        sort=sort,
        sort_order=sort_order,
        include_meta=include_meta,
    )
    return f"{VORATOON_API_BASE_URL}/series?{urlencode(params, doseq=True)}"


def build_voratoon_popular_url(
    *,
    page: int = 1,
    take: int = DEFAULT_POPULAR_TAKE,
) -> str:
    params = {
        "take": take,
        "page": max(page, 1),
    }
    return f"{VORATOON_API_BASE_URL}/series/most-read?{urlencode(params)}"


def build_voratoon_series_detail_url(
    series_slug: str,
    *,
    include_meta: bool = True,
) -> str:
    params = {"includeMeta": str(include_meta).lower()}
    return f"{VORATOON_API_BASE_URL}/series/{series_slug}?{urlencode(params)}"


def build_voratoon_series_chapters_url(series_slug: str) -> str:
    return f"{VORATOON_API_BASE_URL}/series/{series_slug}/chapters"


def build_voratoon_chapter_detail_url(series_slug: str, chapter_number: str) -> str:
    return f"{VORATOON_API_BASE_URL}/series/{series_slug}/chapters/{chapter_number}"
