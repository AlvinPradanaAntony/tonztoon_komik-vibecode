"""
Tonztoon Komik — Komiku Asia Scraper

Scraper untuk https://01.komiku.asia/ menggunakan API resmi melalui Scrapling
`Fetcher` HTTP. Browser `AsyncStealthySession` dengan solver Cloudflare hanya
dibuka sebagai fallback ketika response mendapat status proteksi/server,
transport timeout, atau body Cloudflare challenge.

API contract summary (verified August 25, 2026 via Scrapling and Context7):
- `/api/v2/comics` provides paginated catalog, A-Z sorting, filters and search
  query parameters.
- `/api/v2/comics/latest-updates`, `/popular`, `/new` and `/trending` provide
  the source's listing feeds.
- `/api/v2/comics/search`, `/comics/{slug}`, `/comics/{id}/chapters`, and
  `/comics/{id}/chapters/id/{chapter_id}` provide search, detail, chapter
  metadata, and reader page URLs respectively.
- `/api/v2/comics/filters` provides the official catalog filter values.
- `/api/v2/me/*` is authenticated personal library state and is intentionally
  not used for public catalog or bookmark synchronization.

The active scraper therefore consumes JSON API responses only. Scrapling is
used as the HTTP/browser transport for the first-party API because the host can
return Cloudflare challenges to ordinary HTTP clients; no page DOM or Next.js
RSC payload is parsed by this source.
"""

import asyncio
import logging
import os
import re
from datetime import datetime, timezone
from typing import Any

from scrapling.fetchers import AsyncStealthySession, Fetcher

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.sources.komiku_asia_api import (
    DEFAULT_COMICS_PAGE_SIZE,
    KOMIKU_ASIA_API_BASE_URL,
    KOMIKU_ASIA_BASE_URL,
    build_komiku_asia_chapter_detail_url,
    build_komiku_asia_chapter_url,
    build_komiku_asia_comic_chapters_url,
    build_komiku_asia_comic_detail_url,
    build_komiku_asia_comics_url,
    build_komiku_asia_filters_url,
    build_komiku_asia_latest_updates_url,
    build_komiku_asia_search_url,
    extract_komiku_asia_chapter_identity,
    extract_komiku_asia_slug,
)
from scraper.utils import clean_text

logger = logging.getLogger("scraper.komiku_asia")


class KomikuAsiaScraper(ScraperCommonMixin, BaseComicScraper):
    """API-first scraper with direct HTTP transport and protected fallback."""

    SOURCE_NAME = "komiku_asia"
    BASE_URL = KOMIKU_ASIA_BASE_URL
    API_BASE_URL = KOMIKU_ASIA_API_BASE_URL
    API_PAGE_SIZE = DEFAULT_COMICS_PAGE_SIZE

    _shared_session: AsyncStealthySession | None = None
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
        return cls._env_bool("KOMIKU_ASIA_HEADLESS", False)

    @classmethod
    def _browser_extra_flags(cls) -> list[str]:
        """Gunakan viewport realistis di CI; lokal tetap disembunyikan seperti konfigurasi lama."""
        if os.getenv("GITHUB_ACTIONS", "").lower() == "true":
            return ["--window-size=1366,768"]
        return ["--window-position=-32000,-32000", "--window-size=200,200"]

    @classmethod
    async def get_session(cls) -> AsyncStealthySession:
        if cls._shared_session is None:
            logger.info("Membuka AsyncStealthySession (Persistent) baru...")
            proxy = os.getenv("KOMIKU_ASIA_PROXY")
            if proxy:
                proxy = proxy.strip()
                # Sembunyikan credential password pada logging
                masked_proxy = re.sub(r":[^:/@]+@", ":***@", proxy) if "@" in proxy else proxy
                logger.info("Menggunakan proxy untuk stealth session Komiku Asia: %s", masked_proxy)
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
        """Tutup sesi persisten untuk mengosongkan resource browser."""
        if cls._shared_session is not None:
            logger.info("Menutup AsyncStealthySession...")
            session = cls._shared_session
            cls._shared_session = None
            try:
                await session.__aexit__(None, None, None)
            except Exception as exc:
                logger.warning("Gagal menutup AsyncStealthySession lama: %s", exc)

    @classmethod
    async def reset_shared_session(cls, reason: str) -> None:
        """Paksa reset browser/session agar request berikutnya membuka identitas baru."""
        logger.warning("Reset AsyncStealthySession Komiku Asia: %s", reason)
        await cls.close_shared_session()
        logger.warning(
            "Retry berikutnya akan membuka browser/session baru dengan identitas lebih fresh."
        )

    @classmethod
    def _should_reset_session_on_error(cls, exc: Exception) -> bool:
        """Tentukan apakah error layak memicu browser/session reset."""
        return cls._is_timeout_exception(exc)

    @classmethod
    def _is_timeout_exception(cls, exc: BaseException) -> bool:
        """Kenali timeout tanpa menganggap semua exception sebagai anti-bot block.

        ``Fetcher`` dapat membungkus timeout dari backend transport yang berbeda
        (stdlib, httpx, requests/curl-cffi, atau Scrapling). Class name/module
        dipakai sebagai fallback agar kita tetap spesifik tanpa menangkap error
        parsing, konfigurasi, DNS, dan bug pemanggilan sebagai Cloudflare.
        """
        current: BaseException | None = exc
        visited: set[int] = set()
        timeout_names = {
            "timeout",
            "timeouterror",
            "timeoutexception",
            "connecttimeout",
            "readtimeout",
            "writetimeout",
            "pooltimeout",
        }

        while current is not None and id(current) not in visited:
            visited.add(id(current))
            if isinstance(current, (TimeoutError, asyncio.TimeoutError)):
                return True

            exception_name = type(current).__name__.lower()
            exception_module = type(current).__module__.lower()
            if (
                exception_name in timeout_names
                and any(
                    marker in exception_module
                    for marker in ("httpx", "requests", "curl", "scrapling", "aiohttp")
                )
            ):
                return True

            current = current.__cause__ or current.__context__

        return False

    @classmethod
    def _is_fallback_status(cls, status: Any) -> bool:
        try:
            status_code = int(status)
        except (TypeError, ValueError):
            return False
        return status_code in cls._SESSION_RESET_STATUSES or 500 <= status_code <= 599

    @classmethod
    async def _raise_for_bad_response(cls, url: str, page) -> None:
        """Naikkan error dan reset session bila status respons mengindikasikan block/proxy issue."""
        status = getattr(page, "status", 0)
        if status == 200:
            return

        if cls._is_fallback_status(status):
            await cls.reset_shared_session(
                f"status {status} saat fetch {url}"
            )

        raise RuntimeError(
            f"Gagal fetch halaman target: {url} "
            f"(status={getattr(page, 'status', 'unknown')})"
        )

    async def close(self) -> None:
        """Cleanup hook untuk pipeline utama/sync full library."""
        await self.close_shared_session()

    @classmethod
    def _response_body_text(cls, page) -> str:
        body = getattr(page, "body", b"")
        if isinstance(body, bytes):
            return body.decode("utf-8", errors="ignore")
        return str(body or "")

    @classmethod
    def _needs_browser_fallback(cls, page) -> bool:
        status = getattr(page, "status", 0)
        if cls._is_fallback_status(status):
            return True

        headers = {
            str(key).lower(): str(value).lower()
            for key, value in (getattr(page, "headers", {}) or {}).items()
        }
        if headers.get("cf-mitigated") == "challenge":
            return True

        body = cls._response_body_text(page).lower()
        if any(marker in body for marker in cls._CLOUDFLARE_CHALLENGE_MARKERS):
            return True
        return "cloudflare" in body and any(
            marker in body
            for marker in ("challenge", "captcha", "security verification")
        )

    @staticmethod
    async def _decode_api_json(
        api_url: str,
        page,
    ) -> dict[str, Any] | list[Any]:
        try:
            payload = page.json()
        except (TypeError, ValueError) as exc:
            raise RuntimeError(
                f"Respons API Komiku Asia bukan JSON: {api_url}"
            ) from exc

        if not isinstance(payload, (dict, list)):
            raise RuntimeError(f"Format respons API Komiku Asia tidak didukung: {api_url}")
        return payload

    async def _fetch_api_json_via_browser(
        self,
        api_url: str,
        *,
        timeout_ms: int,
    ) -> dict[str, Any] | list[Any]:
        logger.info("Stealth API fallback (Cloudflare): %s", api_url)
        try:
            session = await self.get_session()
            page = await asyncio.wait_for(
                session.fetch(
                    api_url,
                    timeout=timeout_ms,
                    wait=0,
                ),
                timeout=120.0,
            )
        except asyncio.TimeoutError as exc:
            await self.reset_shared_session(
                f"timeout API Komiku Asia: {api_url}"
            )
            raise RuntimeError("Gagal fetch API Komiku Asia karena timeout") from exc

        await self._raise_for_bad_response(api_url, page)
        return await self._decode_api_json(api_url, page)

    async def _fetch_api_json(
        self,
        api_url: str,
        *,
        timeout_ms: int = 120_000,
    ) -> dict[str, Any] | list[Any]:
        """Fetch API directly, falling back to a browser only on protection errors."""
        logger.info("Direct API fetch: %s", api_url)
        try:
            page = await asyncio.to_thread(
                Fetcher.get,
                api_url,
                stealthy_headers=True,
                timeout=timeout_ms,
            )
        except Exception as exc:
            if not self._is_timeout_exception(exc):
                logger.error(
                    "Direct API fetch Komiku Asia gagal karena error non-timeout; "
                    "browser fallback tidak dijalankan: %s",
                    exc,
                )
                raise RuntimeError(
                    f"Direct API fetch Komiku Asia gagal: {api_url}"
                ) from exc
            logger.warning(
                "Direct API fetch Komiku Asia timeout; memakai browser fallback: %s",
                exc,
            )
            return await self._fetch_api_json_via_browser(
                api_url,
                timeout_ms=timeout_ms,
            )

        if self._needs_browser_fallback(page):
            logger.warning(
                "Direct API Komiku Asia mendapat challenge/status %s; "
                "memakai browser fallback.",
                getattr(page, "status", "unknown"),
            )
            return await self._fetch_api_json_via_browser(
                api_url,
                timeout_ms=timeout_ms,
            )

        await self._raise_for_bad_response(api_url, page)
        return await self._decode_api_json(api_url, page)

    @staticmethod
    def _chapter_route_number(value: Any) -> str:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return str(value)
        return str(int(number)) if number.is_integer() else str(number)

    @staticmethod
    def _datetime_from_timestamp(value: Any) -> datetime | None:
        try:
            timestamp = float(value)
        except (TypeError, ValueError):
            return None
        if timestamp > 10_000_000_000:
            timestamp /= 1000
        try:
            return datetime.fromtimestamp(timestamp, tz=timezone.utc).replace(tzinfo=None)
        except (OverflowError, OSError, ValueError):
            return None

    def _parse_chapter_items(
        self,
        *,
        slug: str,
        chapters_data: list[dict[str, Any]] | None,
    ) -> list[dict[str, Any]]:
        chapters: list[dict[str, Any]] = []
        for chapter in chapters_data or []:
            if not isinstance(chapter, dict):
                continue

            raw_number = chapter.get("n", chapter.get("number"))
            chapter_title = clean_text(chapter.get("title"))
            if raw_number is None and not chapter_title:
                continue

            if raw_number is None:
                chapter_number = self._parse_chapter_number(chapter_title)
            else:
                try:
                    chapter_number = float(raw_number)
                except (TypeError, ValueError):
                    chapter_number = self._parse_chapter_number(str(raw_number))

            if not chapter_title:
                chapter_title = f"Chapter {self._chapter_route_number(chapter_number)}"

            chapter_url = build_komiku_asia_chapter_url(
                slug=slug,
                chapter_number=chapter_number,
                chapter_id=chapter.get("id"),
            )
            if not chapter_url:
                continue

            chapters.append(
                self._build_chapter_payload(
                    chapter_number=chapter_number,
                    title=chapter_title,
                    source_url=chapter_url,
                    release_date=self._datetime_from_timestamp(
                        chapter.get("releasedAt")
                    ),
                )
            )
        return chapters

    def _parse_api_comic(
        self,
        item: dict[str, Any],
        *,
        chapters_data: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any] | None:
        title = clean_text(item.get("title"))
        slug = clean_text(item.get("slug"))
        if not title or not slug:
            return None

        chapters = self._parse_chapter_items(
            slug=slug,
            chapters_data=chapters_data,
        )
        latest_number = item.get("latestChapter")
        latest_chapter = (
            f"Chapter {latest_number}" if latest_number is not None else None
        )
        latest_chapter_url = chapters[0]["source_url"] if chapters else None
        return self._build_comic_payload(
            title=title,
            source_url=f"{self.BASE_URL}/manga/{slug}",
            alternative_titles=clean_text(item.get("alt")) or None,
            cover_image_url=item.get("coverUrl"),
            type=self._parse_type_from_text(item.get("type")),
            status=self._normalize_status(item.get("status")),
            author=item.get("author"),
            artist=item.get("artist"),
            synopsis=item.get("synopsis"),
            genres=item.get("genres") or [],
            rating=self._parse_rating(str(item.get("rating")))
            if item.get("rating") is not None
            else None,
            latest_chapter=latest_chapter,
            latest_chapter_number=self._parse_chapter_number(latest_chapter),
            latest_chapter_url=latest_chapter_url,
            chapters=chapters,
        )

    def _parse_api_catalog_response(
        self,
        payload: dict[str, Any] | list[Any],
        *,
        latest_updates: bool = False,
    ) -> list[dict[str, Any]]:
        raw_items = payload if isinstance(payload, list) else payload.get("items") or []
        comics: list[dict[str, Any]] = []
        for entry in raw_items:
            if not isinstance(entry, dict):
                continue
            item = entry.get("comic") if latest_updates else entry
            if not isinstance(item, dict):
                continue
            parsed = self._parse_api_comic(
                item,
                chapters_data=entry.get("chapters")
                if latest_updates and isinstance(entry.get("chapters"), list)
                else None,
            )
            if parsed:
                comics.append(parsed)
        return comics

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        payload = await self._fetch_api_json(
            build_komiku_asia_latest_updates_url(
                page=page,
                per_page=self.API_PAGE_SIZE,
            )
        )
        return self._parse_api_catalog_response(payload, latest_updates=True)

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        payload = await self._fetch_api_json(
            build_komiku_asia_comics_url(
                page=page,
                per_page=self.API_PAGE_SIZE,
                sort="popular",
            )
        )
        return self._parse_api_catalog_response(payload)

    async def search_comics(
        self,
        query: str,
        page: int = 1,
    ) -> list[dict[str, Any]]:
        """Cari komik melalui kontrak API/frontend Browse Komiku yang baru."""
        normalized_query = clean_text(query)
        if not normalized_query:
            return []

        payload = await self._fetch_api_json(
            build_komiku_asia_search_url(
                normalized_query,
                limit=max(self.API_PAGE_SIZE * page, self.API_PAGE_SIZE),
            )
        )
        results = self._parse_api_catalog_response(payload)
        start = max(page - 1, 0) * self.API_PAGE_SIZE
        return results[start : start + self.API_PAGE_SIZE]

    async def get_catalog_filters(self) -> dict[str, list[Any]]:
        """Return filter values exposed by the official catalog API."""
        payload = await self._fetch_api_json(build_komiku_asia_filters_url())
        if not isinstance(payload, dict):
            raise RuntimeError("Payload filter API Komiku Asia tidak valid")
        return {
            key: value
            for key, value in payload.items()
            if isinstance(value, list)
        }

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        slug = extract_komiku_asia_slug(url)

        detail_payload = await self._fetch_api_json(
            build_komiku_asia_comic_detail_url(slug)
        )
        comic_id = detail_payload.get("id") if isinstance(detail_payload, dict) else None
        if comic_id is None:
            raise RuntimeError("Detail API Komiku Asia tidak mengembalikan comic id")

        chapter_payload = await self._fetch_api_json(
            build_komiku_asia_comic_chapters_url(comic_id)
        )
        chapters_data = chapter_payload if isinstance(chapter_payload, list) else []
        parsed = self._parse_api_comic(
            detail_payload,
            chapters_data=chapters_data,
        )
        if parsed:
            return parsed
        raise RuntimeError(f"Payload detail API Komiku Asia tidak valid: {url}")

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        """
        Refresh metadata Komiku Asia melalui endpoint detail API tanpa sync
        chapter penuh di caller.
        """
        detail = await self.get_comic_detail(url)
        return self._build_metadata_patch(detail, fields=fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        slug, chapter_id = extract_komiku_asia_chapter_identity(chapter_url)
        detail_payload = await self._fetch_api_json(
            build_komiku_asia_comic_detail_url(slug)
        )
        comic_id = detail_payload.get("id") if isinstance(detail_payload, dict) else None
        if comic_id is None:
            raise RuntimeError(
                f"Detail API Komiku Asia tidak mengembalikan comic id: {slug}"
            )

        payload = await self._fetch_api_json(
            build_komiku_asia_chapter_detail_url(comic_id, chapter_id)
        )
        if not isinstance(payload, dict):
            raise RuntimeError("Payload halaman chapter API Komiku Asia tidak valid")

        images: list[dict[str, Any]] = []
        for position, page in enumerate(payload.get("pages") or [], start=1):
            if not isinstance(page, dict):
                continue
            image_url = clean_text(page.get("url"))
            if not image_url:
                continue
            try:
                page_number = int(page.get("index")) + 1
            except (TypeError, ValueError):
                page_number = position
            images.append({"page": page_number, "url": image_url})
        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil katalog penuh source dalam urutan judul A-Z ascending."""
        payload = await self._fetch_api_json(
            build_komiku_asia_comics_url(
                page=page,
                per_page=self.API_PAGE_SIZE,
                sort="az",
                order="asc",
            )
        )
        return self._parse_api_catalog_response(payload)

    async def get_source_comic_count(self) -> int | None:
        """
        Ambil total series dari response katalog API resmi.
        """
        payload = await self._fetch_api_json(
            build_komiku_asia_comics_url(
                page=1,
                per_page=self.API_PAGE_SIZE,
            )
        )
        if isinstance(payload, dict) and isinstance(payload.get("total"), int):
            return int(payload["total"])
        return None
