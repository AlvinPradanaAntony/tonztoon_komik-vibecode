"""
Tonztoon Komik — Kiryuu Scraper

Scraper untuk https://v5.kiryuu.to/.

Hasil investigasi source:
- Katalog, search, dan detail metadata memakai WordPress REST
  `/wp-json/wp/v2/manga`.
- Feed latest/popular memakai endpoint resmi frontend advanced-search
  `POST admin-ajax.php?action=advanced_search` karena fragment tersebut memuat
  latest chapter per item dan ordering frontend.
- Daftar chapter lengkap diambil via `admin-ajax.php?action=chapter_list`.
"""

import json
import logging
import re
import time
from html import unescape
from typing import Any
from urllib.parse import urljoin, urlparse

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.sources.kiryuu_api import (
    KIRYUU_ADVANCED_SEARCH_URL,
    KIRYUU_BASE_URL,
    build_kiryuu_advanced_search_form,
    build_kiryuu_advanced_search_url,
    build_kiryuu_chapter_list_url,
    build_kiryuu_headers,
    build_kiryuu_manga_detail_url,
    build_kiryuu_manga_list_url,
    build_kiryuu_nonce_url,
)
from scraper.utils import clean_text

logger = logging.getLogger("scraper.kiryuu")


class KiryuuScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Kiryuu v5 berbasis REST + AJAX resmi."""

    SOURCE_NAME = "kiryuu"
    BASE_URL = KIRYUU_BASE_URL

    REST_PAGE_SIZE = 24
    CATALOG_ORDER_BY = "title"
    LATEST_ORDER_BY = "updated"
    POPULAR_ORDER_BY = "popular"

    _RETRY_STATUSES = {500, 502, 503, 504}
    _HTML_FALLBACK_FIELDS = {
        "alternative_titles",
        "cover_image_url",
        "genres",
        "rating",
        "synopsis",
        "total_view",
        "type",
    }

    def _fetch_get(self, url: str, *, referer_url: str | None = None, retries: int = 2):
        headers = build_kiryuu_headers(referer_url)
        last_page = None
        for attempt in range(retries + 1):
            logger.info("Fetch Kiryuu GET: %s", url)
            page = self.fetcher.get(url, headers=headers, stealthy_headers=True, timeout=45)
            last_page = page
            if getattr(page, "status", 0) not in self._RETRY_STATUSES:
                return page
            if attempt < retries:
                time.sleep(1.0 + attempt)
        return last_page

    def _fetch_rest_json(self, url: str, *, referer_url: str | None = None) -> tuple[Any, dict[str, str]]:
        response = self._fetch_get(url, referer_url=referer_url or self.BASE_URL)
        if getattr(response, "status", 0) != 200:
            raise RuntimeError(
                f"Gagal mengambil REST Kiryuu: {url} "
                f"(status={getattr(response, 'status', 'unknown')})"
            )

        try:
            payload = json.loads(response.body.decode("utf-8", errors="ignore"))
        except (json.JSONDecodeError, AttributeError) as exc:
            raise RuntimeError(f"Payload REST Kiryuu bukan JSON valid: {url}") from exc

        headers = dict(getattr(response, "headers", {}) or {})
        return payload, headers

    def _fetch_post(
        self,
        url: str,
        *,
        data: dict[str, Any],
        referer_url: str | None = None,
        retries: int = 2,
    ):
        headers = build_kiryuu_headers(referer_url)
        last_page = None
        for attempt in range(retries + 1):
            logger.info("Fetch Kiryuu POST: %s", url)
            page = self.fetcher.post(
                url,
                data=data,
                headers=headers,
                stealthy_headers=True,
                timeout=45,
            )
            last_page = page
            if getattr(page, "status", 0) not in self._RETRY_STATUSES:
                return page
            if attempt < retries:
                time.sleep(1.0 + attempt)
        return last_page

    def _resolve_url(self, href: str | None) -> str:
        return urljoin(self.BASE_URL, clean_text(href))

    def _extract_nonce(self) -> str:
        page = self._fetch_get(build_kiryuu_nonce_url(), referer_url=KIRYUU_ADVANCED_SEARCH_URL)
        if getattr(page, "status", 0) != 200:
            raise RuntimeError(f"Gagal mengambil nonce Kiryuu (status={getattr(page, 'status', 'unknown')})")

        nonce_el = page.css('input[name="search_nonce"]')
        if not nonce_el:
            raise RuntimeError("Tidak menemukan search_nonce Kiryuu.")
        return clean_text(nonce_el[0].attrib.get("value"))

    def _fetch_ajax_feed_page(
        self,
        *,
        page: int = 1,
        query: str | None = None,
        order: str = "asc",
        orderby: str = "title",
    ):
        nonce = self._extract_nonce()
        form = build_kiryuu_advanced_search_form(
            nonce=nonce,
            page=page,
            query=query,
            order=order,
            orderby=orderby,
        )
        response = self._fetch_post(
            build_kiryuu_advanced_search_url(),
            data=form,
            referer_url=KIRYUU_ADVANCED_SEARCH_URL,
        )
        if getattr(response, "status", 0) != 200:
            raise RuntimeError(
                f"Gagal mengambil katalog Kiryuu page {page} "
                f"(status={getattr(response, 'status', 'unknown')})"
            )
        return response

    def _extract_series_slug(self, url: str) -> str:
        match = re.search(r"/manga/([^/?#]+)/?$", url)
        if not match:
            raise ValueError(f"Tidak dapat mengekstrak slug Kiryuu dari URL: {url}")
        return match.group(1)

    def _clean_html_text(self, value: str | None) -> str:
        cleaned = re.sub(r"<[^>]+>", " ", value or "")
        return clean_text(unescape(cleaned))

    def _none_if_placeholder(self, value: str | None) -> str | None:
        cleaned = clean_text(value)
        if not cleaned or cleaned in {"-", "–"}:
            return None
        return cleaned

    def _extract_taxonomy_values(self, item: dict[str, Any], taxonomy: str) -> list[str]:
        values: list[str] = []
        metadata = item.get("metadata") or {}
        for term in metadata.get("tax") or []:
            if term.get("taxonomy") != taxonomy:
                continue
            name = clean_text(term.get("name"))
            if name and name not in values:
                values.append(name)

        for term_group in (item.get("_embedded") or {}).get("wp:term") or []:
            for term in term_group or []:
                if term.get("taxonomy") != taxonomy:
                    continue
                name = clean_text(term.get("name"))
                if name and name not in values:
                    values.append(name)
        return values

    def _first_taxonomy_value(self, item: dict[str, Any], taxonomy: str) -> str | None:
        values = self._extract_taxonomy_values(item, taxonomy)
        return values[0] if values else None

    def _extract_rest_cover_url(self, item: dict[str, Any]) -> str | None:
        metadata = item.get("metadata") or {}
        meta = metadata.get("meta") or {}
        cover_url = self._normalize_image_url(meta.get("thumbnail"))
        if cover_url:
            return cover_url

        media_items = (item.get("_embedded") or {}).get("wp:featuredmedia") or []
        for media in media_items:
            cover_url = self._normalize_image_url(media.get("source_url"))
            if cover_url:
                return cover_url
        return None

    def _parse_rest_manga_item(
        self,
        item: dict[str, Any],
        *,
        include_detail_fields: bool,
    ) -> dict[str, Any] | None:
        title = self._clean_html_text((item.get("title") or {}).get("rendered"))
        source_url = self._resolve_url(item.get("link"))
        if not title or not source_url:
            return None

        metadata = item.get("metadata") or {}
        meta = metadata.get("meta") or {}
        status_value = self._first_taxonomy_value(item, "status")
        type_value = self._first_taxonomy_value(item, "type")

        payload: dict[str, Any] = {
            "cover_image_url": self._extract_rest_cover_url(item),
            "alternative_titles": clean_text(meta.get("alternative_title")) or None,
            "status": self._normalize_status(status_value),
            "type": self._parse_type_from_text(type_value),
            "rating": self._parse_rating(str(meta.get("score"))) if meta.get("score") is not None else None,
            "genres": self._extract_taxonomy_values(item, "genre"),
        }

        if include_detail_fields:
            payload["synopsis"] = self._none_if_placeholder(
                self._clean_html_text((item.get("content") or {}).get("rendered"))
            )
            author_values = self._extract_taxonomy_values(item, "series-author")
            artist_values = self._extract_taxonomy_values(item, "artist")
            payload["author"] = ", ".join(author_values) if author_values else None
            payload["artist"] = ", ".join(artist_values) if artist_values else None

        return self._build_comic_payload(
            title=title,
            source_url=source_url,
            **payload,
        )

    def _fetch_rest_manga_list(
        self,
        *,
        page: int = 1,
        order: str = "asc",
        orderby: str = "title",
    ) -> tuple[list[dict[str, Any]], dict[str, str]]:
        payload, headers = self._fetch_rest_json(
            build_kiryuu_manga_list_url(
                page=page,
                per_page=self.REST_PAGE_SIZE,
                order=order,
                orderby=orderby,
            ),
            referer_url=KIRYUU_ADVANCED_SEARCH_URL,
        )
        if not isinstance(payload, list):
            raise RuntimeError("Payload REST katalog Kiryuu tidak berbentuk list.")

        comics = []
        for item in payload:
            parsed = self._parse_rest_manga_item(item, include_detail_fields=False)
            if parsed is not None:
                comics.append(parsed)
        return comics, headers

    async def search_comics(self, query: str, page: int = 1) -> list[dict[str, Any]]:
        """
        Pencarian langsung ke source Kiryuu.

        Pipeline/API aplikasi saat ini melakukan search dari database lokal,
        tetapi method ini disediakan agar scraper tetap punya capability search
        source-side seperti helper query pada source API lainnya.
        """
        response = self._fetch_ajax_feed_page(
            page=page,
            query=query,
            order="asc",
            orderby=self.CATALOG_ORDER_BY,
        )
        return self._parse_listing_fragment(response)

    def _fetch_rest_manga_detail(self, url: str) -> dict[str, Any]:
        slug = self._extract_series_slug(url)
        payload, _headers = self._fetch_rest_json(
            build_kiryuu_manga_detail_url(slug),
            referer_url=url,
        )
        if not isinstance(payload, list) or not payload:
            raise RuntimeError(f"Tidak menemukan payload REST detail Kiryuu: {url}")

        parsed = self._parse_rest_manga_item(payload[0], include_detail_fields=True)
        if parsed is None:
            raise RuntimeError(f"Payload REST detail Kiryuu tidak valid: {url}")
        parsed["_kiryuu_manga_id"] = str(payload[0].get("id") or "")
        return parsed

    def _normalize_image_url(self, url: str | None) -> str | None:
        cleaned = clean_text(url)
        if not cleaned:
            return None
        if cleaned.startswith("http://v5.kiryuu.to/"):
            return cleaned.replace("http://", "https://", 1)
        return self._resolve_url(cleaned)

    def _parse_listing_fragment(self, response) -> list[dict[str, Any]]:
        titles_by_url: dict[str, str] = {}
        covers_by_url: dict[str, str] = {}
        latest_by_url: dict[str, tuple[str, float | None, str | None]] = {}

        for anchor in response.css('a[href*="/manga/"]:not([href*="/chapter-"])'):
            source_url = self._resolve_url(anchor.attrib.get("href"))
            if not source_url or "/manga/" not in source_url:
                continue

            title_text = clean_text(anchor.get_all_text())
            if title_text:
                titles_by_url.setdefault(source_url, title_text)

            img = anchor.css("img")
            if img:
                image_url = self._normalize_image_url(img[0].attrib.get("src"))
                if image_url:
                    covers_by_url.setdefault(source_url, image_url)
                alt_title = clean_text(img[0].attrib.get("alt"))
                if alt_title:
                    titles_by_url.setdefault(source_url, alt_title)

        for anchor in response.css('a[href*="/chapter-"]'):
            chapter_url = self._resolve_url(anchor.attrib.get("href"))
            source_url = self._series_url_from_chapter_url(chapter_url)
            if not source_url or source_url in latest_by_url:
                continue

            chapter_title = self._extract_chapter_title(clean_text(anchor.get_all_text()))
            latest_by_url[source_url] = (
                chapter_title,
                self._parse_chapter_number(chapter_title),
                chapter_url,
            )

        comics: list[dict[str, Any]] = []
        for source_url, title in titles_by_url.items():
            latest_title, latest_number, latest_url = latest_by_url.get(source_url, (None, None, None))
            comics.append(
                self._build_comic_payload(
                    title=title,
                    source_url=source_url,
                    cover_image_url=covers_by_url.get(source_url),
                    latest_chapter=latest_title,
                    latest_chapter_number=latest_number,
                    latest_chapter_url=latest_url,
                )
            )

        return comics

    def _series_url_from_chapter_url(self, chapter_url: str) -> str | None:
        parsed = urlparse(chapter_url)
        path = parsed.path
        match = re.search(r"(/manga/[^/]+)/chapter-", path)
        if not match:
            return None
        return f"{self.BASE_URL}{match.group(1)}/"

    def _extract_chapter_title(self, text: str | None) -> str:
        cleaned = clean_text(text)
        if not cleaned:
            return ""
        match = re.search(r"Chapter\s+[0-9]+(?:\.[0-9]+)?", cleaned, flags=re.IGNORECASE)
        return match.group(0) if match else cleaned

    def _extract_manga_id(self, response, url: str) -> str:
        body = response.css("body")
        body_class = body[0].attrib.get("class", "") if body else ""
        match = re.search(r"postid-(\d+)", body_class)
        if match:
            return match.group(1)

        for node in response.css("[hx-get]"):
            hx_get = node.attrib.get("hx-get", "")
            match = re.search(r"manga_id=(\d+)", hx_get)
            if match:
                return match.group(1)

        raise RuntimeError(f"Tidak menemukan manga_id Kiryuu pada detail: {url}")

    def _is_missing_metadata_value(self, value: Any) -> bool:
        if value is None:
            return True
        if isinstance(value, str):
            return not value.strip() or value.strip() in {"-", "–"}
        if isinstance(value, list):
            return not value
        return False

    def _extract_detail_text(self, response) -> str:
        body = response.css("body")
        return clean_text(body[0].get_all_text()) if body else ""

    def _extract_labeled_detail_value(self, text: str, label: str) -> str | None:
        stop_labels = (
            "Type",
            "Released",
            "Serialization",
            "Total views",
            "Last Updates",
            "Synopsis",
            "Chapters",
            "Reviews",
            "Gallery",
            "Summary",
            "Share",
        )
        stop_pattern = "|".join(re.escape(item) for item in stop_labels if item.lower() != label.lower())
        match = re.search(
            rf"\b{re.escape(label)}\s+(.+?)(?=\s+(?:{stop_pattern})\b|$)",
            text,
            re.IGNORECASE,
        )
        if not match:
            return None
        value = clean_text(match.group(1))
        return value if value and value != "-" else None

    def _extract_total_view(self, response) -> int | None:
        value = self._extract_labeled_detail_value(self._extract_detail_text(response), "Total views")
        if not value:
            return None
        return self._parse_compact_number(value.replace(" ", ""))

    def _extract_html_synopsis(self, response) -> str | None:
        for node in response.css('[itemprop="description"]'):
            text = clean_text(node.get_all_text())
            if text and text not in {"-", "–"} and len(text) > 1:
                return text
        return None

    def _extract_html_cover_url(self, response) -> str | None:
        for img in response.css("article img.wp-post-image, img.wp-post-image"):
            image_url = self._normalize_image_url(img.attrib.get("src"))
            if image_url:
                return image_url
        return None

    def _extract_html_genres(self, response) -> list[str]:
        genres: list[str] = []
        for anchor in response.css('a[itemprop="genre"], a[href*="/genre/"]'):
            genre = clean_text(anchor.get_all_text())
            if genre and genre not in genres:
                genres.append(genre)
        return genres

    def _extract_html_alternative_titles(self, response, title: str | None) -> str | None:
        title_node = response.css('h1[itemprop="name"]')
        if not title_node:
            return None

        page_text = self._extract_detail_text(response)
        title_text = clean_text(title or title_node[0].get_all_text())
        if not title_text:
            return None

        match = re.search(
            rf"\b{re.escape(title_text)}\s+(.+?)\s+Chapter\s+[0-9]",
            page_text,
            re.IGNORECASE,
        )
        if not match:
            return None

        alternative_titles = clean_text(match.group(1))
        return alternative_titles if alternative_titles and alternative_titles != title_text else None

    def _extract_html_detail_metadata(self, response, *, title: str | None = None) -> dict[str, Any]:
        text = self._extract_detail_text(response)
        type_value = self._extract_labeled_detail_value(text, "Type")
        rating_match = re.search(r"\b([0-9]+(?:[.,][0-9]+)?)\s+Ratings\b", text, re.IGNORECASE)

        return {
            "alternative_titles": self._extract_html_alternative_titles(response, title),
            "cover_image_url": self._extract_html_cover_url(response),
            "genres": self._extract_html_genres(response),
            "rating": (
                self._parse_rating(rating_match.group(1).replace(",", "."))
                if rating_match
                else None
            ),
            "synopsis": self._extract_html_synopsis(response),
            "total_view": self._extract_total_view(response),
            "type": self._parse_type_from_text(type_value),
        }

    def _merge_html_detail_fallback(
        self,
        detail: dict[str, Any],
        response,
        *,
        fields: set[str] | None = None,
    ) -> None:
        fallback = self._extract_html_detail_metadata(response, title=detail.get("title"))
        for field_name, value in fallback.items():
            if fields is not None and field_name not in fields:
                continue
            if self._is_missing_metadata_value(value):
                continue
            if self._is_missing_metadata_value(detail.get(field_name)):
                detail[field_name] = value

    def _needs_html_detail_fallback(self, detail: dict[str, Any], fields: set[str] | None) -> bool:
        target_fields = self._HTML_FALLBACK_FIELDS if fields is None else fields & self._HTML_FALLBACK_FIELDS
        return any(self._is_missing_metadata_value(detail.get(field_name)) for field_name in target_fields)

    def _fetch_chapter_list(self, manga_id: str, *, referer_url: str):
        response = self._fetch_get(
            build_kiryuu_chapter_list_url(manga_id, page=1),
            referer_url=referer_url,
        )
        if getattr(response, "status", 0) != 200:
            raise RuntimeError(
                f"Gagal mengambil daftar chapter Kiryuu manga_id={manga_id} "
                f"(status={getattr(response, 'status', 'unknown')})"
            )
        return response

    def _parse_chapters(self, response) -> list[dict[str, Any]]:
        chapters: list[dict[str, Any]] = []
        seen_urls: set[str] = set()

        for anchor in response.css('a[href*="/chapter-"]'):
            chapter_url = self._resolve_url(anchor.attrib.get("href"))
            if not chapter_url or chapter_url in seen_urls:
                continue
            seen_urls.add(chapter_url)

            chapter_title = self._extract_chapter_title(clean_text(anchor.get_all_text()))
            chapters.append(
                self._build_chapter_payload(
                    chapter_number=self._parse_chapter_number(chapter_title),
                    title=chapter_title,
                    source_url=chapter_url,
                    release_date=None,
                )
            )

        chapters.sort(key=lambda item: item.get("chapter_number", 0), reverse=True)
        return chapters

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        response = self._fetch_ajax_feed_page(page=page, order="desc", orderby=self.LATEST_ORDER_BY)
        return self._parse_listing_fragment(response)

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        response = self._fetch_ajax_feed_page(page=page, order="desc", orderby=self.POPULAR_ORDER_BY)
        return self._parse_listing_fragment(response)

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        detail = self._fetch_rest_manga_detail(url)
        manga_id = clean_text(detail.pop("_kiryuu_manga_id", ""))
        response = self._fetch_get(url, referer_url=self.BASE_URL)
        if getattr(response, "status", 0) == 200:
            self._merge_html_detail_fallback(detail, response)
            if not manga_id:
                manga_id = self._extract_manga_id(response, url)
        elif not manga_id:
            raise RuntimeError(f"Gagal mengambil detail HTML Kiryuu: {url}")

        chapters_response = self._fetch_chapter_list(manga_id, referer_url=url)
        detail["chapters"] = self._parse_chapters(chapters_response)
        return detail

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        detail = self._fetch_rest_manga_detail(url)
        detail.pop("_kiryuu_manga_id", None)
        if self._needs_html_detail_fallback(detail, fields):
            response = self._fetch_get(url, referer_url=self.BASE_URL)
            if getattr(response, "status", 0) == 200:
                self._merge_html_detail_fallback(detail, response, fields=fields)
        return self._build_metadata_patch(detail, fields=fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        response = self._fetch_get(chapter_url, referer_url=self.BASE_URL)
        if getattr(response, "status", 0) != 200:
            raise RuntimeError(f"Gagal mengambil chapter Kiryuu: {chapter_url}")

        images: list[dict[str, Any]] = []
        seen: set[str] = set()
        for img in response.css("main img"):
            image_url = self._normalize_image_url(img.attrib.get("src") or img.attrib.get("data-src"))
            if not image_url or image_url in seen:
                continue
            if "/imgsc/" not in image_url and "yuucdn.com" not in image_url:
                continue
            seen.add(image_url)
            images.append({"page": len(images) + 1, "url": image_url})

        return images

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        comics, _headers = self._fetch_rest_manga_list(
            page=page,
            order="asc",
            orderby=self.CATALOG_ORDER_BY,
        )
        return comics

    async def get_source_comic_count(self) -> int | None:
        _comics, headers = self._fetch_rest_manga_list(
            page=1,
            order="asc",
            orderby=self.CATALOG_ORDER_BY,
        )
        total = headers.get("x-wp-total") or headers.get("X-WP-Total")
        if total is None:
            return None
        try:
            return max(int(total), 0)
        except (TypeError, ValueError):
            return None
