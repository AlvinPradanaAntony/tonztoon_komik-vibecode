"""
Tonztoon Komik — Shinigami Scraper

Scraper untuk https://e.shinigami.asia/ dengan flow DB-backed seperti source lain.

Catatan implementasi:
- Situs memakai SPA/SvelteKit client-side routing.
- Semua operasi utama memakai endpoint resmi `https://api.shngm.io/v1`.
- Feed latest, katalog, detail manga, daftar chapter, dan chapter images
  diambil dari API resmi tanpa parsing DOM.
"""

import re
from datetime import datetime
from typing import Any
from urllib.parse import urljoin

import httpx

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.sources.shinigami_api import (
    DEFAULT_CHAPTER_LIST_PAGE_SIZE,
    SHINIGAMI_API_BASE_URL,
    SHINIGAMI_BASE_URL,
    build_shinigami_api_headers,
    build_shinigami_chapter_detail_url,
    build_shinigami_chapter_list_url,
    build_shinigami_chapter_url,
    build_shinigami_manga_list_url,
    build_shinigami_search_url,
    clean_shinigami_series_title,
    parse_shinigami_iso_datetime,
    parse_shinigami_manga_list_payload,
)


class ShinigamiScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Shinigami berbasis API resmi."""

    SOURCE_NAME = "shinigami"
    BASE_URL = SHINIGAMI_BASE_URL
    API_BASE_URL = SHINIGAMI_API_BASE_URL
    API_PAGE_SIZE = DEFAULT_CHAPTER_LIST_PAGE_SIZE

    def _build_api_headers(self, referer_url: str | None = None) -> dict[str, str]:
        return build_shinigami_api_headers(referer_url)

    async def _fetch_api_json(self, url: str, *, referer_url: str | None = None) -> dict[str, Any]:
        headers = self._build_api_headers(referer_url)

        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            payload = response.json()

        if payload.get("retcode") != 0:
            raise RuntimeError(
                f"API Shinigami gagal untuk {url}: "
                f"{payload.get('message') or 'unknown error'}"
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
        title = self._clean_text(chapter_title)
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
        page = 1
        total_pages = 1
        chapters: list[dict[str, Any]] = []

        while page <= total_pages:
            endpoint = build_shinigami_chapter_list_url(
                manga_id,
                page=page,
                page_size=self.API_PAGE_SIZE,
            )
            payload = await self._fetch_api_json(endpoint, referer_url=referer_url)
            meta = payload.get("meta") or {}
            total_pages = max(int(meta.get("total_page") or 1), 1)

            for item in payload.get("data") or []:
                chapter_number = item.get("chapter_number")
                chapter_id = self._clean_text(item.get("chapter_id"))
                if chapter_number is None or not chapter_id:
                    continue

                title = self._build_chapter_title(chapter_number, item.get("chapter_title"))
                chapter_url = build_shinigami_chapter_url(chapter_id)
                if not chapter_url:
                    continue
                chapters.append(
                    self._build_chapter_payload(
                        chapter_number=float(chapter_number),
                        title=title,
                        source_url=chapter_url,
                        release_date=self._parse_iso_datetime(item.get("release_date")),
                    )
                )

            page += 1

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    def _build_search_url(self, query: str | None = None) -> str:
        return build_shinigami_search_url(query)

    def _clean_series_title(self, raw_title: str | None) -> str:
        return clean_shinigami_series_title(raw_title)

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
        raw_items, total_pages = parse_shinigami_manga_list_payload(payload)
        if page > total_pages:
            return []

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
        """
        Feed latest diambil dari endpoint resmi `manga/list`.
        """
        return await self._fetch_search_page(page=page)

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Feed popular memakai ranking `rating` dari endpoint resmi `manga/list`.
        """
        return await self._fetch_search_page(page=page, sort="rating")

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        manga_id = self._extract_manga_id(url)
        detail_payload = await self._fetch_api_json(
            f"{self.API_BASE_URL}/manga/detail/{manga_id}",
            referer_url=url,
        )
        detail = detail_payload.get("data") or {}
        if not detail:
            raise RuntimeError(f"Tidak menemukan payload detail Shinigami untuk: {url}")

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

        chapters = await self._fetch_all_chapter_pages(manga_id, url)

        title = self._clean_text(detail.get("title"))
        if not title:
            raise RuntimeError(f"Tidak menemukan title pada payload detail Shinigami: {url}")

        return self._build_comic_payload(
            title=title,
            source_url=url,
            alternative_titles=self._clean_text(detail.get("alternative_title")) or None,
            cover_image_url=self._clean_text(detail.get("cover_image_url")) or None,
            author=", ".join(author_values) if author_values else None,
            artist=", ".join(artist_values) if artist_values else None,
            status=self._map_status_value(detail.get("status")),
            type=comic_type,
            synopsis=self._clean_text(detail.get("description")) or None,
            rating=self._parse_rating(str(detail.get("user_rate")) if detail.get("user_rate") is not None else None),
            total_view=int(detail["view_count"]) if detail.get("view_count") is not None else None,
            genres=genres,
            chapters=chapters,
        )

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        requested_fields = set(fields or ())
        manga_id = self._extract_manga_id(url)
        detail_payload = await self._fetch_api_json(
            f"{self.API_BASE_URL}/manga/detail/{manga_id}",
            referer_url=url,
        )
        detail = detail_payload.get("data") or {}
        if not detail:
            return {}

        taxonomy = detail.get("taxonomy") or {}
        author_values = [item.get("name") for item in taxonomy.get("Author", []) if item.get("name")]
        artist_values = [item.get("name") for item in taxonomy.get("Artist", []) if item.get("name")]
        format_values = [item.get("name") for item in taxonomy.get("Format", []) if item.get("name")]
        type_values = [item.get("name") for item in taxonomy.get("Type", []) if item.get("name")]

        comic_type = None
        if format_values:
            comic_type = self._parse_type_from_text(format_values[0])
        if comic_type is None and type_values:
            comic_type = self._parse_type_from_text(type_values[0])
        detail_patch = self._build_comic_payload(
            title=self._clean_text(detail.get("title")) or "",
            source_url=url,
            alternative_titles=self._clean_text(detail.get("alternative_title")) or None,
            cover_image_url=self._clean_text(detail.get("cover_image_url")) or None,
            author=", ".join(author_values) if author_values else None,
            artist=", ".join(artist_values) if artist_values else None,
            status=self._map_status_value(detail.get("status")),
            type=comic_type,
            synopsis=self._clean_text(detail.get("description")) or None,
            rating=self._parse_rating(
                str(detail.get("user_rate")) if detail.get("user_rate") is not None else None
            ),
            total_view=int(detail["view_count"]) if detail.get("view_count") is not None else None,
        )
        return self._build_metadata_patch(detail_patch, fields=requested_fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        chapter_id = self._extract_chapter_id(chapter_url)
        payload = await self._fetch_api_json(
            build_shinigami_chapter_detail_url(chapter_id),
            referer_url=chapter_url,
        )
        detail = payload.get("data") or {}
        chapter = detail.get("chapter") or {}
        base_url = self._clean_text(detail.get("base_url")) or self._clean_text(detail.get("base_url_low"))
        chapter_path = self._clean_text(chapter.get("path"))
        filenames = chapter.get("data") or []
        if not base_url or not chapter_path or not isinstance(filenames, list):
            return []

        images: list[dict[str, Any]] = []
        for filename in filenames:
            cleaned_filename = self._clean_text(str(filename))
            if not cleaned_filename:
                continue

            image_url = urljoin(f"{base_url.rstrip('/')}/", f"{chapter_path.lstrip('/')}{cleaned_filename}")
            images.append({"page": len(images) + 1, "url": image_url})

        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        return await self._fetch_search_page(page=page)

    async def get_source_comic_count(self) -> int | None:
        """Ambil total komik Shinigami dari metadata endpoint manga/list."""
        payload = await self._fetch_api_json(
            build_shinigami_manga_list_url(page=1),
            referer_url=self._build_search_url(None),
        )
        meta = payload.get("meta") or {}
        total = meta.get("total_record")
        if total is None:
            return None

        try:
            return max(int(total), 0)
        except (TypeError, ValueError):
            return None
