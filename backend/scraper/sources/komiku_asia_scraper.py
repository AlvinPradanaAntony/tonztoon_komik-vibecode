"""
Tonztoon Komik — Komiku Asia Scraper

Scraper untuk https://01.komiku.asia/ menggunakan Scrapling `AsyncStealthySession`
karena situs target dilindungi Cloudflare dan akan mengembalikan 403 untuk
request HTTP biasa.

DOM summary (verified April 17, 2026 via ScraplingServer):
- Latest/list page: /manga/?order=update[&page=N]
  - .listupd .bsx
    - a[href]                    -> detail URL
    - .tt                        -> title
    - img                        -> cover
    - .epxs                      -> latest chapter label
    - .numscore                  -> rating
    - span.type                  -> comic type (via class name)

- Popular page: /manga/?order=popular
  - #content .serieslist.pop li
    - .imgseries a[href]         -> detail URL
    - .leftseries h2 a           -> title
    - .imgseries img             -> cover
    - .leftseries .numscore      -> rating
    - .leftseries span a[rel=tag]-> genres

- Search page: /?s={query}
  - .listupd .bsx (sama seperti latest/list)

- Detail page: /manga/{slug}/
  - h1.entry-title               -> title
  - .seriestucontl .thumb img    -> cover
  - .entry-content-single p      -> synopsis
  - table.infotable tr           -> metadata (Alternative, Status, Type, Author, etc.)
  - .seriestugenre a             -> genres
  - #chapterlist li              -> daftar chapter

- Chapter page: /{slug}-chapter-{n}/
  - .ts-main-image               -> gambar chapter
"""

import asyncio
import logging
import re
from datetime import datetime
from typing import Any
from urllib.parse import urlencode

from scrapling.fetchers import AsyncStealthySession

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin

logger = logging.getLogger("scraper.komiku_asia")


class KomikuAsiaScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk mirror Komiku Asia yang memakai stealth mode."""

    SOURCE_NAME = "komiku_asia"
    BASE_URL = "https://01.komiku.asia"

    _INDONESIAN_MONTHS = {
        "januari": "January",
        "februari": "February",
        "maret": "March",
        "april": "April",
        "mei": "May",
        "juni": "June",
        "juli": "July",
        "agustus": "August",
        "september": "September",
        "oktober": "October",
        "november": "November",
        "desember": "December",
    }

    _shared_session: AsyncStealthySession | None = None
    _SESSION_RESET_ERROR_MARKERS = (
        "cloudflare captcha is still present",
        "captcha",
        "turnstile",
        "timeout",
        "timed out",
    )
    _SESSION_RESET_STATUSES = {403, 429, 500, 502, 503, 504}

    @classmethod
    async def get_session(cls) -> AsyncStealthySession:
        if cls._shared_session is None:
            logger.info("Membuka AsyncStealthySession (Persistent) baru...")
            cls._shared_session = AsyncStealthySession(
                headless=False,
                real_chrome=True,
                solve_cloudflare=True,
                google_search=True,
                extra_flags=["--window-position=-32000,-32000", "--window-size=200,200"],
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
        if isinstance(exc, (TimeoutError, asyncio.TimeoutError)):
            return True

        message = str(exc).lower()
        return any(marker in message for marker in cls._SESSION_RESET_ERROR_MARKERS)

    @classmethod
    async def _raise_for_bad_response(cls, url: str, page) -> None:
        """Naikkan error dan reset session bila status respons mengindikasikan block/proxy issue."""
        status = getattr(page, "status", 0)
        if status == 200:
            return

        if status in cls._SESSION_RESET_STATUSES:
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

    async def _fetch_page(
        self,
        url: str,
        *,
        wait_selector: str,
        timeout_ms: int = 45_000,
        wait_ms: int = 900,
    ):
        """
        Ambil halaman via AsyncStealthySession agar lolos Cloudflare.
        Karena menggunakan session, status cache dan validasi Turnstile
        akan tetap disimpan di pemanggilan `.fetch(...)` berikutnya.
        """
        logger.info("Stealth fetch: %s", url)
        try:
            session = await self.get_session()
            page = await session.fetch(
                url,
                wait_selector=wait_selector,
                wait_selector_state="visible",
                timeout=timeout_ms,
                wait=wait_ms,
            )
        except Exception as exc:
            if self._should_reset_session_on_error(exc):
                await self.reset_shared_session(
                    f"{type(exc).__name__}: {exc}"
                )
                logger.warning(
                    "Fetch gagal untuk %s dan error diteruskan ke caller agar backoff/retry berjalan.",
                    url,
                )
            raise

        await self._raise_for_bad_response(url, page)
        return page

    def _parse_date(self, date_str: str | None) -> datetime | None:
        cleaned = self._clean_text(date_str)
        if not cleaned:
            return None

        normalized = cleaned
        for indo, english in self._INDONESIAN_MONTHS.items():
            normalized = re.sub(
                rf"\b{indo}\b",
                english,
                normalized,
                flags=re.IGNORECASE,
            )

        for fmt in ("%B %d, %Y", "%d %B %Y", "%Y-%m-%d"):
            try:
                return datetime.strptime(normalized, fmt)
            except ValueError:
                continue

        return None

    def _extract_type_from_class(self, element) -> str | None:
        return self._parse_type_from_text(" ".join(element.attrib.get("class", "").split()))

    def _build_manga_list_url(self, *, page: int = 1, order: str | None = None) -> str:
        query: dict[str, Any] = {}
        if page > 1:
            query["page"] = page
        if order:
            query["order"] = order
        if not query:
            return f"{self.BASE_URL}/manga/"
        return f"{self.BASE_URL}/manga/?{urlencode(query)}"

    def _extract_info_table_map(self, response) -> dict[str, str]:
        """Bangun map metadata dari tabel informasi detail komik."""
        info_map: dict[str, str] = {}
        for row in response.css("table.infotable tr"):
            cells = row.css("td")
            if len(cells) < 2:
                continue

            key = self._clean_text(cells[0].text).lower().rstrip(":")
            value = self._clean_text(cells[1].get_all_text())
            if key:
                info_map[key] = value
        return info_map

    def _parse_grid_cards(self, cards: list) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for card in cards:
            try:
                link_el = card.css("a")
                if not link_el:
                    continue

                comic_url = self._resolve_url(link_el[0].attrib.get("href"))

                title = ""
                title_el = card.css(".tt")
                if title_el:
                    title = self._clean_text(title_el[0].text)
                if not title:
                    img = card.css("img")
                    if img:
                        title = self._clean_text(img[0].attrib.get("alt"))
                if not title:
                    continue

                img = card.css("img")
                cover_url = self._extract_image_url(img[0] if img else None, invalid_substrings=())

                latest_chapter = None
                latest_chapter_number = None
                latest_chapter_url = None
                chapter_el = card.css(".epxs")
                if chapter_el:
                    latest_chapter = self._clean_text(chapter_el[0].text)
                    latest_chapter_number = self._parse_chapter_number(latest_chapter)

                rating_el = card.css(".numscore")
                rating = self._parse_rating(rating_el[0].text if rating_el else None)

                comic_type = None
                type_el = card.css("span.type")
                if type_el:
                    comic_type = self._extract_type_from_class(type_el[0])

                summary = None
                summary_el = card.css(".bigor .adds")
                if summary_el:
                    summary = self._clean_text(summary_el[0].get_all_text())

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        cover_image_url=cover_url,
                        type=comic_type,
                        summary=summary,
                        rating=rating,
                        latest_chapter=latest_chapter,
                        latest_chapter_number=latest_chapter_number,
                        latest_chapter_url=latest_chapter_url,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komiku Asia grid card: %s", exc)
                continue

        return comics_data

    def _parse_popular_cards(self, cards: list) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for card in cards:
            try:
                title_el = card.css(".leftseries h2 a")
                if not title_el:
                    continue

                title = self._clean_text(title_el[0].text)
                comic_url = self._resolve_url(title_el[0].attrib.get("href"))

                img = card.css(".imgseries img")
                cover_url = self._extract_image_url(img[0] if img else None, invalid_substrings=())

                genres = [
                    self._clean_text(genre.text)
                    for genre in card.css(".leftseries span a")
                    if self._clean_text(genre.text)
                ]

                rating_el = card.css(".numscore")
                rating = self._parse_rating(rating_el[0].text if rating_el else None)

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        cover_image_url=cover_url,
                        genres=genres,
                        rating=rating,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komiku Asia popular card: %s", exc)
                continue

        return comics_data

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        url = self._build_manga_list_url(page=page, order="update")
        response = await self._fetch_page(url, wait_selector=".listupd .bsx, .pagination")
        return self._parse_grid_cards(response.css(".listupd .bsx"))

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        url = self._build_manga_list_url(page=page, order="popular")
        response = await self._fetch_page(url, wait_selector=".serieslist.pop li")
        return self._parse_popular_cards(response.css(".serieslist.pop li"))

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        response = await self._fetch_page(url, wait_selector=".seriestucon")

        title = ""
        title_el = response.css("h1.entry-title")
        if title_el:
            title = self._clean_text(title_el[0].text)

        synopsis = None
        synopsis_el = response.css(".entry-content-single[itemprop='description'] p")
        if synopsis_el:
            synopsis = self._clean_text(synopsis_el[0].text)

        cover_el = response.css(".seriestucontl .thumb img")
        cover_url = self._extract_image_url(cover_el[0] if cover_el else None, invalid_substrings=())

        info_map = self._extract_info_table_map(response)

        genres = [
            self._clean_text(genre.text)
            for genre in response.css(".seriestugenre a")
            if self._clean_text(genre.text)
        ]

        rating = None
        rating_el = response.css(".rating .num")
        if rating_el:
            rating = self._parse_rating(rating_el[0].text)

        chapters: list[dict[str, Any]] = []
        for chapter_item in response.css("#chapterlist li"):
            try:
                link_el = chapter_item.css("a")
                if not link_el:
                    continue

                chapter_url = self._resolve_url(link_el[0].attrib.get("href"))

                title_node = chapter_item.css(".chapternum")
                chapter_title = self._clean_text(title_node[0].text) if title_node else ""

                date_node = chapter_item.css(".chapterdate")
                release_date = self._parse_date(date_node[0].text if date_node else None)

                chapters.append(
                    self._build_chapter_payload(
                        chapter_number=self._parse_chapter_number(chapter_title),
                        title=chapter_title,
                        source_url=chapter_url,
                        release_date=release_date,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komiku Asia chapter row: %s", exc)
                continue

        return self._build_comic_payload(
            title=title,
            source_url=url,
            alternative_titles=info_map.get("alternative"),
            cover_image_url=cover_url,
            author=info_map.get("author"),
            artist=None,
            status=self._normalize_status(info_map.get("status")),
            type=self._parse_type_from_text(info_map.get("type")),
            synopsis=synopsis,
            rating=rating,
            genres=genres,
            chapters=chapters,
        )

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        """
        Refresh metadata Komiku Asia dari detail page tanpa sync chapter penuh.

        Karena source ini tidak menyediakan endpoint metadata ringan yang stabil,
        patch diambil dari halaman detail stealth yang sama lalu dipersempit ke
        field yang diminta.
        """
        detail = await self.get_comic_detail(url)
        return self._build_metadata_patch(detail, fields=fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        response = await self._fetch_page(chapter_url, wait_selector=".ts-main-image")

        images: list[dict[str, Any]] = []
        for img in response.css(".ts-main-image"):
            img_url = self._extract_image_url(img, invalid_substrings=())
            if not img_url:
                continue

            try:
                page_number = int(img.attrib.get("data-index", len(images))) + 1
            except ValueError:
                page_number = len(images) + 1

            images.append(
                {
                    "page": page_number,
                    "url": img_url,
                }
            )

        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        url = self._build_manga_list_url(page=page)
        response = await self._fetch_page(url, wait_selector=".listupd .bsx, .pagination")
        return self._parse_grid_cards(response.css(".listupd .bsx"))

    async def _get_list_mode_series_urls(self) -> set[str]:
        """Ambil seluruh URL komik dari halaman alfabet list-mode."""
        response = await self._fetch_page(
            f"{self.BASE_URL}/manga/list-mode/",
            wait_selector=".soralist",
        )
        return {
            href
            for anchor in response.css(".soralist a.series.tip")
            if (href := self._resolve_url(anchor.attrib.get("href")))
        }

    async def get_source_comic_count(self) -> int | None:
        """
        Hitung total komik Komiku Asia dari halaman `list-mode`.

        Halaman ini menampilkan daftar alfabet lengkap dalam satu dokumen,
        sehingga jauh lebih murah dan stabil dibanding probing pagination
        katalog image-mode yang diproteksi Cloudflare.
        """
        return len(await self._get_list_mode_series_urls())
