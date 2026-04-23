"""
Tonztoon Komik — Komikcast Scraper

Implementasi source Komikcast yang sepenuhnya memakai backend API resmi
`https://be.komikcast.cc`.

Frontend `https://v1.komikcast.fit` hanya bertindak sebagai SPA consumer dari
API tersebut, jadi scraper ini sengaja tidak lagi membawa fallback parsing DOM
atau browser session. Semua method publik mengambil data langsung dari endpoint
JSON resmi source.
"""

import logging
from typing import Any

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.utils import clean_text
from scraper.sources.komikcast_api import (
    KOMIKCAST_API_BASE_URL,
    KOMIKCAST_BASE_URL,
    build_komikcast_chapter_detail_url,
    build_komikcast_popular_url,
    build_komikcast_series_chapters_url,
    build_komikcast_series_detail_url,
    build_komikcast_series_index_url,
    coalesce_komikcast_total_view,
    extract_komikcast_chapter_identity,
    extract_komikcast_series_slug,
    fetch_komikcast_api_json,
    parse_komikcast_iso_datetime,
    sum_komikcast_chapter_views,
)

logger = logging.getLogger("scraper.komikcast")


class KomikcastScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Komikcast berbasis backend API resmi source."""

    SOURCE_NAME = "komikcast"
    BASE_URL = KOMIKCAST_BASE_URL
    API_BASE_URL = KOMIKCAST_API_BASE_URL

    async def _fetch_api_json(self, api_url: str) -> dict[str, Any]:
        logger.info("API fetch Komikcast: %s", api_url)
        return await fetch_komikcast_api_json(api_url)

    def _extract_series_slug(self, url: str) -> str:
        return extract_komikcast_series_slug(url)

    def _extract_chapter_identity(self, chapter_url: str) -> tuple[str, str]:
        return extract_komikcast_chapter_identity(chapter_url)

    def _sum_chapter_views(self, chapter_items: list[dict[str, Any]]) -> int | None:
        return sum_komikcast_chapter_views(chapter_items)

    def _coalesce_total_view(
        self,
        *,
        item_data: dict[str, Any],
        item_metadata: dict[str, Any],
        item_data_metadata: dict[str, Any],
    ) -> int | None:
        return coalesce_komikcast_total_view(
            item_data=item_data,
            item_metadata=item_metadata,
            item_data_metadata=item_data_metadata,
        )

    def _parse_api_chapter_items(self, series_slug: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        chapters: list[dict[str, Any]] = []

        for item in items:
            chapter_data = item.get("data") or {}
            chapter_index = chapter_data.get("index")
            if chapter_index is None:
                continue

            raw_title = clean_text(chapter_data.get("title"))
            chapter_title = raw_title or f"Chapter {chapter_index}"
            chapters.append(
                    self._build_chapter_payload(
                        chapter_number=float(chapter_index),
                        title=chapter_title,
                        source_url=f"{self.BASE_URL}/series/{series_slug}/chapter/{chapter_index}",
                        release_date=parse_komikcast_iso_datetime(item.get("createdAt")),
                    )
                )

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    def _parse_popular_series_items(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for item in items:
            try:
                data = item.get("data") or {}
                metadata = item.get("metadata") or {}
                data_metadata = item.get("dataMetadata") or {}
                slug = clean_text(data.get("slug"))
                title = clean_text(data.get("title"))
                if not slug or not title:
                    continue

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=f"{self.BASE_URL}/series/{slug}",
                        cover_image_url=clean_text(data.get("coverImage")) or None,
                        alternative_titles=clean_text(data.get("nativeTitle")) or None,
                        author=clean_text(data.get("author")) or None,
                        status=self._normalize_status(data.get("status")),
                        type=clean_text(data.get("format")) or None,
                        synopsis=clean_text(data.get("synopsis")) or None,
                        rating=self._parse_rating(
                            str(data.get("rating")) if data.get("rating") is not None else None
                        ),
                        total_view=self._coalesce_total_view(
                            item_data=data,
                            item_metadata=metadata,
                            item_data_metadata=data_metadata,
                        ),
                        genres=[
                            clean_text(genre.get("data", {}).get("name"))
                            for genre in data.get("genres") or []
                            if clean_text(genre.get("data", {}).get("name"))
                        ],
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komikcast popular API item: %s", exc)
                continue

        return comics_data

    async def _fetch_series_index(self, *, page: int = 1, query: str | None = None) -> dict[str, Any]:
        """
        Ambil data katalog langsung dari backend JSON Komikcast.

        SPA `/comics?page=N` tidak membaca query `page` dari URL awal; pagination
        dilakukan lewat request XHR ke `be.komikcast.cc/series`. Karena itu full
        sync/latest harus memakai endpoint ini agar page > 1 tidak selalu
        mengembalikan 12 item halaman pertama.
        """
        api_url = build_komikcast_series_index_url(page=page, query=query)
        return await self._fetch_api_json(api_url)

    def _parse_series_index_items(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for item in items:
            try:
                data = item.get("data") or {}
                slug = clean_text(data.get("slug"))
                title = clean_text(data.get("title"))
                if not slug or not title:
                    continue

                latest_chapter = None
                latest_chapter_number = None
                chapters = item.get("chapters") or []
                if chapters:
                    chapter_index = chapters[0].get("chapterIndex")
                    if chapter_index is not None:
                        latest_chapter_number = float(chapter_index)
                        latest_chapter = f"Chapter {chapter_index}"

                genres = [
                    clean_text(genre.get("data", {}).get("name"))
                    for genre in data.get("genres") or []
                    if clean_text(genre.get("data", {}).get("name"))
                ]

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=f"{self.BASE_URL}/series/{slug}",
                        cover_image_url=clean_text(data.get("coverImage")) or None,
                        alternative_titles=clean_text(data.get("nativeTitle")) or None,
                        author=clean_text(data.get("author")) or None,
                        status=self._normalize_status(data.get("status")),
                        type=clean_text(data.get("format")) or None,
                        synopsis=clean_text(data.get("synopsis")) or None,
                        rating=self._parse_rating(
                            str(data.get("rating")) if data.get("rating") is not None else None
                        ),
                        genres=genres,
                        latest_chapter=latest_chapter,
                        latest_chapter_number=latest_chapter_number,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komikcast series index item: %s", exc)
                continue

        return comics_data

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Feed latest diambil dari endpoint JSON backend, bukan query URL SPA.

        Ini penting agar page > 1 benar-benar berpindah halaman, bukan mengulang
        12 item pertama dari `/comics`.
        """
        payload = await self._fetch_series_index(page=page)
        return self._parse_series_index_items(payload.get("data") or [])

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Feed popular memakai endpoint resmi `most-read` dari backend source.

        Endpoint ini juga masih dipanggil frontend halaman `/populer`, jadi
        scraper tidak perlu membuka halaman SPA atau membaca kartu populer dari
        DOM lagi.
        """
        api_url = build_komikcast_popular_url(page=page)
        payload = await self._fetch_api_json(api_url)
        return self._parse_popular_series_items(payload.get("data") or [])

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        series_slug = self._extract_series_slug(url)
        detail_payload = await self._fetch_api_json(
            build_komikcast_series_detail_url(series_slug)
        )
        chapters_payload = await self._fetch_api_json(
            build_komikcast_series_chapters_url(series_slug)
        )

        detail = detail_payload.get("data") or {}
        series_data = detail.get("data") or {}
        if not series_data:
            raise RuntimeError(f"Tidak menemukan payload detail Komikcast: {url}")

        chapter_items = chapters_payload.get("data") or []
        chapters = self._parse_api_chapter_items(series_slug, chapter_items)

        total_view = self._sum_chapter_views(chapter_items)
        if total_view is None:
            total_view = self._coalesce_total_view(
                item_data=series_data,
                item_metadata=detail.get("metadata") or {},
                item_data_metadata=detail.get("dataMetadata") or {},
            )

        return self._build_comic_payload(
            title=clean_text(series_data.get("title")),
            source_url=url,
            alternative_titles=clean_text(series_data.get("nativeTitle")) or None,
            cover_image_url=clean_text(series_data.get("coverImage")) or None,
            author=clean_text(series_data.get("author")) or None,
            status=self._normalize_status(series_data.get("status")),
            type=self._parse_type_from_text(series_data.get("format")),
            synopsis=clean_text(series_data.get("synopsis")) or None,
            rating=self._parse_rating(
                str(series_data.get("rating")) if series_data.get("rating") is not None else None
            ),
            total_view=total_view,
            genres=[
                clean_text(genre.get("data", {}).get("name"))
                for genre in series_data.get("genres") or []
                if clean_text(genre.get("data", {}).get("name"))
            ],
            chapters=chapters,
        )

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        requested_fields = set(fields or ())
        series_slug = self._extract_series_slug(url)
        detail_payload = await self._fetch_api_json(
            build_komikcast_series_detail_url(series_slug)
        )
        detail = detail_payload.get("data") or {}
        series_data = detail.get("data") or {}
        if not series_data:
            return {}

        total_view = None
        if not requested_fields or "total_view" in requested_fields:
            chapters_payload = await self._fetch_api_json(
                build_komikcast_series_chapters_url(series_slug)
            )
            chapter_items = chapters_payload.get("data") or []
            total_view = self._sum_chapter_views(chapter_items)

        if total_view is None:
            total_view = self._coalesce_total_view(
                item_data=series_data,
                item_metadata=detail.get("metadata") or {},
                item_data_metadata=detail.get("dataMetadata") or {},
            )
        detail_patch = self._build_comic_payload(
            title=clean_text(series_data.get("title")) or "",
            source_url=url,
            alternative_titles=clean_text(series_data.get("nativeTitle")) or None,
            cover_image_url=clean_text(series_data.get("coverImage")) or None,
            author=clean_text(series_data.get("author")) or None,
            artist=None,
            status=self._normalize_status(series_data.get("status")),
            type=self._parse_type_from_text(series_data.get("format")),
            synopsis=clean_text(series_data.get("synopsis")) or None,
            rating=self._parse_rating(
                str(series_data.get("rating")) if series_data.get("rating") is not None else None
            ),
            total_view=total_view,
        )
        return self._build_metadata_patch(detail_patch, fields=requested_fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        series_slug, chapter_number = self._extract_chapter_identity(chapter_url)
        payload = await self._fetch_api_json(
            build_komikcast_chapter_detail_url(series_slug, chapter_number)
        )
        chapter_data = (payload.get("data") or {}).get("data") or {}

        images: list[dict[str, Any]] = []
        for page_number, image_url in enumerate(chapter_data.get("images") or [], start=1):
            cleaned_url = clean_text(image_url)
            if not cleaned_url:
                continue
            images.append({"page": page_number, "url": cleaned_url})

        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        payload = await self._fetch_series_index(page=page)
        return self._parse_series_index_items(payload.get("data") or [])

    async def get_source_comic_count(self) -> int | None:
        """Ambil total komik Komikcast dari metadata endpoint katalog resmi."""
        payload = await self._fetch_series_index(page=1)
        meta = payload.get("meta") or {}
        total = meta.get("total")
        if total is None:
            return None

        try:
            return max(int(total), 0)
        except (TypeError, ValueError):
            return None
