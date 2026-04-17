"""
Tonztoon Komik — Komiku Asia Scraper

Scraper untuk https://01.komiku.asia/ menggunakan Scrapling `StealthySession`
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
from urllib.parse import urlencode, urljoin

from scrapling.fetchers import StealthySession

from scraper.base_scraper import BaseComicScraper

logger = logging.getLogger("scraper.komiku_asia")


class KomikuAsiaScraper(BaseComicScraper):
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

    @classmethod
    async def close_shared_session(cls) -> None:
        """Kompatibilitas dengan lifecycle app; tidak ada sesi persisten yang ditahan."""
        return None

    @staticmethod
    def _fetch_page_sync(
        url: str,
        *,
        wait_selector: str,
        timeout_ms: int,
        wait_ms: int,
    ):
        """
        Jalur sinkron yang meniru pola kerja `testing/scraper_counts.py`.

        Playwright sync API dijalankan di worker thread via `asyncio.to_thread`,
        sehingga tetap aman dipanggil dari FastAPI async.
        """
        with StealthySession(
            headless=False,
            real_chrome=True,
            solve_cloudflare=True,
            google_search=True,
            extra_flags=["--window-position=-32000,-32000", "--window-size=200,200"],
        ) as session:
            page = session.fetch(
                url,
                wait_selector=wait_selector,
                wait_selector_state="visible",
                solve_cloudflare=True,
                network_idle=True,
                timeout=timeout_ms,
                wait=wait_ms,
            )
            if getattr(page, "status", 0) != 200:
                raise RuntimeError(
                    f"Gagal fetch halaman target: {url} "
                    f"(status={getattr(page, 'status', 'unknown')})"
                )
            return page

    async def _fetch_page(
        self,
        url: str,
        *,
        wait_selector: str,
        timeout_ms: int = 45_000,
        wait_ms: int = 900,
    ):
        """
        Ambil halaman via StealthySession agar lolos Cloudflare.

        Konfigurasi disamakan dengan `backend/scraper_counts.py`:
        `headless=False`, `real_chrome=True`, `solve_cloudflare=True`,
        `google_search=True`.
        """
        logger.info("Stealth fetch: %s", url)
        return await asyncio.to_thread(
            self._fetch_page_sync,
            url,
            wait_selector=wait_selector,
            timeout_ms=timeout_ms,
            wait_ms=wait_ms,
        )

    def _clean_text(self, text: str | None) -> str:
        if not text:
            return ""
        return re.sub(r"\s+", " ", text).strip()

    def _make_slug(self, title: str) -> str:
        slug = title.lower().strip()
        slug = re.sub(r"[^a-z0-9\s-]", "", slug)
        slug = re.sub(r"[\s-]+", "-", slug)
        return slug.strip("-")

    def _parse_chapter_number(self, text: str) -> float:
        if not text:
            return 0.0

        match = re.search(r"(\d+(?:[.\-]\d+)?)", text, re.IGNORECASE)
        if not match:
            return 0.0

        try:
            return float(match.group(1).replace("-", "."))
        except ValueError:
            return 0.0

    def _parse_rating(self, text: str | None) -> float | None:
        cleaned = self._clean_text(text)
        if not cleaned:
            return None
        try:
            return float(cleaned)
        except ValueError:
            return None

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
        classes = element.attrib.get("class", "").split()
        known_types = {"manga", "manhwa", "manhua", "comic"}
        for class_name in classes:
            lowered = class_name.lower()
            if lowered in known_types:
                return lowered
        return None

    def _build_manga_list_url(self, *, page: int = 1, order: str | None = None) -> str:
        query: dict[str, Any] = {}
        if page > 1:
            query["page"] = page
        if order:
            query["order"] = order
        if not query:
            return f"{self.BASE_URL}/manga/"
        return f"{self.BASE_URL}/manga/?{urlencode(query)}"

    def _parse_grid_cards(self, cards: list) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for card in cards:
            try:
                link_el = card.css("a")
                if not link_el:
                    continue

                href = link_el[0].attrib.get("href", "")
                comic_url = urljoin(self.BASE_URL, href)

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

                cover_url = None
                img = card.css("img")
                if img:
                    cover_url = img[0].attrib.get("src") or img[0].attrib.get("data-src")

                latest_chapter = None
                latest_chapter_url = None
                chapter_el = card.css(".epxs")
                if chapter_el:
                    latest_chapter = self._clean_text(chapter_el[0].text)
                    latest_chapter_url = comic_url

                rating = None
                rating_el = card.css(".numscore")
                if rating_el:
                    rating = self._parse_rating(rating_el[0].text)

                comic_type = None
                type_el = card.css("span.type")
                if type_el:
                    comic_type = self._extract_type_from_class(type_el[0])

                summary = None
                summary_el = card.css(".bigor .adds")
                if summary_el:
                    summary = self._clean_text(summary_el[0].get_all_text())

                comics_data.append(
                    {
                        "title": title,
                        "slug": self._make_slug(title),
                        "cover_image_url": cover_url,
                        "type": comic_type,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                        "summary": summary,
                        "rating": rating,
                        "latest_chapter": latest_chapter,
                        "latest_chapter_url": latest_chapter_url,
                    }
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
                href = title_el[0].attrib.get("href", "")
                comic_url = urljoin(self.BASE_URL, href)

                img = card.css(".imgseries img")
                cover_url = None
                if img:
                    cover_url = img[0].attrib.get("src") or img[0].attrib.get("data-src")

                genres = [
                    self._clean_text(genre.text)
                    for genre in card.css(".leftseries span a")
                    if self._clean_text(genre.text)
                ]

                rating = None
                rating_el = card.css(".numscore")
                if rating_el:
                    rating = self._parse_rating(rating_el[0].text)

                comics_data.append(
                    {
                        "title": title,
                        "slug": self._make_slug(title),
                        "cover_image_url": cover_url,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                        "genres": genres,
                        "rating": rating,
                    }
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

        cover_url = None
        cover_el = response.css(".seriestucontl .thumb img")
        if cover_el:
            cover_url = cover_el[0].attrib.get("src") or cover_el[0].attrib.get("data-src")

        info_map: dict[str, str] = {}
        for row in response.css("table.infotable tr"):
            cells = row.css("td")
            if len(cells) < 2:
                continue
            key = self._clean_text(cells[0].text).lower().rstrip(":")
            value = self._clean_text(cells[1].get_all_text())
            if key:
                info_map[key] = value

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

                href = link_el[0].attrib.get("href", "")
                chapter_url = urljoin(self.BASE_URL, href)

                title_node = chapter_item.css(".chapternum")
                chapter_title = self._clean_text(title_node[0].text) if title_node else ""

                date_node = chapter_item.css(".chapterdate")
                release_date = self._parse_date(date_node[0].text if date_node else None)

                chapters.append(
                    {
                        "chapter_number": self._parse_chapter_number(chapter_title),
                        "title": chapter_title,
                        "source_url": chapter_url,
                        "release_date": release_date,
                    }
                )
            except Exception as exc:
                logger.warning("Error parsing Komiku Asia chapter row: %s", exc)
                continue

        return {
            "title": title,
            "slug": self._make_slug(title),
            "alternative_titles": info_map.get("alternative"),
            "cover_image_url": cover_url,
            "author": info_map.get("author"),
            "artist": None,
            "status": info_map.get("status", "").lower() or None,
            "type": info_map.get("type", "").lower() or None,
            "synopsis": synopsis,
            "rating": rating,
            "source_url": url,
            "source_name": self.SOURCE_NAME,
            "genres": genres,
            "chapters": chapters,
        }

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        response = await self._fetch_page(chapter_url, wait_selector=".ts-main-image")

        images: list[dict[str, Any]] = []
        for img in response.css(".ts-main-image"):
            img_url = img.attrib.get("src") or img.attrib.get("data-src")
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

    async def search(self, query: str) -> list[dict[str, Any]]:
        url = f"{self.BASE_URL}/?{urlencode({'s': query})}"
        response = await self._fetch_page(url, wait_selector=".listupd .bsx, .bixbox")
        return self._parse_grid_cards(response.css(".listupd .bsx"))

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        url = self._build_manga_list_url(page=page)
        response = await self._fetch_page(url, wait_selector=".listupd .bsx, .pagination")
        return self._parse_grid_cards(response.css(".listupd .bsx"))
