"""
Tonztoon Komik — Shinigami Scraper

Scraper untuk https://s1.shinigami.mx/ dengan flow DB-backed seperti source lain.

Catatan implementasi:
- Situs memakai SPA Vite/React client-side routing.
- Semua operasi utama memakai endpoint resmi `https://api.shinigami.io/v1`.
- Feed latest, katalog, detail manga, daftar chapter, dan chapter images
  diambil dari API JSON resmi tanpa parsing DOM, dengan fallback Scrapling AsyncFetcher.
"""

import logging
import re
from datetime import datetime
from typing import Any
from urllib.parse import urljoin

import httpx
from scrapling.fetchers import AsyncFetcher

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.utils import clean_text
from scraper.sources.shinigami_api import (
    DEFAULT_CHAPTER_LIST_PAGE_SIZE,
    SHINIGAMI_API_BASE_URL,
    SHINIGAMI_BASE_URL,
    build_shinigami_api_headers,
    build_shinigami_chapter_detail_url,
    build_shinigami_chapter_list_url,
    build_shinigami_chapter_url,
    build_shinigami_manga_detail_url,
    build_shinigami_manga_list_url,
    build_shinigami_search_url,
    build_shinigami_series_url,
    clean_shinigami_series_title,
    parse_shinigami_has_next,
    parse_shinigami_iso_datetime,
    parse_shinigami_manga_list_payload,
    parse_shinigami_next_cursor,
    parse_shinigami_total_count,
    pick_shinigami_cover_url,
)

logger = logging.getLogger("scraper.shinigami")

_SCRAPLING_FALLBACK_STATUSES = frozenset({403, 429})


class ShinigamiScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Shinigami berbasis API resmi."""

    SOURCE_NAME = "shinigami"
    BASE_URL = SHINIGAMI_BASE_URL
    API_BASE_URL = SHINIGAMI_API_BASE_URL
    API_PAGE_SIZE = DEFAULT_CHAPTER_LIST_PAGE_SIZE

    def _build_api_headers(self, referer_url: str | None = None) -> dict[str, str]:
        return build_shinigami_api_headers(referer_url)

    async def _fetch_api_json_via_scrapling(
        self,
        url: str,
        *,
        headers: dict[str, str],
    ) -> dict[str, Any]:
        response = await AsyncFetcher.get(
            url,
            headers=headers,
            impersonate="chrome",
            timeout=30,
        )
        if getattr(response, "status", 0) >= 400:
            raise RuntimeError(
                f"Scrapling HTTP {getattr(response, 'status', '?')} untuk {url}"
            )
        return response.json()

    async def _fetch_api_json(self, url: str, *, referer_url: str | None = None) -> dict[str, Any]:
        headers = self._build_api_headers(referer_url)
        payload: dict[str, Any] | None = None

        try:
            async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
                response = await client.get(url, headers=headers)
                if response.status_code in _SCRAPLING_FALLBACK_STATUSES:
                    logger.info(
                        "Shinigami httpx status %s untuk %s; mencoba fallback Scrapling AsyncFetcher.",
                        response.status_code,
                        url,
                    )
                    payload = await self._fetch_api_json_via_scrapling(url, headers=headers)
                else:
                    response.raise_for_status()
                    payload = response.json()
        except httpx.HTTPError as exc:
            logger.info(
                "Shinigami httpx gagal untuk %s (%s); mencoba fallback Scrapling AsyncFetcher.",
                url,
                exc,
            )
            payload = await self._fetch_api_json_via_scrapling(url, headers=headers)

        if not isinstance(payload, dict) or payload.get("retcode") != 0:
            message = payload.get("message") if isinstance(payload, dict) else None
            raise RuntimeError(
                f"API Shinigami gagal untuk {url}: "
                f"{message or 'unknown error'}"
            )

        return payload

    def _extract_manga_id(self, url: str) -> str:
        match = re.search(r"/series/([0-9a-f-]+)", url, re.IGNORECASE)
        if not match:
            raise ValueError(f"Tidak dapat mengekstrak manga_id dari URL: {url}")
        return match.group(1)

    def _extract_chapter_id(self, url: str) -> str:
        match = re.search(r"/chapter/([0-9a-f-]+)", url, re.IGNORECASE)
        if not match:
            raise ValueError(f"Tidak dapat mengekstrak chapter_id dari URL: {url}")
        return match.group(1)

    def _parse_iso_datetime(self, value: str | None) -> datetime | None:
        return parse_shinigami_iso_datetime(value)

    def _build_chapter_title(self, chapter_number: float | int | None, chapter_title: str | None) -> str:
        title = clean_text(chapter_title)
        if title:
            return title

        if chapter_number is None:
            return ""

        if float(chapter_number).is_integer():
            return f"Chapter {int(chapter_number)}"
        return f"Chapter {chapter_number}"

    def _map_status_value(self, raw_status: Any) -> str | None:
        if raw_status is None:
            return None

        if isinstance(raw_status, int):
            return {
                1: "ongoing",
                2: "completed",
                3: "hiatus",
            }.get(raw_status)

        return self._normalize_status(str(raw_status))

    async def _fetch_all_chapter_pages(self, manga_id: str, referer_url: str) -> list[dict[str, Any]]:
        cursor: str | None = None
        seen_cursors: set[str] = set()
        seen_chapter_ids: set[str] = set()
        chapters: list[dict[str, Any]] = []

        while True:
            endpoint = build_shinigami_chapter_list_url(
                manga_id,
                limit=self.API_PAGE_SIZE,
                cursor=cursor,
            )
            payload = await self._fetch_api_json(endpoint, referer_url=referer_url)

            for item in payload.get("data") or []:
                chapter_number = item.get("chapter_number")
                chapter_id = clean_text(item.get("chapter_id"))
                if chapter_number is None or not chapter_id or chapter_id in seen_chapter_ids:
                    continue

                chapter_url = build_shinigami_chapter_url(chapter_id)
                if not chapter_url:
                    continue

                seen_chapter_ids.add(chapter_id)
                title = self._build_chapter_title(chapter_number, item.get("chapter_title"))
                chapters.append(
                    self._build_chapter_payload(
                        chapter_number=float(chapter_number),
                        title=title,
                        source_url=chapter_url,
                        release_date=self._parse_iso_datetime(item.get("release_date")),
                    )
                )

            has_next = parse_shinigami_has_next(payload)
            next_cursor = parse_shinigami_next_cursor(payload)
            if not has_next or not next_cursor or next_cursor in seen_cursors:
                break

            seen_cursors.add(next_cursor)
            cursor = next_cursor

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    def _build_search_url(self, query: str | None = None) -> str:
        return build_shinigami_search_url(query)

    def _clean_series_title(self, raw_title: str | None) -> str:
        return clean_shinigami_series_title(raw_title)

    def _extract_detail_fields(
        self,
        detail: dict[str, Any],
        source_url: str,
        *,
        chapters: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        taxonomy = detail.get("taxonomy") or {}
        genres = [item.get("name") for item in taxonomy.get("Genre", []) if item.get("name")]
        author_values = [item.get("name") for item in taxonomy.get("Author", []) if item.get("name")]
        artist_values = [item.get("name") for item in taxonomy.get("Artist", []) if item.get("name")]
        format_values = [item.get("name") for item in taxonomy.get("Format", []) if item.get("name")]
        type_values = [item.get("name") for item in taxonomy.get("Type", []) if item.get("name")]

        comic_type = None
        if format_values:
            comic_type = self._parse_type_from_text(format_values[0])
        if comic_type is None and type_values:
            comic_type = self._parse_type_from_text(type_values[0])

        extra: dict[str, Any] = {
            "alternative_titles": clean_text(detail.get("alternative_title")) or None,
            "cover_image_url": pick_shinigami_cover_url(detail),
            "author": ", ".join(author_values) if author_values else None,
            "artist": ", ".join(artist_values) if artist_values else None,
            "status": self._map_status_value(detail.get("status")),
            "type": comic_type,
            "synopsis": clean_text(detail.get("description")) or None,
            "rating": self._parse_rating(
                str(detail.get("user_rate")) if detail.get("user_rate") is not None else None
            ),
            "total_view": int(detail["view_count"]) if detail.get("view_count") is not None else None,
        }
        if chapters is not None:
            extra["genres"] = genres
            extra["chapters"] = chapters

        return self._build_comic_payload(
            title=clean_text(detail.get("title")) or "",
            source_url=source_url,
            **extra,
        )

    async def _fetch_search_page_via_api(
        self,
        *,
        page: int = 1,
        query: str | None = None,
        sort: str = "latest",
    ) -> list[dict[str, Any]]:
        payload = await self._fetch_api_json(
            build_shinigami_manga_list_url(page=page, query=query, sort=sort),
            referer_url=self._build_search_url(query),
        )
        raw_items, _has_next = parse_shinigami_manga_list_payload(payload)

        results: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        for item in raw_items:
            source_url = item["source_url"]
            if source_url in seen_urls:
                continue

            seen_urls.add(source_url)
            results.append(
                self._build_comic_payload(
                    title=item["title"],
                    source_url=source_url,
                    latest_chapter=item.get("latest_chapter"),
                    latest_chapter_number=item.get("latest_chapter_number"),
                    latest_release=item.get("latest_release"),
                    cover_image_url=item.get("cover_image_url"),
                )
            )

        return results

    async def _fetch_search_page(
        self,
        *,
        page: int = 1,
        query: str | None = None,
        sort: str = "latest",
    ) -> list[dict[str, Any]]:
        return await self._fetch_search_page_via_api(page=page, query=query, sort=sort)

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """Feed latest diambil dari endpoint resmi `manga/list`."""
        return await self._fetch_search_page(page=page, sort="latest")

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """Feed popular memakai ranking `popularity` dari endpoint resmi `manga/list`."""
        return await self._fetch_search_page(page=page, sort="popularity")

    async def search(self, query: str, page: int = 1) -> list[dict[str, Any]]:
        """Cari komik berdasarkan judul melalui endpoint resmi `manga/list`."""
        cleaned_query = clean_text(query)
        if not cleaned_query:
            return []
        return await self._fetch_search_page(page=page, query=cleaned_query, sort="latest")

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        manga_id = self._extract_manga_id(url)
        canonical_url = build_shinigami_series_url(manga_id) or url
        detail_payload = await self._fetch_api_json(
            build_shinigami_manga_detail_url(manga_id),
            referer_url=canonical_url,
        )
        detail = detail_payload.get("data") or {}
        if not detail:
            raise RuntimeError(f"Tidak menemukan payload detail Shinigami untuk: {url}")

        title = clean_text(detail.get("title"))
        if not title:
            raise RuntimeError(f"Tidak menemukan title pada payload detail Shinigami: {url}")

        chapters = await self._fetch_all_chapter_pages(manga_id, canonical_url)
        return self._extract_detail_fields(detail, canonical_url, chapters=chapters)

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        requested_fields = set(fields or ())
        manga_id = self._extract_manga_id(url)
        canonical_url = build_shinigami_series_url(manga_id) or url
        detail_payload = await self._fetch_api_json(
            build_shinigami_manga_detail_url(manga_id),
            referer_url=canonical_url,
        )
        detail = detail_payload.get("data") or {}
        if not detail:
            return {}

        detail_patch = self._extract_detail_fields(detail, canonical_url)
        return self._build_metadata_patch(detail_patch, fields=requested_fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        chapter_id = self._extract_chapter_id(chapter_url)
        payload = await self._fetch_api_json(
            build_shinigami_chapter_detail_url(chapter_id),
            referer_url=chapter_url,
        )
        detail = payload.get("data") or {}
        chapter = detail.get("chapter") or {}
        base_url = clean_text(detail.get("base_url")) or clean_text(detail.get("base_url_low"))
        chapter_path = clean_text(chapter.get("path"))
        filenames = chapter.get("data") or []
        if not base_url or not chapter_path or not isinstance(filenames, list):
            return []

        images: list[dict[str, Any]] = []
        for filename in filenames:
            cleaned_filename = clean_text(str(filename))
            if not cleaned_filename:
                continue

            image_url = urljoin(f"{base_url.rstrip('/')}/", f"{chapter_path.lstrip('/')}{cleaned_filename}")
            images.append({"page": len(images) + 1, "url": image_url})

        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        return await self._fetch_search_page(page=page)

    async def get_source_comic_count(self) -> int | None:
        """Ambil perkiraan total komik Shinigami dari metadata/facet endpoint `manga/list`."""
        try:
            payload = await self._fetch_api_json(
                build_shinigami_manga_list_url(page=1, page_size=1),
                referer_url=self._build_search_url(None),
            )
        except Exception:
            logger.warning("Gagal mengambil source_comic_count dari Shinigami", exc_info=True)
            return None

        return parse_shinigami_total_count(payload)
