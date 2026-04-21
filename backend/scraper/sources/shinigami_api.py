"""
Shared helper untuk endpoint API Shinigami yang dipakai lintas scraper.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any
from urllib.parse import quote, urlencode

from scraper.time_utils import now_wib

SHINIGAMI_BASE_URL = "https://e.shinigami.asia"
SHINIGAMI_API_BASE_URL = "https://api.shngm.io/v1"
DEFAULT_MANGA_LIST_PAGE_SIZE = 24
DEFAULT_CHAPTER_LIST_PAGE_SIZE = 100


def _clean_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def build_shinigami_api_headers(referer_url: str | None = None) -> dict[str, str]:
    referer = referer_url or f"{SHINIGAMI_BASE_URL}/"
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
    cleaned_query = _clean_text(query)
    if not cleaned_query:
        return f"{SHINIGAMI_BASE_URL}/search"
    return f"{SHINIGAMI_BASE_URL}/search?q={quote(cleaned_query)}"


def build_shinigami_manga_list_params(
    *,
    page: int = 1,
    page_size: int = DEFAULT_MANGA_LIST_PAGE_SIZE,
    query: str | None = None,
    sort: str = "latest",
    sort_order: str = "desc",
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "page": page,
        "page_size": page_size,
        "genre_include_mode": "or",
        "genre_exclude_mode": "or",
        "sort": sort,
        "sort_order": sort_order,
    }

    cleaned_query = _clean_text(query)
    if cleaned_query:
        params["q"] = cleaned_query

    return params


def build_shinigami_manga_list_url(
    *,
    page: int = 1,
    page_size: int = DEFAULT_MANGA_LIST_PAGE_SIZE,
    query: str | None = None,
    sort: str = "latest",
    sort_order: str = "desc",
) -> str:
    params = build_shinigami_manga_list_params(
        page=page,
        page_size=page_size,
        query=query,
        sort=sort,
        sort_order=sort_order,
    )
    return f"{SHINIGAMI_API_BASE_URL}/manga/list?{urlencode(params)}"


def build_shinigami_series_url(manga_id: str | None) -> str | None:
    cleaned_id = _clean_text(manga_id)
    if not cleaned_id:
        return None
    return f"{SHINIGAMI_BASE_URL}/series/{cleaned_id}/"


def clean_shinigami_series_title(raw_title: str | None) -> str:
    title = _clean_text(raw_title)
    title = re.sub(r"\s+Chara Image$", "", title, flags=re.IGNORECASE)
    title = re.sub(r"^\s*UP\s+", "", title, flags=re.IGNORECASE)
    return title


def parse_shinigami_iso_datetime(value: str | None) -> datetime | None:
    cleaned = _clean_text(value)
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


def parse_shinigami_total_pages(payload: dict[str, Any]) -> int:
    meta = payload.get("meta") or {}
    return max(int(meta.get("total_page") or 1), 1)


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
        "cover_image_url": clean_shinigami_series_title(item.get("cover_image_url")) or None,
        "rating": item.get("user_rate"),
        "total_view": item.get("view_count"),
        "status": item.get("status"),
        "raw": item,
    }


def parse_shinigami_manga_list_payload(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    if payload.get("retcode") != 0:
        raise RuntimeError(payload.get("message") or "Unknown Shinigami API error")

    items: list[dict[str, Any]] = []
    for raw_item in payload.get("data") or []:
        normalized = normalize_shinigami_manga_list_item(raw_item)
        if normalized is not None:
            items.append(normalized)

    return items, parse_shinigami_total_pages(payload)
