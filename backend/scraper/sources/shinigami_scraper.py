"""
Tonztoon Komik — Shinigami Scraper

Scraper untuk https://e.shinigami.asia/ dengan flow DB-backed seperti source lain.

Catatan implementasi:
- Situs memakai SPA/SvelteKit client-side routing.
- Daftar manga `/search` paling stabil diambil dari endpoint API `manga/list`.
- Fallback browser tetap dipertahankan untuk berjaga-jaga jika endpoint API
  gagal/berubah.
- Chapter images diambil dari DOM render akhir dan difilter agar tidak ikut
  membawa banner iklan.
"""

import asyncio
import logging
import re
from datetime import datetime
from typing import Any

import httpx

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.sources.shinigami_api import (
    DEFAULT_CHAPTER_LIST_PAGE_SIZE,
    SHINIGAMI_API_BASE_URL,
    SHINIGAMI_BASE_URL,
    build_shinigami_api_headers,
    build_shinigami_manga_list_url,
    build_shinigami_search_url,
    clean_shinigami_series_title,
    parse_shinigami_iso_datetime,
    parse_shinigami_manga_list_payload,
)

logger = logging.getLogger("scraper.shinigami")


JS_CLICK_NEXT = """
() => {
  const buttons = [...document.querySelectorAll('button')];
  const nextBtn = buttons.find(button =>
    button.querySelector('img[src*="arrow-right"]') &&
    !button.classList.contains('opacity-25') &&
    !button.disabled
  );
  if (!nextBtn) return false;
  nextBtn.click();
  return true;
}
"""

JS_EXTRACT_VISIBLE_SERIES = """
() => {
  const anchors = [...document.querySelectorAll('a[href*="/series/"]')];
  return anchors
    .map(anchor => {
      const rect = anchor.getBoundingClientRect();
      const style = window.getComputedStyle(anchor);
      const isVisible =
        style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        parseFloat(style.opacity || '1') > 0 &&
        rect.width > 0 &&
        rect.height > 0;
      if (!isVisible) return null;

      const href = anchor.getAttribute('href');
      const title =
        anchor.querySelector('h4')?.innerText?.trim() ||
        anchor.querySelector('img')?.getAttribute('alt')?.trim() ||
        anchor.innerText?.replace(/\\s+/g, ' ').trim() ||
        '';

      const metaTexts = [...anchor.querySelectorAll('span, p, div')]
        .map(el => (el.innerText || '').replace(/\\s+/g, ' ').trim())
        .filter(Boolean);
      const latestChapter = metaTexts.find(text =>
        /^ch(?:apter)?\\.?/i.test(text) && text.length <= 20
      );
      const latestRelease = metaTexts.find(text =>
        /(mnt|menit|jam|hari|bln|bulan|thn|tahun|minggu)/i.test(text) &&
        text.length <= 24
      );

      return {
        href,
        title,
        latest_chapter: latestChapter || null,
        latest_release: latestRelease || null,
      };
    })
    .filter(Boolean);
}
"""


class ShinigamiScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Shinigami berbasis DynamicFetcher."""

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
            endpoint = (
                f"{self.API_BASE_URL}/chapter/{manga_id}/list"
                f"?page={page}&page_size={self.API_PAGE_SIZE}"
                "&sort_by=chapter_number&sort_order=desc"
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
                chapters.append(
                    self._build_chapter_payload(
                        chapter_number=float(chapter_number),
                        title=title,
                        source_url=f"{self.BASE_URL}/chapter/{chapter_id}",
                        release_date=self._parse_iso_datetime(item.get("release_date")),
                    )
                )

            page += 1

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    def _run_dynamic_fetch(
        self,
        url: str,
        *,
        wait_selector: str,
        page_action=None,
        timeout_ms: int = 90_000,
        wait_ms: int = 1_500,
    ):
        logger.info("Dynamic fetch Shinigami: %s", url)
        response = self.dynamic_fetcher.fetch(
            url,
            headless=True,
            network_idle=True,
            wait_selector=wait_selector,
            wait_selector_state="attached",
            timeout=timeout_ms,
            wait=wait_ms,
            page_action=page_action,
        )
        if getattr(response, "status", 0) not in {200, 308}:
            raise RuntimeError(
                f"Gagal fetch halaman target: {url} "
                f"(status={getattr(response, 'status', 'unknown')})"
            )
        return response

    async def _fetch_dynamic(
        self,
        url: str,
        *,
        wait_selector: str,
        page_action=None,
        timeout_ms: int = 90_000,
        wait_ms: int = 1_500,
    ):
        return await asyncio.to_thread(
            self._run_dynamic_fetch,
            url,
            wait_selector=wait_selector,
            page_action=page_action,
            timeout_ms=timeout_ms,
            wait_ms=wait_ms,
        )

    def _build_search_url(self, query: str | None = None) -> str:
        return build_shinigami_search_url(query)

    def _clean_series_title(self, raw_title: str | None) -> str:
        return clean_shinigami_series_title(raw_title)

    def _extract_search_items_from_response(self, response) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        seen_urls: set[str] = set()

        for anchor in response.css('a[href*="/series/"]'):
            href = anchor.attrib.get("href")
            source_url = self._resolve_url(href)
            if not source_url or source_url in seen_urls:
                continue

            title = None
            title_el = anchor.css("h4")
            if title_el:
                title = self._clean_series_title(title_el[0].text)
            if not title:
                img = anchor.css("img")
                title = self._clean_series_title(img[0].attrib.get("alt") if img else None)

            if not title:
                continue

            meta_texts = [
                self._clean_text(node.text)
                for node in anchor.css("span, p, div")
                if self._clean_text(node.text)
            ]
            latest_chapter = next((text for text in meta_texts if re.match(r"^ch(?:apter)?\.?", text, re.IGNORECASE)), None)
            latest_release = next(
                (text for text in meta_texts if re.search(r"(mnt|menit|jam|hari|bln|bulan|thn|tahun|UP)", text, re.IGNORECASE)),
                None,
            )

            seen_urls.add(source_url)
            items.append(
                self._build_comic_payload(
                    title=title,
                    source_url=source_url,
                    latest_chapter=latest_chapter,
                    latest_chapter_number=self._parse_chapter_number(latest_chapter) or None,
                    latest_release=latest_release,
                )
            )

        return items

    async def _fetch_search_page_via_api(
        self,
        *,
        page: int = 1,
        query: str | None = None,
    ) -> list[dict[str, Any]]:
        payload = await self._fetch_api_json(
            build_shinigami_manga_list_url(page=page, query=query),
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

    async def _fetch_search_page_via_dom(
        self,
        *,
        page: int = 1,
        query: str | None = None,
    ) -> list[dict[str, Any]]:
        captured: dict[str, Any] = {"items": [], "reached_target": False}

        def navigate_and_capture(playwright_page) -> None:
            playwright_page.wait_for_timeout(3_000)

            current_page = 1
            while current_page < page:
                previous_first_href = playwright_page.evaluate(
                    """
                    () => {
                      const first = document.querySelector('a[href*="/series/"]');
                      return first ? first.getAttribute('href') : null;
                    }
                    """
                )
                clicked = playwright_page.evaluate(JS_CLICK_NEXT)
                if not clicked:
                    captured["reached_target"] = False
                    return

                try:
                    playwright_page.wait_for_function(
                        """
                        previousHref => {
                          const first = document.querySelector('a[href*="/series/"]');
                          if (!first) return false;
                          return first.getAttribute('href') !== previousHref;
                        }
                        """,
                        previous_first_href,
                        timeout=12_000,
                    )
                except Exception:
                    playwright_page.wait_for_timeout(4_000)

                current_page += 1

            captured["reached_target"] = current_page == page
            captured["items"] = playwright_page.evaluate(JS_EXTRACT_VISIBLE_SERIES)

        response = await self._fetch_dynamic(
            self._build_search_url(query),
            wait_selector='a[href*="/series/"]',
            page_action=navigate_and_capture,
        )

        if page == 1 and not captured["items"]:
            captured["items"] = [
                {
                    "href": item.get("source_url"),
                    "title": item.get("title"),
                    "latest_chapter": item.get("latest_chapter"),
                    "latest_release": item.get("latest_release"),
                }
                for item in self._extract_search_items_from_response(response)
            ]
            captured["reached_target"] = True

        if not captured["reached_target"]:
            return []

        results: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        for item in captured["items"]:
            source_url = self._resolve_url(item.get("href"))
            title = self._clean_series_title(item.get("title"))
            if not title or not source_url or source_url in seen_urls:
                continue

            latest_chapter = self._clean_text(item.get("latest_chapter"))
            seen_urls.add(source_url)
            results.append(
                self._build_comic_payload(
                    title=title,
                    source_url=source_url,
                    latest_chapter=latest_chapter or None,
                    latest_chapter_number=self._parse_chapter_number(latest_chapter) or None,
                    latest_release=self._clean_text(item.get("latest_release")) or None,
                )
            )

        return results

    async def _fetch_search_page(
        self,
        *,
        page: int = 1,
        query: str | None = None,
    ) -> list[dict[str, Any]]:
        try:
            return await self._fetch_search_page_via_api(page=page, query=query)
        except Exception as exc:
            logger.warning(
                "API manga/list Shinigami gagal untuk page=%s query=%r, fallback ke DOM: %s",
                page,
                query,
                exc,
            )
            return await self._fetch_search_page_via_dom(page=page, query=query)

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Feed latest diambil dari `/search` yang default-nya memakai urutan terbaru.
        """
        return await self._fetch_search_page(page=page)

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Best-effort popular feed dari halaman `/explore`.

        Saat ini belum ada pagination/endpoint populer yang stabil seperti source
        lain, jadi hanya page 1 yang dipakai.
        """
        if page > 1:
            return []

        response = await self._fetch_dynamic(
            f"{self.BASE_URL}/explore",
            wait_selector='a[href*="/series/"]',
        )

        results: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        for anchor in response.css('a[href*="/series/"]'):
            source_url = self._resolve_url(anchor.attrib.get("href"))
            if not source_url or source_url in seen_urls:
                continue

            img = anchor.css("img")
            title = self._clean_series_title(img[0].attrib.get("alt") if img else None)
            if not title:
                title_el = anchor.css("h4")
                title = self._clean_series_title(title_el[0].text if title_el else None)
            if not title:
                continue

            seen_urls.add(source_url)
            results.append(
                self._build_comic_payload(
                    title=title,
                    source_url=source_url,
                )
            )

        return results

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
        response = await self._fetch_dynamic(
            chapter_url,
            wait_selector='img[src*="assets.shngm.id/chapter/"], img.w-full.object-contain',
            wait_ms=2_000,
        )

        images: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        for img in response.css("img"):
            image_url = self._extract_image_url(
                img,
                invalid_substrings=("dewakematian.com", "logo.png", "profile.png"),
            )
            if not image_url or "assets.shngm.id/chapter/" not in image_url or image_url in seen_urls:
                continue

            seen_urls.add(image_url)
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
