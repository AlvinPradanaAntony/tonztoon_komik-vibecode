"""
Tonztoon Komik — Voratoon Scraper

Implementasi source Voratoon menggunakan API-First via Next.js proxy endpoint
pada web canonical (https://voratoon.co) dengan resolusi DNS Cloudflare DoH.
Mendukung auto session handshake (vt_proxy), ekstraksi data JSON lengkap,
dan performa scraping tinggi tanpa DOM parsing.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from typing import Any

import httpx
from scrapling.fetchers import AsyncStealthySession

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.utils import clean_text
from scraper.sources.voratoon_api import (
    DEFAULT_POPULAR_TAKE,
    DEFAULT_SERIES_INDEX_TAKE,
    VORATOON_BASE_URL,
    build_voratoon_api_headers,
    build_voratoon_chapter_detail_url,
    build_voratoon_popular_url,
    build_voratoon_series_chapters_url,
    build_voratoon_series_detail_url,
    build_voratoon_series_index_url,
    coalesce_voratoon_total_view,
    ensure_voratoon_dns_configured,
    extract_cover_from_src,
    extract_voratoon_chapter_identity,
    extract_voratoon_series_slug,
    fetch_voratoon_api_json,
    get_voratoon_base_url,
    normalize_voratoon_web_url,
    parse_voratoon_iso_datetime,
)

logger = logging.getLogger("scraper.voratoon")


class _VoratoonBaseUrlDescriptor:
    """Descriptor agar BASE_URL bekerja baik di class maupun instance."""

    def __get__(self, instance, owner=None) -> str:
        return get_voratoon_base_url()


class VoratoonScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Voratoon berbasis API-first dengan browser fallback."""

    SOURCE_NAME = "voratoon"
    BASE_URL = _VoratoonBaseUrlDescriptor()

    _shared_session: AsyncStealthySession | None = None
    _shared_page: Any = None
    _SESSION_RESET_STATUSES = {403, 429}
    _CLOUDFLARE_CHALLENGE_MARKERS = (
        "just a moment",
        "cf-mitigated",
        "challenge-platform",
        "cf-chl-",
        "turnstile",
        "checking your browser",
        "performing security verification",
        "enable javascript and cookies",
    )

    @classmethod
    def _env_bool(cls, name: str, default: bool = False) -> bool:
        raw = os.getenv(name)
        if raw is None:
            return default
        return raw.strip().lower() in {"1", "true", "yes", "y", "on"}

    @classmethod
    def _headless(cls) -> bool:
        return cls._env_bool("VORATOON_HEADLESS", False)

    @classmethod
    def _browser_extra_flags(cls) -> list[str]:
        """Gunakan viewport realistis di CI; lokal tetap disembunyikan."""
        if os.getenv("GITHUB_ACTIONS", "").lower() == "true":
            return ["--window-size=1366,768"]
        return ["--window-position=-32000,-32000", "--window-size=200,200"]

    @classmethod
    async def get_session(cls) -> AsyncStealthySession:
        if cls._shared_session is None:
            logger.info("Membuka AsyncStealthySession Voratoon (Persistent)...")
            proxy = os.getenv("VORATOON_PROXY")
            if proxy:
                proxy = proxy.strip()
                masked_proxy = re.sub(r":[^:/@]+@", ":***@", proxy) if "@" in proxy else proxy
                logger.info("Menggunakan proxy untuk stealth session Voratoon: %s", masked_proxy)
            else:
                proxy = None

            cls._shared_session = AsyncStealthySession(
                headless=cls._headless(),
                real_chrome=True,
                block_webrtc=True,
                solve_cloudflare=True,
                google_search=True,
                timeout=120_000,
                extra_flags=cls._browser_extra_flags(),
                proxy=proxy,
            )
            await cls._shared_session.__aenter__()
        return cls._shared_session

    @classmethod
    async def close_shared_session(cls) -> None:
        """Tutup tab browser dan sesi persisten untuk mengosongkan resource."""
        if cls._shared_page is not None:
            try:
                if not cls._shared_page.is_closed():
                    await cls._shared_page.close()
            except Exception as exc:
                logger.warning("Gagal menutup page browser Voratoon: %s", exc)
            finally:
                cls._shared_page = None

        if cls._shared_session is not None:
            logger.info("Menutup AsyncStealthySession Voratoon...")
            session = cls._shared_session
            cls._shared_session = None
            try:
                await session.__aexit__(None, None, None)
            except Exception as exc:
                logger.warning("Gagal menutup AsyncStealthySession Voratoon: %s", exc)

    @classmethod
    async def reset_shared_session(cls, reason: str) -> None:
        """Paksa reset browser/session agar request berikutnya membuka identitas baru."""
        logger.warning("Reset AsyncStealthySession Voratoon: %s", reason)
        await cls.close_shared_session()
        logger.warning(
            "Retry berikutnya akan membuka browser/session baru dengan identitas lebih fresh."
        )

    @classmethod
    async def _get_or_create_page(cls, host: str) -> Any:
        session = await cls.get_session()
        if cls._shared_page is not None and not cls._shared_page.is_closed():
            return cls._shared_page

        logger.info("Membuka browser tab baru Voratoon untuk host %s...", host)
        page = await session.context.new_page()
        try:
            await page.goto(f"{host}/", timeout=60_000, wait_until="domcontentloaded")
            page_content = await page.content()
            if session._detect_cloudflare(page_content):
                logger.info("Cloudflare Turnstile terdeteksi di browser Voratoon, memecahkan challenge...")
                await session._cloudflare_solver(page)
                await page.wait_for_load_state("domcontentloaded")
            cls._shared_page = page
            return page
        except Exception as exc:
            try:
                await page.close()
            except Exception:
                pass
            cls._shared_page = None
            raise exc

    @classmethod
    async def _fetch_server_action_via_browser(
        cls,
        host: str,
        action_id: str,
        call_spec: dict[str, Any],
        timeout_ms: int = 60_000,
    ) -> str:
        """Mengeksekusi Next.js Server Action dari dalam browser context yang telah terautentikasi WAF."""
        logger.info("Stealth Server Action fallback (Cloudflare) Voratoon: path=%s", call_spec.get("path"))
        page = await cls._get_or_create_page(host)
        js_code = """
        async ([actionId, callSpec]) => {
            const resp = await window.fetch('/', {
                method: 'POST',
                headers: {
                    'Next-Action': actionId,
                    'Accept': 'text/x-component',
                    'Content-Type': 'text/plain;charset=UTF-8'
                },
                body: JSON.stringify([[callSpec]])
            });
            const text = await resp.text();
            return {
                status: resp.status,
                text: text
            };
        }
        """
        try:
            res = await asyncio.wait_for(
                page.evaluate(js_code, [action_id, call_spec]),
                timeout=timeout_ms / 1000.0,
            )
        except Exception as exc:
            logger.warning(
                "Error evaluasi JavaScript Server Action di browser: %s. Mencoba re-create page...",
                exc,
            )
            if cls._shared_page is not None:
                try:
                    await cls._shared_page.close()
                except Exception:
                    pass
                cls._shared_page = None
            page = await cls._get_or_create_page(host)
            res = await asyncio.wait_for(
                page.evaluate(js_code, [action_id, call_spec]),
                timeout=timeout_ms / 1000.0,
            )

        status = res.get("status", 0)
        if status == 200:
            return res.get("text", "")

        if status in cls._SESSION_RESET_STATUSES or 500 <= status <= 599:
            await cls.reset_shared_session(f"Browser Server Action Voratoon mengembalikan HTTP {status}")

        raise RuntimeError(f"Browser Server Action Voratoon gagal dengan status HTTP {status}")

    async def close(self) -> None:
        """Cleanup hook untuk pipeline scraper/sync."""
        await self.close_shared_session()

    def __init__(self):
        super().__init__()
        ensure_voratoon_dns_configured()

    def _build_api_headers(self, referer_url: str | None = None) -> dict[str, str]:
        return build_voratoon_api_headers(referer_url)

    async def _fetch_api_json(
        self,
        api_url: str,
        *,
        referer_url: str | None = None,
        timeout: float = 30.0,
    ) -> dict[str, Any]:
        """Method pembantu API dengan session management dan browser fallback."""
        return await fetch_voratoon_api_json(
            api_url,
            referer_url=referer_url,
            timeout=timeout,
            browser_fallback_handler=self._fetch_server_action_via_browser,
        )

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
        return extract_cover_from_src(cleaned)

    def _parse_series_item(self, item: dict[str, Any]) -> dict[str, Any] | None:
        """Parser data series dari response JSON API Voratoon."""
        data = item.get("data") or {}
        metadata = item.get("metadata") or {}
        data_metadata = item.get("dataMetadata") or {}

        slug = clean_text(data.get("slug") or item.get("slug"))
        title = clean_text(data.get("title") or item.get("title"))
        if not slug or not title:
            return None

        cover = self._normalize_cover_url(data.get("coverImage") or data.get("cover"))
        status = self._normalize_status(data.get("status"))
        comic_type = self._parse_type_from_text(data.get("format") or data.get("type")) or "manga"

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

        total_chapters = data.get("totalChapters")
        latest_chapter = None
        latest_chapter_number = None
        latest_chapter_url = None
        if total_chapters:
            try:
                ch_num = float(total_chapters)
                latest_chapter = f"Chapter {total_chapters}"
                latest_chapter_number = ch_num
                latest_chapter_url = f"{self.BASE_URL}/series/{slug}/chapter/{total_chapters}"
            except (ValueError, TypeError):
                pass

        return self._build_comic_payload(
            title=title,
            source_url=f"{self.BASE_URL}/series/{slug}",
            slug=slug,
            cover_image_url=cover,
            type=comic_type,
            status=status,
            rating=rating,
            total_view=total_view,
            genres=genres,
            author=clean_text(data.get("author")) or None,
            synopsis=clean_text(data.get("synopsis")) or None,
            latest_chapter=latest_chapter,
            latest_chapter_url=latest_chapter_url,
            latest_chapter_number=latest_chapter_number,
            raw=item,
        )

    def _parse_api_chapter_items(self, series_slug: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Parser chapter dari response JSON API Voratoon."""
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
        endpoint = build_voratoon_series_index_url(page=1, take=1, include_meta=True)
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
            include_meta=True,
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
        """Ambil daftar komik keseluruhan (direktori/katalog berurutan)."""
        endpoint = build_voratoon_series_index_url(
            page=page,
            take=DEFAULT_SERIES_INDEX_TAKE,
            sort="title",
            sort_order="asc",
            include_meta=True,
        )
        payload = await self._fetch_api_json(endpoint)
        items = payload.get("data") or []
        comics_data: list[dict[str, Any]] = []

        for raw_item in items:
            parsed = self._parse_series_item(raw_item)
            if parsed is not None:
                comics_data.append(parsed)

        return comics_data

    async def search(self, query: str, page: int = 1) -> list[dict[str, Any]]:
        """Cari komik berdasarkan judul melalui API Voratoon."""
        cleaned_query = clean_text(query)
        if not cleaned_query:
            return []

        endpoint = build_voratoon_series_index_url(
            page=page,
            query=cleaned_query,
            take=DEFAULT_SERIES_INDEX_TAKE,
            include_meta=True,
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
        """Ambil detail komik dan daftar lengkap chapternya via API Voratoon."""
        normalized_url = normalize_voratoon_web_url(url)
        slug = self._extract_series_slug(normalized_url)
        detail_endpoint = build_voratoon_series_detail_url(slug, include_meta=True)
        chapters_endpoint = build_voratoon_series_chapters_url(slug)

        try:
            detail_payload, chapters_payload = await asyncio.gather(
                self._fetch_api_json(detail_endpoint, referer_url=normalized_url),
                self._fetch_api_json(chapters_endpoint, referer_url=normalized_url),
            )
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                raise ValueError(f"Komik Voratoon tidak ditemukan (404): {url}") from exc
            raise

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
        """Ambil semua URL gambar dari satu chapter Voratoon."""
        normalized_url = normalize_voratoon_web_url(chapter_url)
        slug, chapter_number = self._extract_chapter_identity(normalized_url)
        endpoint = build_voratoon_chapter_detail_url(slug, chapter_number)

        try:
            payload = await self._fetch_api_json(endpoint, referer_url=normalized_url)
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                logger.warning("Chapter Voratoon %s/%s tidak ditemukan (404)", slug, chapter_number)
                return []
            raise

        data = payload.get("data") or {}
        inner_data = data.get("data") or {}
        raw_images = inner_data.get("images") or data.get("images") or []

        from app.services.image_service import normalize_voratoon_image_url

        images: list[dict[str, Any]] = []
        for idx, img_url in enumerate(raw_images, start=1):
            cleaned_url = clean_text(img_url)
            if cleaned_url:
                images.append({"page": idx, "url": normalize_voratoon_image_url(cleaned_url)})

        return images
