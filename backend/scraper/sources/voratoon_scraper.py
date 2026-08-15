"""
Tonztoon Komik — Voratoon Scraper

Implementasi source Voratoon yang sepenuhnya memakai backend API resmi
`https://api.voratoon.com`.

Frontend `https://v1.voratoon.com` bertindak sebagai SPA/Next.js consumer dari
API tersebut. Scraper ini mengambil data langsung dari endpoint JSON resmi source
dengan integrasi Scrapling dan HTTP client asynchronous.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.utils import clean_text
from scraper.sources.voratoon_api import (
    DEFAULT_POPULAR_TAKE,
    DEFAULT_SERIES_INDEX_TAKE,
    VORATOON_API_BASE_URL,
    VORATOON_BASE_URL,
    build_voratoon_api_headers,
    build_voratoon_chapter_detail_url,
    build_voratoon_popular_url,
    build_voratoon_series_chapters_url,
    build_voratoon_series_detail_url,
    build_voratoon_series_index_url,
    coalesce_voratoon_total_view,
    extract_voratoon_chapter_identity,
    extract_voratoon_series_slug,
    parse_voratoon_iso_datetime,
)

logger = logging.getLogger("scraper.voratoon")


class VoratoonScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Voratoon berbasis backend API resmi source."""

    SOURCE_NAME = "voratoon"
    BASE_URL = VORATOON_BASE_URL
    API_BASE_URL = VORATOON_API_BASE_URL

    def _build_api_headers(self, referer_url: str | None = None) -> dict[str, str]:
        return build_voratoon_api_headers(referer_url)

    async def _fetch_api_json(self, api_url: str, *, referer_url: str | None = None) -> dict[str, Any]:
        headers = self._build_api_headers(referer_url)
        async with httpx.AsyncClient(timeout=35.0, follow_redirects=True) as client:
            response = await client.get(api_url, headers=headers)
            response.raise_for_status()
            payload = response.json()

        if payload.get("status") not in (200, None):
            raise RuntimeError(
                f"API Voratoon gagal untuk {api_url}: "
                f"{payload.get('message') or 'unknown error'}"
            )

        return payload

    def _extract_series_slug(self, url: str) -> str:
        return extract_voratoon_series_slug(url)

    def _extract_chapter_identity(self, chapter_url: str) -> tuple[str, str]:
        return extract_voratoon_chapter_identity(chapter_url)

    def _coalesce_total_view(
        self,
        *,
        item_data: dict[str, Any],
        item_metadata: dict[str, Any],
        item_data_metadata: dict[str, Any],
    ) -> int | None:
        return coalesce_voratoon_total_view(
            item_data=item_data,
            item_metadata=item_metadata,
            item_data_metadata=item_data_metadata,
        )

    def _normalize_cover_url(self, raw_cover: str | None) -> str | None:
        cleaned = clean_text(raw_cover)
        if not cleaned:
            return None
        return cleaned

    def _parse_series_item(self, item: dict[str, Any]) -> dict[str, Any] | None:
        data = item.get("data") or {}
        metadata = item.get("metadata") or {}
        data_metadata = item.get("dataMetadata") or {}

        slug = clean_text(data.get("slug") or item.get("slug"))
        title = clean_text(data.get("title") or item.get("title"))
        if not slug or not title:
            return None

        cover = self._normalize_cover_url(data.get("coverImage") or data.get("cover"))
        status = self._normalize_status(data.get("status"))
        comic_type = self._parse_type_from_text(data.get("format") or data.get("type"))

        raw_rating = data.get("rating")
        rating = self._parse_rating(str(raw_rating)) if raw_rating is not None else None

        total_view = self._coalesce_total_view(
            item_data=data,
            item_metadata=metadata,
            item_data_metadata=data_metadata,
        )

        genres = [
            clean_text(g.get("data", {}).get("name") if isinstance(g, dict) else g)
            for g in (data.get("genres") or [])
            if clean_text(g.get("data", {}).get("name") if isinstance(g, dict) else g)
        ]

        return {
            "title": title,
            "slug": slug,
            "source_url": f"{self.BASE_URL}/series/{slug}",
            "cover_image_url": cover,
            "type": comic_type,
            "status": status,
            "rating": rating,
            "total_view": total_view,
            "genres": genres,
            "author": clean_text(data.get("author")) or None,
            "synopsis": clean_text(data.get("synopsis")) or None,
            "raw": item,
        }

    def _parse_api_chapter_items(self, series_slug: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        chapters: list[dict[str, Any]] = []

        for item in items:
            chapter_data = item.get("data") or {}
            chapter_index = chapter_data.get("index")
            if chapter_index is None:
                continue

            raw_title = clean_text(chapter_data.get("title"))
            chapter_title = raw_title or f"Chapter {chapter_index}"
            chapter_url = f"{self.BASE_URL}/series/{series_slug}/chapter/{chapter_index}"

            chapters.append(
                self._build_chapter_payload(
                    chapter_number=float(chapter_index),
                    title=chapter_title,
                    source_url=chapter_url,
                    release_date=parse_voratoon_iso_datetime(item.get("createdAt")),
                )
            )

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    async def get_source_comic_count(self) -> int | None:
        """Ambil total komik yang tersedia langsung pada katalog Voratoon."""
        endpoint = build_voratoon_series_index_url(page=1, take=1)
        try:
            payload = await self._fetch_api_json(endpoint)
            meta = payload.get("meta") or {}
            total = meta.get("total")
            return int(total) if total is not None else None
        except Exception:
            logger.warning("Gagal mengambil source_comic_count dari Voratoon", exc_info=True)
            return None

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        """Ambil patch metadata ringan tanpa sync daftar chapter."""
        requested_fields = set(fields or set())
        should_fetch_total_view = not requested_fields or "total_view" in requested_fields
        should_fetch_rating = not requested_fields or "rating" in requested_fields
        should_fetch_status = not requested_fields or "status" in requested_fields
        should_fetch_cover = not requested_fields or "cover_image_url" in requested_fields

        slug = self._extract_series_slug(url)
        detail_url = build_voratoon_series_detail_url(slug, include_meta=True)
        payload = await self._fetch_api_json(detail_url, referer_url=url)
        item = payload.get("data") or {}
        item_data = item.get("data") or {}
        item_metadata = item.get("metadata") or {}
        item_data_metadata = item.get("dataMetadata") or {}

        patch: dict[str, Any] = {}

        if should_fetch_total_view:
            total_view = self._coalesce_total_view(
                item_data=item_data,
                item_metadata=item_metadata,
                item_data_metadata=item_data_metadata,
            )
            if total_view is not None:
                patch["total_view"] = total_view

        if should_fetch_rating:
            raw_rating = item_data.get("rating")
            if raw_rating is not None:
                rating = self._parse_rating(str(raw_rating))
                if rating is not None:
                    patch["rating"] = rating

        if should_fetch_status:
            status = self._normalize_status(item_data.get("status"))
            if status is not None:
                patch["status"] = status

        if should_fetch_cover:
            cover = self._normalize_cover_url(item_data.get("coverImage") or item_data.get("cover"))
            if cover is not None:
                patch["cover_image_url"] = cover

        return patch

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil daftar komik yang baru di-update dari API Voratoon."""
        endpoint = build_voratoon_series_index_url(
            page=page,
            take=DEFAULT_SERIES_INDEX_TAKE,
            sort="latest",
            sort_order="desc",
        )
        payload = await self._fetch_api_json(endpoint)
        items = payload.get("data") or []
        comics_data: list[dict[str, Any]] = []

        for raw_item in items:
            parsed = self._parse_series_item(raw_item)
            if parsed is not None:
                comics_data.append(parsed)

        return comics_data

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil daftar komik populer dari API Voratoon."""
        endpoint = build_voratoon_popular_url(page=page, take=DEFAULT_POPULAR_TAKE)
        payload = await self._fetch_api_json(endpoint)
        items = payload.get("data") or []
        comics_data: list[dict[str, Any]] = []

        for raw_item in items:
            parsed = self._parse_series_item(raw_item)
            if parsed is not None:
                comics_data.append(parsed)

        return comics_data

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil daftar komik keseluruhan (direktori/katalog)."""
        endpoint = build_voratoon_series_index_url(
            page=page,
            take=DEFAULT_SERIES_INDEX_TAKE,
            sort="title",
            sort_order="asc",
        )
        payload = await self._fetch_api_json(endpoint)
        items = payload.get("data") or []
        comics_data: list[dict[str, Any]] = []

        for raw_item in items:
            parsed = self._parse_series_item(raw_item)
            if parsed is not None:
                comics_data.append(parsed)

        return comics_data

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        """Ambil detail komik dan daftar lengkap chapternya."""
        slug = self._extract_series_slug(url)
        detail_endpoint = build_voratoon_series_detail_url(slug, include_meta=True)
        chapters_endpoint = build_voratoon_series_chapters_url(slug)

        detail_payload, chapters_payload = await asyncio.gather(
            self._fetch_api_json(detail_endpoint, referer_url=url),
            self._fetch_api_json(chapters_endpoint, referer_url=url),
        )

        item = detail_payload.get("data") or {}
        series_meta = self._parse_series_item(item)
        if not series_meta:
            raise ValueError(f"Payload detail Voratoon tidak valid untuk: {url}")

        raw_chapters = chapters_payload.get("data") or []
        chapters = self._parse_api_chapter_items(slug, raw_chapters)

        return {
            **series_meta,
            "source_url": f"{self.BASE_URL}/series/{slug}",
            "chapters": chapters,
        }

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        """Ambil semua URL gambar dari satu chapter."""
        slug, chapter_number = self._extract_chapter_identity(chapter_url)
        endpoint = build_voratoon_chapter_detail_url(slug, chapter_number)
        payload = await self._fetch_api_json(endpoint, referer_url=chapter_url)

        data = payload.get("data") or {}
        inner_data = data.get("data") or {}
        raw_images = inner_data.get("images") or data.get("images") or []

        images: list[dict[str, Any]] = []
        for idx, img_url in enumerate(raw_images, start=1):
            cleaned_url = clean_text(img_url)
            if cleaned_url:
                images.append({"page": idx, "url": cleaned_url})

        return images
