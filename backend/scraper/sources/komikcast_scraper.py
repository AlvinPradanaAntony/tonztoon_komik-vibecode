"""
Tonztoon Komik — Komikcast Scraper

Scraper untuk https://v1.komikcast.fit/ dengan pendekatan API-first.

Frontend source memang SPA, tetapi data utamanya berasal dari backend resmi
`https://be.komikcast.cc`, sehingga:
- katalog/latest/search memakai endpoint `/series`
- detail comic memakai endpoint `/series/{slug}?includeMeta=true`
- daftar chapter memakai endpoint `/series/{slug}/chapters`
- chapter images memakai endpoint `/series/{slug}/chapters/{chapterIndex}`
- popular memakai endpoint `/series/most-read`

DOM summary (legacy fallback notes, verified April 17, 2026):
- Library page: /comics[?page=N]
  - div.grid > a[href*="/series/"]
    - h3                         -> title
    - img                        -> cover
    - p[0]                       -> author
    - p[1]                       -> latest chapter label
    - p[2]                       -> status
    - p[3]                       -> synopsis ringkas
    - span[0]                    -> rating
    - span[1]                    -> views
    - span[2]                    -> total chapter

- Popular page: /populer
  - a[href*="/series/"]          -> multiple ranking sections, preserve DOM order
    - h3                         -> title
    - img                        -> cover
    - span matching "Ch."        -> latest chapter label
    - span rating                -> rating

- Detail page: /series/{slug}
  - h1                           -> title
  - img[src*="/cover/"]          -> cover + backdrop
  - img[src*="/assets/status-icon/"] -> status icon (alt text = status)
  - p.mt-2                       -> synopsis
  - a[href*="/comics?genres="]   -> genres
  - a[href*="/chapter/"]         -> chapter entries
    - p.font-semibold            -> chapter title
    - span[0]                    -> relative release text

- Chapter page: /series/{slug}/chapter/{n}
  - img[src*="/wp-content/img/"] / img[src*="imgkc"] -> chapter images
"""

import logging
import asyncio
import re
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from functools import partial
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen

from scrapling.fetchers import DynamicSession

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.time_utils import now_wib

logger = logging.getLogger("scraper.komikcast")


class KomikcastScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Komikcast berbasis backend API resmi source."""

    SOURCE_NAME = "komikcast"
    BASE_URL = "https://v1.komikcast.fit"
    API_BASE_URL = "https://be.komikcast.cc"

    _TYPE_MAP = {
        "MANGA": "manga",
        "MANHWA": "manhwa",
        "MANHUA": "manhua",
    }

    _shared_session: DynamicSession | None = None
    _session_executor: ThreadPoolExecutor | None = None

    def _build_api_headers(self) -> dict[str, str]:
        return {
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": f"{self.BASE_URL}/",
            "Origin": self.BASE_URL,
        }

    async def _fetch_api_json(self, api_url: str) -> dict[str, Any]:
        logger.info("API fetch Komikcast: %s", api_url)

        def do_request() -> dict[str, Any]:
            request = Request(api_url, headers=self._build_api_headers())
            with urlopen(request, timeout=45) as response:
                payload = response.read().decode("utf-8", errors="ignore")
            return json.loads(payload)

        data = await asyncio.to_thread(do_request)
        if data.get("status") != 200:
            raise RuntimeError(f"Gagal mengambil data API Komikcast: {api_url}")
        return data

    def _extract_series_slug(self, url: str) -> str:
        match = re.search(r"/series/([^/?#]+)", url)
        if not match:
            raise ValueError(f"Tidak dapat mengekstrak slug series Komikcast dari URL: {url}")
        return match.group(1)

    def _extract_chapter_identity(self, chapter_url: str) -> tuple[str, str]:
        match = re.search(r"/series/([^/?#]+)/chapter/([^/?#]+)", chapter_url)
        if not match:
            raise ValueError(f"Tidak dapat mengekstrak chapter identity dari URL: {chapter_url}")
        return match.group(1), match.group(2)

    def _parse_iso_datetime(self, value: str | None) -> datetime | None:
        cleaned = self._clean_text(value)
        if not cleaned:
            return None

        try:
            return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        except ValueError:
            return None

    def _sum_chapter_views(self, chapter_items: list[dict[str, Any]]) -> int | None:
        total = 0
        seen = False

        for chapter in chapter_items:
            views_total = ((chapter.get("views") or {}).get("total"))
            if views_total is None:
                continue
            seen = True
            total += int(views_total)

        return total if seen else None

    def _coalesce_total_view(
        self,
        *,
        item_data: dict[str, Any],
        item_metadata: dict[str, Any],
        item_data_metadata: dict[str, Any],
    ) -> int | None:
        candidates = (
            item_data.get("totalViews"),
            (item_metadata.get("views") or {}).get("total"),
            item_data_metadata.get("totalViewsComputed"),
            item_data_metadata.get("historyViews"),
            item_data_metadata.get("analyticsViews"),
        )

        for value in candidates:
            if value is None:
                continue
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
        return None

    def _parse_api_chapter_items(self, series_slug: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        chapters: list[dict[str, Any]] = []

        for item in items:
            chapter_data = item.get("data") or {}
            chapter_index = chapter_data.get("index")
            if chapter_index is None:
                continue

            raw_title = self._clean_text(chapter_data.get("title"))
            chapter_title = raw_title or f"Chapter {chapter_index}"
            chapters.append(
                self._build_chapter_payload(
                    chapter_number=float(chapter_index),
                    title=chapter_title,
                    source_url=f"{self.BASE_URL}/series/{series_slug}/chapter/{chapter_index}",
                    release_date=self._parse_iso_datetime(item.get("createdAt")),
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
                slug = self._clean_text(data.get("slug"))
                title = self._clean_text(data.get("title"))
                if not slug or not title:
                    continue

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=f"{self.BASE_URL}/series/{slug}",
                        cover_image_url=self._clean_text(data.get("coverImage")) or None,
                        alternative_titles=self._clean_text(data.get("nativeTitle")) or None,
                        author=self._clean_text(data.get("author")) or None,
                        status=self._normalize_status(data.get("status")),
                        type=self._clean_text(data.get("format")) or None,
                        synopsis=self._clean_text(data.get("synopsis")) or None,
                        rating=self._parse_rating(
                            str(data.get("rating")) if data.get("rating") is not None else None
                        ),
                        total_view=self._coalesce_total_view(
                            item_data=data,
                            item_metadata=metadata,
                            item_data_metadata=data_metadata,
                        ),
                        genres=[
                            self._clean_text(genre.get("data", {}).get("name"))
                            for genre in data.get("genres") or []
                            if self._clean_text(genre.get("data", {}).get("name"))
                        ],
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komikcast popular API item: %s", exc)
                continue

        return comics_data

    @classmethod
    def _ensure_session_executor(cls) -> ThreadPoolExecutor:
        if cls._session_executor is None:
            cls._session_executor = ThreadPoolExecutor(
                max_workers=1,
                thread_name_prefix="komikcast-session",
            )
        return cls._session_executor

    @classmethod
    async def _run_session_call(cls, func, /, *args, **kwargs):
        loop = asyncio.get_running_loop()
        executor = cls._ensure_session_executor()
        return await loop.run_in_executor(executor, partial(func, *args, **kwargs))

    @classmethod
    async def get_session(cls) -> DynamicSession:
        """
        Ambil session DynamicSession persisten untuk source ini.

        Session dibuka sekali per process/source run lalu dipakai ulang agar
        startup browser Playwright tidak terulang di setiap request.
        """
        if cls._shared_session is None:
            logger.info("Membuka DynamicSession (Persistent) baru...")
            session = DynamicSession(
                headless=True,
                disable_resources=False,
                network_idle=True,
            )
            try:
                cls._shared_session = await cls._run_session_call(session.__enter__)
            except Exception:
                if cls._session_executor is not None:
                    cls._session_executor.shutdown(wait=False, cancel_futures=True)
                    cls._session_executor = None
                raise
        return cls._shared_session

    @classmethod
    async def close_shared_session(cls) -> None:
        """Tutup session persisten untuk mengosongkan resource browser."""
        if cls._shared_session is not None:
            logger.info("Menutup DynamicSession...")
            session = cls._shared_session
            cls._shared_session = None
            try:
                await cls._run_session_call(session.__exit__, None, None, None)
            finally:
                if cls._session_executor is not None:
                    cls._session_executor.shutdown(wait=False, cancel_futures=True)
                    cls._session_executor = None

    async def close(self) -> None:
        """Cleanup hook untuk pipeline utama/sync full library."""
        await self.close_shared_session()

    async def _fetch_page(
        self,
        url: str,
        *,
        wait_selector: str,
        timeout_ms: int = 45_000,
        wait_ms: int = 1_200,
    ):
        """Render halaman SPA via DynamicSession persisten lalu kembalikan response Scrapling."""
        logger.info("Dynamic session fetch: %s", url)
        session = await self.get_session()
        page = await self._run_session_call(
            session.fetch,
            url,
            wait_selector=wait_selector,
            wait_selector_state="attached",
            timeout=timeout_ms,
            wait=wait_ms,
        )
        if getattr(page, "status", 0) != 200:
            raise RuntimeError(
                f"Gagal fetch halaman target: {url} "
                f"(status={getattr(page, 'status', 'unknown')})"
            )
        return page

    def _build_comics_url(self, *, page: int = 1, query: str | None = None) -> str:
        params: dict[str, Any] = {}
        if page > 1:
            params["page"] = page
        if query:
            params["search"] = query
        if not params:
            return f"{self.BASE_URL}/comics"
        return f"{self.BASE_URL}/comics?{urlencode(params)}"

    async def _fetch_series_index(self, *, page: int = 1, query: str | None = None) -> dict[str, Any]:
        """
        Ambil data katalog langsung dari backend JSON Komikcast.

        SPA `/comics?page=N` tidak membaca query `page` dari URL awal; pagination
        dilakukan lewat request XHR ke `be.komikcast.cc/series`. Karena itu full
        sync/latest harus memakai endpoint ini agar page > 1 tidak selalu
        mengembalikan 12 item halaman pertama.
        """
        params: dict[str, Any] = {
            "takeChapter": 2,
            "includeMeta": "true",
            "sort": "latest",
            "sortOrder": "desc",
            "take": 12,
            "page": max(page, 1),
        }

        if query:
            cleaned_query = self._clean_text(query)
            if cleaned_query:
                params["filter"] = f'title=like="{cleaned_query}",nativeTitle=like="{cleaned_query}"'

        api_url = f"{self.API_BASE_URL}/series?{urlencode(params, doseq=True)}"
        return await self._fetch_api_json(api_url)

    def _parse_relative_release_date(self, text: str | None) -> datetime | None:
        """
        Best-effort parser untuk teks relatif Komikcast seperti `2 day`, `5 hour`.

        Jika format tidak dikenali, return None agar tetap aman.
        """
        cleaned = self._clean_text(text).lower()
        if not cleaned:
            return None

        match = re.search(r"(\d+)\s*(minute|hour|day|week|month|year)", cleaned)
        if not match:
            return None

        amount = int(match.group(1))
        unit = match.group(2)
        now = now_wib().replace(tzinfo=None)

        if unit == "minute":
            return now - timedelta(minutes=amount)
        if unit == "hour":
            return now - timedelta(hours=amount)
        if unit == "day":
            return now - timedelta(days=amount)
        if unit == "week":
            return now - timedelta(weeks=amount)
        if unit == "month":
            return now - timedelta(days=amount * 30)
        if unit == "year":
            return now - timedelta(days=amount * 365)
        return None

    def _extract_type_from_icon(self, response) -> str | None:
        """Deteksi type dari icon header detail bila tersedia."""
        for img in response.css('img[src*="/assets/type-series/"]'):
            src = img.attrib.get("src", "")
            type_key = src.rsplit("/", 1)[-1].split(".", 1)[0].upper()
            comic_type = self._TYPE_MAP.get(type_key)
            if comic_type:
                return comic_type
        return None

    def _extract_genres(self, response) -> list[str]:
        """
        Ambil genre dari query string anchor genre.

        Pada detail page Komikcast, label genre terlihat di elemen turunan/sibling,
        sementara anchor `a[href*="/comics?genres="]` sering tidak punya text langsung.
        Karena itu sumber paling stabil adalah nilai query param `genres`.
        """
        genres: list[str] = []

        for genre_link in response.css('a[href*="/comics?genres="]'):
            href = genre_link.attrib.get("href", "")
            if not href:
                continue

            parsed = urlparse(href)
            for raw_genre in parse_qs(parsed.query).get("genres", []):
                genre_name = self._clean_text(raw_genre)
                if genre_name and genre_name not in genres:
                    genres.append(genre_name)

        return genres

    def _parse_library_cards(self, cards: list) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for card in cards:
            try:
                comic_url = self._resolve_url(card.attrib.get("href"))
                title_el = card.css("h3")
                title = self._clean_text(title_el[0].text if title_el else None)
                if not title or not comic_url:
                    continue

                paragraphs = [self._clean_text(p.text) for p in card.css("p") if self._clean_text(p.text)]
                spans = [self._clean_text(span.text) for span in card.css("span") if self._clean_text(span.text)]

                cover_img = card.css("img")
                cover_url = self._extract_image_url(
                    cover_img[0] if cover_img else None,
                    invalid_substrings=("placehold.co", "/assets/480p.gif"),
                )

                author = paragraphs[0] if len(paragraphs) > 0 else None
                latest_chapter = paragraphs[1] if len(paragraphs) > 1 else None
                status = self._normalize_status(paragraphs[2] if len(paragraphs) > 2 else None)
                summary = paragraphs[3] if len(paragraphs) > 3 else None

                rating = self._parse_rating(spans[0] if len(spans) > 0 else None)
                latest_chapter_number = self._parse_chapter_number(latest_chapter)

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        cover_image_url=cover_url,
                        author=author,
                        status=status,
                        synopsis=summary,
                        rating=rating,
                        latest_chapter=latest_chapter,
                        latest_chapter_number=latest_chapter_number or None,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komikcast library card: %s", exc)
                continue

        return comics_data

    def _parse_series_index_items(self, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []

        for item in items:
            try:
                data = item.get("data") or {}
                slug = self._clean_text(data.get("slug"))
                title = self._clean_text(data.get("title"))
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
                    self._clean_text(genre.get("data", {}).get("name"))
                    for genre in data.get("genres") or []
                    if self._clean_text(genre.get("data", {}).get("name"))
                ]

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=f"{self.BASE_URL}/series/{slug}",
                        cover_image_url=self._clean_text(data.get("coverImage")) or None,
                        alternative_titles=self._clean_text(data.get("nativeTitle")) or None,
                        author=self._clean_text(data.get("author")) or None,
                        status=self._normalize_status(data.get("status")),
                        type=self._clean_text(data.get("format")) or None,
                        synopsis=self._clean_text(data.get("synopsis")) or None,
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

    def _parse_popular_cards(self, cards: list) -> list[dict[str, Any]]:
        comics_data: list[dict[str, Any]] = []
        seen_urls: set[str] = set()

        for card in cards:
            try:
                comic_url = self._resolve_url(card.attrib.get("href"))
                if not comic_url or comic_url in seen_urls:
                    continue

                title_el = card.css("h3")
                title = self._clean_text(title_el[0].text if title_el else None)
                if not title:
                    continue

                spans = [self._clean_text(span.text) for span in card.css("span") if self._clean_text(span.text)]
                latest_chapter = next((text for text in spans if text.lower().startswith("ch.")), None)
                rating_text = next(
                    (
                        text.replace("★", "").strip()
                        for text in spans
                        if text.replace("★", "").strip() and self._parse_rating(text.replace("★", "").strip()) is not None
                    ),
                    None,
                )

                img = card.css("img")
                cover_url = self._extract_image_url(
                    img[0] if img else None,
                    invalid_substrings=("placehold.co", "/assets/480p.gif"),
                )

                seen_urls.add(comic_url)
                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        cover_image_url=cover_url,
                        rating=self._parse_rating(rating_text),
                        latest_chapter=latest_chapter,
                        latest_chapter_number=self._parse_chapter_number(latest_chapter) or None,
                    )
                )
            except Exception as exc:
                logger.warning("Error parsing Komikcast popular card: %s", exc)
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

        Ini lebih stabil daripada parsing DOM `/populer` dan sekaligus memberi
        akses langsung ke ranking dan angka view source.
        """
        api_url = f"{self.API_BASE_URL}/series/most-read?take=20&page={max(page, 1)}"
        payload = await self._fetch_api_json(api_url)
        return self._parse_popular_series_items(payload.get("data") or [])

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        series_slug = self._extract_series_slug(url)
        detail_payload = await self._fetch_api_json(
            f"{self.API_BASE_URL}/series/{series_slug}?includeMeta=true"
        )
        chapters_payload = await self._fetch_api_json(
            f"{self.API_BASE_URL}/series/{series_slug}/chapters"
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
            title=self._clean_text(series_data.get("title")),
            source_url=url,
            alternative_titles=self._clean_text(series_data.get("nativeTitle")) or None,
            cover_image_url=self._clean_text(series_data.get("coverImage")) or None,
            author=self._clean_text(series_data.get("author")) or None,
            status=self._normalize_status(series_data.get("status")),
            type=self._parse_type_from_text(series_data.get("format")),
            synopsis=self._clean_text(series_data.get("synopsis")) or None,
            rating=self._parse_rating(
                str(series_data.get("rating")) if series_data.get("rating") is not None else None
            ),
            total_view=total_view,
            genres=[
                self._clean_text(genre.get("data", {}).get("name"))
                for genre in series_data.get("genres") or []
                if self._clean_text(genre.get("data", {}).get("name"))
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
            f"{self.API_BASE_URL}/series/{series_slug}?includeMeta=true"
        )
        detail = detail_payload.get("data") or {}
        series_data = detail.get("data") or {}
        if not series_data:
            return {}

        total_view = None
        if not requested_fields or "total_view" in requested_fields:
            chapters_payload = await self._fetch_api_json(
                f"{self.API_BASE_URL}/series/{series_slug}/chapters"
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
            title=self._clean_text(series_data.get("title")) or "",
            source_url=url,
            alternative_titles=self._clean_text(series_data.get("nativeTitle")) or None,
            cover_image_url=self._clean_text(series_data.get("coverImage")) or None,
            author=self._clean_text(series_data.get("author")) or None,
            artist=None,
            status=self._normalize_status(series_data.get("status")),
            type=self._parse_type_from_text(series_data.get("format")),
            synopsis=self._clean_text(series_data.get("synopsis")) or None,
            rating=self._parse_rating(
                str(series_data.get("rating")) if series_data.get("rating") is not None else None
            ),
            total_view=total_view,
        )
        return self._build_metadata_patch(detail_patch, fields=requested_fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        series_slug, chapter_number = self._extract_chapter_identity(chapter_url)
        payload = await self._fetch_api_json(
            f"{self.API_BASE_URL}/series/{series_slug}/chapters/{chapter_number}"
        )
        chapter_data = (payload.get("data") or {}).get("data") or {}

        images: list[dict[str, Any]] = []
        for page_number, image_url in enumerate(chapter_data.get("images") or [], start=1):
            cleaned_url = self._clean_text(image_url)
            if not cleaned_url:
                continue
            images.append({"page": page_number, "url": cleaned_url})

        return images

    async def search(self, query: str) -> list[dict[str, Any]]:
        """
        Search memakai backend JSON yang sama dengan katalog SPA.
        """
        lowered_query = self._clean_text(query).lower()
        if not lowered_query:
            return []

        payload = await self._fetch_series_index(page=1, query=lowered_query)
        comics = self._parse_series_index_items(payload.get("data") or [])
        return [
            comic for comic in comics
            if lowered_query in comic.get("title", "").lower()
            or lowered_query in (comic.get("author") or "").lower()
            or lowered_query in (comic.get("synopsis") or "").lower()
        ]

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        payload = await self._fetch_series_index(page=page)
        return self._parse_series_index_items(payload.get("data") or [])
