"""
Tonztoon Komik — Shinigami Scraper

Scraper untuk https://s1.shinigami.mx/ dengan flow DB-backed seperti source lain.

Catatan implementasi:
- Situs memakai SPA Vite/React client-side routing.
- Semua operasi utama memakai endpoint resmi `https://api.shinigami.io/v1` melalui
  Scrapling `Fetcher` HTTP (TLS impersonation Chrome, tanpa parsing DOM).
- Browser `AsyncStealthySession` dengan solver Cloudflare hanya dibuka sebagai
  fallback ketika respons mendapat status proteksi/server (`403`/`429`/`5xx`),
  transport timeout, atau body Cloudflare challenge (pola sama seperti `komiku_asia`).
"""

import asyncio
import logging
import os
import re
from datetime import datetime
from typing import Any
from urllib.parse import urljoin

from scrapling.fetchers import AsyncStealthySession, Fetcher

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


class ShinigamiScraper(ScraperCommonMixin, BaseComicScraper):
    """API-first scraper untuk Shinigami dengan direct Scrapling HTTP dan stealth fallback."""

    SOURCE_NAME = "shinigami"
    BASE_URL = SHINIGAMI_BASE_URL
    API_BASE_URL = SHINIGAMI_API_BASE_URL
    API_PAGE_SIZE = DEFAULT_CHAPTER_LIST_PAGE_SIZE

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
        return cls._env_bool("SHINIGAMI_HEADLESS", False)

    @classmethod
    def _browser_extra_flags(cls) -> list[str]:
        """Gunakan viewport realistis di CI; lokal tetap disembunyikan."""
        if os.getenv("GITHUB_ACTIONS", "").lower() == "true":
            return ["--window-size=1366,768"]
        return ["--window-position=-32000,-32000", "--window-size=200,200"]

    @classmethod
    async def get_session(cls) -> AsyncStealthySession:
        if cls._shared_session is None:
            logger.info("Membuka AsyncStealthySession (Persistent) Shinigami baru...")
            proxy = os.getenv("SHINIGAMI_PROXY")
            if proxy:
                proxy = proxy.strip()
                masked_proxy = re.sub(r":[^:/@]+@", ":***@", proxy) if "@" in proxy else proxy
                logger.info("Menggunakan proxy untuk stealth session Shinigami: %s", masked_proxy)
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
            logger.info("Menutup AsyncStealthySession Shinigami...")
            session = cls._shared_session
            cls._shared_session = None
            try:
                await session.__aexit__(None, None, None)
            except Exception as exc:
                logger.warning("Gagal menutup AsyncStealthySession Shinigami lama: %s", exc)

    @classmethod
    async def reset_shared_session(cls, reason: str) -> None:
        """Paksa reset browser/session agar request berikutnya membuka identitas baru."""
        logger.warning("Reset AsyncStealthySession Shinigami: %s", reason)
        await cls.close_shared_session()
        logger.warning(
            "Retry berikutnya akan membuka browser/session baru dengan identitas lebih fresh."
        )

    @classmethod
    def _is_timeout_exception(cls, exc: BaseException) -> bool:
        """Kenali timeout tanpa menganggap semua exception sebagai anti-bot block."""
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
            f"Gagal fetch API Shinigami: {url} "
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
    def _decode_api_json(url: str, page) -> dict[str, Any]:
        try:
            payload = page.json()
        except (TypeError, ValueError) as exc:
            raise RuntimeError(f"Respons API Shinigami bukan JSON: {url}") from exc

        if not isinstance(payload, dict) or payload.get("retcode") != 0:
            message = payload.get("message") if isinstance(payload, dict) else None
            raise RuntimeError(
                f"API Shinigami gagal untuk {url}: "
                f"{message or 'unknown error'}"
            )
        return payload

    def _build_api_headers(self, referer_url: str | None = None) -> dict[str, str]:
        return build_shinigami_api_headers(referer_url)

    async def _fetch_api_json_via_browser(
        self,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        timeout_ms: int = 120_000,
    ) -> dict[str, Any]:
        logger.info("Stealth API fallback (Cloudflare) Shinigami: %s", url)
        try:
            session = await self.get_session()
            page = await asyncio.wait_for(
                session.fetch(
                    url,
                    extra_headers=headers,
                    timeout=timeout_ms,
                    wait=0,
                ),
                timeout=120.0,
            )
        except asyncio.TimeoutError as exc:
            await self.reset_shared_session(f"timeout API Shinigami: {url}")
            raise RuntimeError(f"Gagal fetch API Shinigami karena timeout: {url}") from exc

        await self._raise_for_bad_response(url, page)
        return self._decode_api_json(url, page)

    async def _fetch_api_json(
        self,
        url: str,
        *,
        referer_url: str | None = None,
        timeout_seconds: int = 30,
        timeout_ms: int = 120_000,
    ) -> dict[str, Any]:
        """Fetch API langsung via Scrapling Fetcher, fallback ke browser hanya saat proteksi/timeout."""
        headers = self._build_api_headers(referer_url)
        logger.debug("Direct API fetch Shinigami: %s", url)
        try:
            page = await asyncio.to_thread(
                Fetcher.get,
                url,
                headers=headers,
                impersonate="chrome",
                stealthy_headers=True,
                timeout=timeout_seconds,
            )
        except Exception as exc:
            if not self._is_timeout_exception(exc):
                logger.error(
                    "Direct API fetch Shinigami gagal karena error non-timeout; "
                    "browser fallback tidak dijalankan: %s",
                    exc,
                )
                raise RuntimeError(
                    f"Direct API fetch Shinigami gagal: {url}"
                ) from exc
            logger.warning(
                "Direct API fetch Shinigami timeout; memakai browser fallback: %s",
                exc,
            )
            return await self._fetch_api_json_via_browser(
                url,
                headers=headers,
                timeout_ms=timeout_ms,
            )

        if self._needs_browser_fallback(page):
            logger.warning(
                "Direct API Shinigami mendapat challenge/status %s; memakai browser fallback.",
                getattr(page, "status", "unknown"),
            )
            return await self._fetch_api_json_via_browser(
                url,
                headers=headers,
                timeout_ms=timeout_ms,
            )

        await self._raise_for_bad_response(url, page)
        return self._decode_api_json(url, page)

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
