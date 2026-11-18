"""
Shared helper untuk endpoint API Shinigami yang dipakai lintas scraper.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any
from urllib.parse import quote, urlencode, urlparse

from scraper.time_utils import now_wib
from scraper.utils import clean_text

SHINIGAMI_BASE_URL = "https://s1.shinigami.mx"
SHINIGAMI_LEGACY_BASE_URLS = ("https://e.shinigami.asia",)
SHINIGAMI_API_BASE_URL = "https://api.shinigami.io/v1"
DEFAULT_MANGA_LIST_PAGE_SIZE = 24
DEFAULT_CHAPTER_LIST_PAGE_SIZE = 100
SHINIGAMI_MAX_SEARCH_HITS = 1000

_SHINIGAMI_SORT_MAP: dict[str, tuple[str, str]] = {
    "latest": ("latest", "desc"),
    "popular": ("popularity", "desc"),
    "popularity": ("popularity", "desc"),
    "rating": ("rating", "desc"),
    "new_manga": ("new_manga", "desc"),
    "az": ("title", "asc"),
    "title": ("title", "asc"),
}


def normalize_shinigami_web_url(url: str | None) -> str:
    """Normalisasi URL web Shinigami (termasuk domain legacy) ke host aktif."""
    cleaned = clean_text(url)
    if not cleaned:
        return f"{SHINIGAMI_BASE_URL}/"

    if cleaned.startswith("/"):
        return f"{SHINIGAMI_BASE_URL}{cleaned}"

    parsed = urlparse(cleaned)
    if parsed.scheme and parsed.netloc:
        path = parsed.path or "/"
        query = f"?{parsed.query}" if parsed.query else ""
        return f"{SHINIGAMI_BASE_URL}{path}{query}"

    return f"{SHINIGAMI_BASE_URL}/{cleaned.lstrip('/')}"


def build_shinigami_api_headers(referer_url: str | None = None) -> dict[str, str]:
    referer = normalize_shinigami_web_url(referer_url)
    return {
        "accept": "application/json",
        "origin": SHINIGAMI_BASE_URL,
        "referer": referer,
        "user-agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/147.0.0.0 Safari/537.36"
        ),
    }


def build_shinigami_search_url(query: str | None = None) -> str:
    cleaned_query = clean_text(query)
    if not cleaned_query:
        return f"{SHINIGAMI_BASE_URL}/search"
    return f"{SHINIGAMI_BASE_URL}/search?q={quote(cleaned_query)}"


def build_shinigami_chapter_url(chapter_id: str | None) -> str | None:
    cleaned_id = clean_text(chapter_id)
    if not cleaned_id:
        return None
    return f"{SHINIGAMI_BASE_URL}/chapter/{cleaned_id}"


def resolve_shinigami_sort_params(
    sort: str = "latest",
    sort_order: str | None = None,
) -> tuple[str, str]:
    """Petakan key sort ke parameter API Shinigami terbaru."""
    normalized_sort = clean_text(sort).lower() or "latest"
    api_sort, default_order = _SHINIGAMI_SORT_MAP.get(
        normalized_sort,
        (normalized_sort, "desc"),
    )
    resolved_order = clean_text(sort_order).lower() or default_order
    return api_sort, resolved_order


def build_shinigami_manga_list_params(
    *,
    page: int = 1,
    page_size: int = DEFAULT_MANGA_LIST_PAGE_SIZE,
    offset: int | None = None,
    query: str | None = None,
    sort: str = "latest",
    sort_order: str | None = None,
    comic_format: str | None = None,
    comic_type: str | None = None,
) -> dict[str, Any]:
    resolved_limit = max(int(page_size), 1)
    resolved_offset = (
        max(int(offset), 0)
        if offset is not None
        else max(int(page) - 1, 0) * resolved_limit
    )
    resolved_sort, resolved_sort_order = resolve_shinigami_sort_params(sort, sort_order)

    params: dict[str, Any] = {
        "offset": resolved_offset,
        "limit": resolved_limit,
        "genre_include_mode": "or",
        "genre_exclude_mode": "or",
        "sort": resolved_sort,
        "sort_order": resolved_sort_order,
    }

    cleaned_query = clean_text(query)
    if cleaned_query:
        params["q"] = cleaned_query

    cleaned_format = clean_text(comic_format)
    if cleaned_format:
        params["format"] = cleaned_format

    cleaned_type = clean_text(comic_type)
    if cleaned_type:
        params["type"] = cleaned_type

    return params


def build_shinigami_manga_list_url(
    *,
    page: int = 1,
    page_size: int = DEFAULT_MANGA_LIST_PAGE_SIZE,
    offset: int | None = None,
    query: str | None = None,
    sort: str = "latest",
    sort_order: str | None = None,
    comic_format: str | None = None,
    comic_type: str | None = None,
) -> str:
    params = build_shinigami_manga_list_params(
        page=page,
        page_size=page_size,
        offset=offset,
        query=query,
        sort=sort,
        sort_order=sort_order,
        comic_format=comic_format,
        comic_type=comic_type,
    )
    return f"{SHINIGAMI_API_BASE_URL}/manga/list?{urlencode(params)}"


def build_shinigami_manga_detail_url(manga_id: str) -> str:
    return f"{SHINIGAMI_API_BASE_URL}/manga/detail/{manga_id}"


def build_shinigami_chapter_list_url(
    manga_id: str,
    *,
    limit: int = DEFAULT_CHAPTER_LIST_PAGE_SIZE,
    cursor: str | None = None,
    sort_by: str = "chapter_number",
    sort_order: str = "desc",
) -> str:
    params: dict[str, Any] = {
        "limit": max(int(limit), 1),
        "sort_by": sort_by,
        "sort_order": sort_order,
    }
    cleaned_cursor = clean_text(cursor)
    if cleaned_cursor:
        params["cursor"] = cleaned_cursor
    return f"{SHINIGAMI_API_BASE_URL}/chapter/{manga_id}/list?{urlencode(params)}"


def build_shinigami_chapter_detail_url(chapter_id: str) -> str:
    return f"{SHINIGAMI_API_BASE_URL}/chapter/detail/{chapter_id}"


def build_shinigami_series_url(manga_id: str | None) -> str | None:
    cleaned_id = clean_text(manga_id)
    if not cleaned_id:
        return None
    return f"{SHINIGAMI_BASE_URL}/series/{cleaned_id}/"


def clean_shinigami_series_title(raw_title: str | None) -> str:
    title = clean_text(raw_title)
    title = re.sub(r"\s+Chara Image$", "", title, flags=re.IGNORECASE)
    title = re.sub(r"^\s*UP\s+", "", title, flags=re.IGNORECASE)
    return title


def parse_shinigami_iso_datetime(value: str | None) -> datetime | None:
    cleaned = clean_text(value)
    if not cleaned:
        return None

    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


def format_shinigami_latest_chapter(chapter_number: float | int | None) -> str | None:
    if chapter_number is None:
        return None

    try:
        numeric_value = float(chapter_number)
    except (TypeError, ValueError):
        return None

    if numeric_value.is_integer():
        return f"CH.{int(numeric_value)}"
    return f"CH.{numeric_value}"


def format_shinigami_relative_time(value: str | None) -> str | None:
    published_at = parse_shinigami_iso_datetime(value)
    if published_at is None:
        return None

    current_time = now_wib()
    delta = current_time - published_at.astimezone(current_time.tzinfo)
    total_seconds = max(int(delta.total_seconds()), 0)

    if total_seconds < 60:
        return "UP"

    total_minutes = total_seconds // 60
    if total_minutes < 60:
        return f"{total_minutes}m"

    total_hours = total_minutes // 60
    if total_hours < 24:
        return f"{total_hours}h"

    total_days = total_hours // 24
    if total_days < 7:
        return f"{total_days}d"

    total_weeks = total_days // 7
    if total_weeks < 5:
        return f"{total_weeks}w"

    total_months = total_days // 30
    if total_months < 12:
        return f"{total_months}mo"

    total_years = total_days // 365
    return f"{max(total_years, 1)}y"


def parse_shinigami_has_next(payload: dict[str, Any]) -> bool:
    meta = payload.get("meta") or {}
    return bool(meta.get("has_next"))


def parse_shinigami_next_cursor(payload: dict[str, Any]) -> str | None:
    meta = payload.get("meta") or {}
    return clean_text(meta.get("next_cursor")) or None


def parse_shinigami_total_pages(payload: dict[str, Any]) -> int:
    meta = payload.get("meta") or {}
    return max(int(meta.get("total_page") or 1), 1)


def parse_shinigami_total_count(payload: dict[str, Any]) -> int | None:
    """Ambil perkiraan total komik dari `meta.total_record` atau agregat `facet`."""
    meta = payload.get("meta") or {}
    total_record = meta.get("total_record")
    if total_record is not None:
        try:
            return max(int(total_record), 0)
        except (TypeError, ValueError):
            pass

    facets = payload.get("facet") or {}
    if not isinstance(facets, dict):
        return None

    for facet_key in ("taxonomy.Format.name", "taxonomy.Type.name"):
        bucket = facets.get(facet_key)
        if not isinstance(bucket, dict) or not bucket:
            continue
        total = 0
        valid = False
        for value in bucket.values():
            try:
                total += max(int(value), 0)
                valid = True
            except (TypeError, ValueError):
                continue
        if valid and total > 0:
            return total

    return None


def pick_shinigami_cover_url(item: dict[str, Any]) -> str | None:
    """Pilih URL cover terbaik sesuai helper `c4` di frontend Shinigami."""
    return (
        clean_text(item.get("cover_portrait_url"))
        or clean_text(item.get("cover_image_url"))
        or None
    )


def normalize_shinigami_manga_list_item(item: dict[str, Any]) -> dict[str, Any] | None:
    title = clean_shinigami_series_title(item.get("title"))
    source_url = build_shinigami_series_url(item.get("manga_id"))
    if not title or not source_url:
        return None

    latest_chapter_number = item.get("latest_chapter_number")

    return {
        "title": title,
        "source_url": source_url,
        "latest_chapter": format_shinigami_latest_chapter(latest_chapter_number),
        "latest_chapter_number": float(latest_chapter_number)
        if latest_chapter_number is not None
        else None,
        "latest_release": format_shinigami_relative_time(item.get("latest_chapter_time")),
        "cover_image_url": pick_shinigami_cover_url(item),
        "rating": item.get("user_rate"),
        "total_view": item.get("view_count"),
        "status": item.get("status"),
        "raw": item,
    }


def parse_shinigami_manga_list_payload(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], bool]:
    if payload.get("retcode") != 0:
        raise RuntimeError(payload.get("message") or "Unknown Shinigami API error")

    items: list[dict[str, Any]] = []
    for raw_item in payload.get("data") or []:
        normalized = normalize_shinigami_manga_list_item(raw_item)
        if normalized is not None:
            items.append(normalized)

    return items, parse_shinigami_has_next(payload)
