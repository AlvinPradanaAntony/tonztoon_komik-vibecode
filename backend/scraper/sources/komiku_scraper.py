"""
Tonztoon Komik — Komiku Scraper (Priority 1)

Scraper untuk https://komiku.org/
Menggunakan Scrapling Fetcher untuk halaman statis.

DOM Structure (verified April 2026):
- Homepage (/) latest updates: section#Terbaru > div.ls4w > article.ls4
  - Ada di homepage, tapi bukan source of truth yang dipakai scraper.
  - Sumber canonical untuk sinkronisasi "Terbaru" ada di /pustaka/ yang
    mengambil data infinite scroll dari endpoint API di bawah.

- Homepage (/) popular/ranking: section#Rekomendasi_Komik article.ls2
  - Ada di homepage, tapi bukan source of truth yang dipakai scraper.
  - Sumber canonical untuk sinkronisasi "Populer" ada di /other/hot/ yang
    mengambil data infinite scroll dari endpoint API canonical.

- Listing page (/daftar-komik/): article.manga-card
  - h4 > a → title + link
  - img.lazy → cover (data-src)
  - p.meta → type & status

- Library page (/pustaka/): div.bge (NOT article.ls4 — different from homepage)
  Uses HTMX infinite scroll via https://api.komiku.org/manga/page/{N}/
  - .bgei img → cover (direct src, no lazy)
  - .kan > a[href] → comic URL
  - .kan h3 → title
  - .kan .judul2 → views + update time + color indicator
  - .kan .new1:first-of-type a → first chapter link + title
  - .kan .new1:last-of-type a → latest chapter link + title
  
- Detail page (/manga/{slug}/):
  - #Judul h1 > span > span[itemprop=name] → title
  - #Judul .j2 → alternative title
  - .ims img → cover image (src, not lazy)
  - meta[itemprop=additionalType] → type (Manga/Manhwa/Manhua)
  - meta[itemprop=creativeWorkStatus] → status (Ongoing/End)
  - meta[itemprop=genre] → genres (multiple)
  - table.inftable tr → info table (Judul, Author, Status, etc.)
  - p.desc[itemprop=description] → synopsis
  - #daftarChapter tr[itemprop=itemListElement] → chapter rows
    - a[itemprop=url] → chapter link
    - span[itemprop=name] → chapter name
    - td.tanggalseries → release date (DD/MM/YYYY)

- Chapter page (/{slug}-chapter-{n}/):
  - #Baca_Komik img → chapter images
"""

import logging
import re
from datetime import datetime
from typing import Any

from scraper.base_scraper import BaseComicScraper
from scraper.sources.common import ScraperCommonMixin
from scraper.utils import clean_text

logger = logging.getLogger("scraper.komiku")


class KomikuScraper(ScraperCommonMixin, BaseComicScraper):
    """Scraper implementation untuk Komiku.org."""

    SOURCE_NAME = "komiku"
    BASE_URL = "https://komiku.org"
    LATEST_UPDATES_API_BASE = "https://api.komiku.org/manga"
    POPULAR_API_BASE = "https://api.komiku.org/other/hot"

    # Alternatif mirror
    MIRROR_URL = "https://01.komiku.asia"

    def _fetch_page(self, url: str):
        """Ambil halaman statis Komiku dengan Fetcher standar."""
        logger.info("Fetch page: %s", url)
        return self.fetcher.get(url)

    def _parse_date(self, date_str: str) -> datetime | None:
        """Parse tanggal dari format DD/MM/YYYY."""
        try:
            return datetime.strptime(date_str.strip(), "%d/%m/%Y")
        except (ValueError, AttributeError):
            return None

    def _build_latest_updates_url(self, page: int) -> str:
        """Bangun URL latest update dari endpoint canonical Komiku."""
        if page <= 1:
            return f"{self.LATEST_UPDATES_API_BASE}/"
        return f"{self.LATEST_UPDATES_API_BASE}/page/{page}/"

    def _build_popular_url(self, page: int) -> str:
        """Bangun URL popular dari endpoint canonical Komiku."""
        if page <= 1:
            return f"{self.POPULAR_API_BASE}/"
        return f"{self.POPULAR_API_BASE}/page/{page}/"

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik terbaru dari sumber canonical Komiku.

        Source of truth untuk listing "Terbaru" ada di `/pustaka/` yang
        melakukan infinite scroll ke endpoint:
          https://api.komiku.org/manga/page/{page}/

        Endpoint ini langsung mengembalikan fragmen `div.bge`, sehingga lebih
        akurat dan lebih stabil untuk cron dibanding scraping potongan homepage.
        """
        url = self._build_latest_updates_url(page)
        response = self._fetch_page(url)
        comic_entries = response.css("div.bge")
        logger.info("Found %s latest entries from canonical API", len(comic_entries))
        return self._parse_library_entries(comic_entries)

    def _extract_chapter_link_data(self, chapter_link) -> tuple[str | None, str | None]:
        """Ambil judul dan URL chapter dari node anchor listing."""
        if chapter_link is None:
            return None, None

        spans = chapter_link.css("span")
        chapter_title = (
            clean_text(spans[-1].text)
            if len(spans) >= 2
            else clean_text(chapter_link.text)
        )
        chapter_url = self._resolve_url(chapter_link.attrib.get("href"))
        return chapter_title or None, chapter_url or None

    def _parse_library_entries(self, comic_entries: list) -> list[dict[str, Any]]:
        """
        Parse daftar `div.bge` dari library page/API Komiku.

        DOM div.bge:
          .bgei img          → cover image
          .bgei .tpe1_inf b  → type (Manga/Manhwa/Manhua)
          .kan > a[href]     → comic URL
          .kan h3            → title
          .kan .judul2       → views + relative update time
          .kan .new1 a       → first/latest chapter links
        """
        comics_data = []
        for entry in comic_entries:
            try:
                title_el = entry.css(".kan h3")
                if not title_el:
                    continue

                title = clean_text(title_el[0].text)
                if not title:
                    continue

                link_el = entry.css(".kan > a")
                if not link_el:
                    link_el = entry.css(".bgei a")
                if not link_el:
                    continue

                comic_url = self._resolve_url(link_el[0].attrib.get("href"))

                img = entry.css(".bgei img")
                cover_url = self._extract_image_url(img[0] if img else None)

                comic_type = None
                type_el = entry.css(".bgei .tpe1_inf b")
                if type_el:
                    comic_type = self._parse_type_from_text(type_el[0].text)

                meta_text = None
                meta_el = entry.css(".kan .judul2")
                if meta_el:
                    meta_text = clean_text(meta_el[0].text)

                summary = None
                summary_el = entry.css(".kan p")
                if summary_el:
                    summary = clean_text(summary_el[0].text)

                chapter_links = entry.css(".kan .new1 a")
                first_chapter = None
                first_chapter_url = None
                latest_chapter = None
                latest_chapter_url = None
                if chapter_links:
                    first_chapter, first_chapter_url = self._extract_chapter_link_data(chapter_links[0])
                    latest_chapter, latest_chapter_url = self._extract_chapter_link_data(chapter_links[-1])

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        cover_image_url=cover_url,
                        type=comic_type,
                        listing_meta=meta_text,
                        summary=summary,
                        first_chapter=first_chapter,
                        first_chapter_url=first_chapter_url,
                        latest_chapter=latest_chapter,
                        latest_chapter_url=latest_chapter_url,
                    )
                )

            except Exception as e:
                logger.warning(f"Error parsing library entry: {e}")
                continue
        return comics_data

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik populer dari sumber canonical Komiku.

        Source of truth untuk listing "Populer" ada di `/other/hot/` yang
        melakukan infinite scroll ke endpoint:
          https://api.komiku.org/other/hot/page/{page}/

        Endpoint ini mengembalikan fragmen `div.bge` yang konsisten antar-page,
        jadi lebih tepat dipakai daripada mencampur homepage dan `/pustaka/`.
        """
        url = self._build_popular_url(page)
        response = self._fetch_page(url)
        comic_entries = response.css("div.bge")
        logger.info("Found %s popular entries from canonical API", len(comic_entries))
        return self._parse_library_entries(comic_entries)

    def _extract_info_table_map(self, response) -> dict[str, str]:
        """Bangun map metadata dari tabel informasi detail komik."""
        info_map: dict[str, str] = {}
        for row in response.css("table.inftable tr"):
            cells = row.css("td")
            if len(cells) < 2:
                continue

            key = clean_text(cells[0].text).lower().rstrip(":")
            value = clean_text(cells[1].get_all_text())
            if key:
                info_map[key] = value
        return info_map

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        """
        Ambil detail lengkap komik dari halaman detail.

        DOM Structure:
        - #Judul h1 > span > span[itemprop="name"] → title
        - #Judul .j2 → alternative title
        - .ims img → cover image (src, NOT lazy)
        - meta[itemprop="additionalType"] → type (Manga/Manhwa/Manhua)
        - meta[itemprop="creativeWorkStatus"] → status (Ongoing/End)
        - meta[itemprop="genre"] → genres (multiple)
        - table.inftable tr → info table
        - p.desc[itemprop="description"] → synopsis
        - #daftarChapter tr[itemprop="itemListElement"] → chapter list
          - a[itemprop="url"] → chapter link
          - span[itemprop="name"] → chapter name
          - td.tanggalseries → release date (DD/MM/YYYY)
        """
        response = self._fetch_page(url)

        # --- Title ---
        title = ""
        title_selectors = [
            '#Judul span[itemprop="name"]',
            "#Judul h1 span",
            "#Judul h1",
            "table.inftable tr:first-child td:last-child",
        ]
        for selector in title_selectors:
            title_elements = response.css(selector)
            if not title_elements:
                continue
            title = clean_text(title_elements[0].text)
            if title:
                break

        # Fallback: any span[itemprop=name] that isn't a chapter name
        if not title:
            name_els = response.css('span[itemprop="name"]')
            for el in name_els:
                text = clean_text(el.text)
                if text and text != "Komiku" and "chapter" not in text.lower():
                    title = text
                    break

        if not title:
            head_title_el = response.css("head title") 
            if head_title_el:
                head_title = clean_text(head_title_el[0].text)
                title = re.sub(r"\s*-\s*Komiku$", "", head_title, flags=re.IGNORECASE)

        if title:
            title = re.sub(r"^Komik\s+", "", title, flags=re.IGNORECASE)

        info_map = self._extract_info_table_map(response)

        # --- Alternative title ---
        alt_title = None
        alt_selectors = ["#Judul .j2"]
        for selector in alt_selectors:
            alt_elements = response.css(selector)
            if not alt_elements:
                continue
            alt_title = clean_text(alt_elements[0].text)
            if alt_title:
                break
        if not alt_title:
            alt_title = info_map.get("judul indonesia")

        # --- Cover image ---
        cover_img = response.css(".ims img")
        cover_url = self._extract_image_url(cover_img[0] if cover_img else None, invalid_substrings=())
        if not cover_url:
            cover_img2 = response.css('img[itemprop="image"]')
            cover_url = self._extract_image_url(cover_img2[0] if cover_img2 else None, invalid_substrings=())

        # --- Type from meta ---
        comic_type = None
        type_meta = response.css('meta[itemprop="additionalType"]')
        if type_meta:
            comic_type = self._parse_type_from_text(type_meta[0].attrib.get("content", ""))

        # --- Status from meta ---
        status = None
        status_meta = response.css('meta[itemprop="creativeWorkStatus"]')
        if status_meta:
            status = self._normalize_status(status_meta[0].attrib.get("content"))

        # --- Genres from meta ---
        genres = []
        genre_metas = response.css('meta[itemprop="genre"]')
        for gm in genre_metas:
            genre_name = gm.attrib.get("content", "").strip()
            if genre_name and genre_name not in genres:
                genres.append(genre_name)

        # --- Fallback genres from info table ---
        if not genres:
            genre_list = response.css("table.inftable ul.genre li.genre a span")
            for gl in genre_list:
                g = clean_text(gl.text)
                if g and g not in genres:
                    genres.append(g)

        # --- Author ---
        author = None
        # Try info table first (more reliable than meta)
        if not title:
            title = info_map.get("judul komik", "")
        author = info_map.get("author") or info_map.get("pengarang")
        if not comic_type:
            comic_type = self._parse_type_from_text(
                info_map.get("tipe") or info_map.get("jenis komik")
            )
        if not status:
            status = self._normalize_status(info_map.get("status"))

        # --- Synopsis ---
        synopsis = None
        desc_el = response.css('p.desc[itemprop="description"]')
        if desc_el:
            synopsis = clean_text(desc_el[0].text)
        if not synopsis:
            desc_el2 = response.css("p.desc")
            if desc_el2:
                synopsis = clean_text(desc_el2[0].text)

        if not title:
            logger.warning(
                "Komiku detail tanpa title. selector utama tidak cocok untuk url=%s",
                url,
            )

        # --- Chapters ---
        chapters = []
        chapter_rows = response.css("#daftarChapter tr[itemprop='itemListElement']")
        for ch_row in chapter_rows:
            try:
                ch_link = ch_row.css("a[itemprop='url']")
                if not ch_link:
                    continue

                ch_href = ch_link[0].attrib.get("href", "")
                ch_url = self._resolve_url(ch_href)

                ch_name_el = ch_row.css("span[itemprop='name']")
                ch_title = ""
                if ch_name_el:
                    # The title text is inside a <b> tag within the span
                    b_el = ch_name_el[0].css("b")
                    if b_el:
                        ch_title = clean_text(b_el[0].text)
                    if not ch_title:
                        ch_title = clean_text(ch_name_el[0].text)

                ch_number = self._parse_chapter_number(ch_title)

                # Fallback: parse from <a> title attribute
                # e.g. "Baca World Trigger Chapter 253 Bahasa Indonesia"
                if ch_number == 0.0 and ch_link:
                    link_title = ch_link[0].attrib.get("title", "")
                    ch_number = self._parse_chapter_number(link_title)
                    if not ch_title:
                        ch_title = f"Chapter {ch_number}" if ch_number else ""

                # Fallback: parse from URL path
                # e.g. /world-trigger-chapter-253/
                if ch_number == 0.0 and ch_href:
                    url_match = re.search(
                        r"(?:chapter|chap|ch)-(\d+(?:[.-]\d+)?)",
                        ch_href,
                        re.IGNORECASE,
                    )
                    if url_match:
                        raw_num = url_match.group(1).replace("-", ".")
                        try:
                            ch_number = float(raw_num)
                        except ValueError:
                            pass

                # Release date
                date_td = ch_row.css("td.tanggalseries")
                release_date = None
                if date_td:
                    release_date = self._parse_date(date_td[0].text)

                chapters.append(
                    self._build_chapter_payload(
                        chapter_number=ch_number,
                        title=ch_title,
                        source_url=ch_url,
                        release_date=release_date,
                    )
                )

            except Exception as e:
                logger.warning(f"Error parsing chapter row: {e}")
                continue

        return self._build_comic_payload(
            title=title,
            source_url=url,
            alternative_titles=alt_title,
            cover_image_url=cover_url,
            author=author,
            artist=None,  # Komiku doesn't separate artist
            status=status,
            type=comic_type,
            synopsis=synopsis,
            rating=None,  # Komiku doesn't expose a numeric rating
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
        Refresh metadata Komiku dari detail page tanpa ikut memproses chapter.

        Komiku belum punya endpoint metadata ringan yang terpisah, jadi patch
        dibangun dari halaman detail yang sama, lalu pipeline hanya meng-update
        kolom yang diminta.
        """
        detail = await self.get_comic_detail(url)
        return self._build_metadata_patch(detail, fields=fields)

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        """
        Ambil semua gambar dari halaman chapter.

        DOM Structure:
        <div id="Baca_Komik">
          <img src="https://img.komiku.org/..." class="klazy ww" id="1" />
          <img src="..." class="klazy ww" id="2" />
          ...
        </div>
        """
        response = self._fetch_page(chapter_url)

        images = []
        img_elements = response.css("#Baca_Komik img")

        for i, img in enumerate(img_elements, start=1):
            img_url = self._extract_image_url(img, invalid_substrings=("lazy", "lazy.jpg"))

            if img_url:
                images.append({
                    "page": i,
                    "url": img_url,
                })

        logger.info("Found %s images in chapter", len(images))
        return images

    def _parse_manga_card_entries(
        self,
        comic_entries: list,
        *,
        include_meta: bool,
    ) -> list[dict[str, Any]]:
        """Parse format `article.manga-card` yang dipakai katalog publik Komiku."""
        comics_data: list[dict[str, Any]] = []

        for entry in comic_entries:
            try:
                title_el = entry.css("h4 a")
                if not title_el:
                    continue

                title = clean_text(title_el[0].text)
                if not title:
                    continue

                comic_url = self._resolve_url(title_el[0].attrib.get("href"))
                img = entry.css("img.lazy")
                cover_url = self._extract_image_url(img[0] if img else None)

                payload: dict[str, Any] = {
                    "cover_image_url": cover_url,
                }
                if include_meta:
                    meta_el = entry.css("p.meta")
                    meta_text = clean_text(meta_el[0].get_all_text()) if meta_el else ""
                    payload["type"] = self._parse_type_from_text(meta_text)
                    if "ongoing" in meta_text.lower():
                        payload["status"] = self._normalize_status(meta_text)
                    elif any(keyword in meta_text.lower() for keyword in ("completed", "end")):
                        payload["status"] = self._normalize_status(meta_text)

                comics_data.append(
                    self._build_comic_payload(
                        title=title,
                        source_url=comic_url,
                        **payload,
                    )
                )

            except Exception as e:
                logger.warning("Error parsing manga-card entry: %s", e)
                continue

        return comics_data

    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik keseluruhan dari halaman daftar-komik.
        
        URL: https://komiku.org/daftar-komik/?halaman={page} (kalau page > 1) 
        atau https://komiku.org/daftar-komik/

        Hasilnya menggunakan format daftar komik (article.manga-card).
        """
        if page > 1:
            url = f"{self.BASE_URL}/daftar-komik/?halaman={page}"
        else:
            url = f"{self.BASE_URL}/daftar-komik/"
            
        response = self._fetch_page(url)
        comic_entries = response.css("article.manga-card")
        return self._parse_manga_card_entries(comic_entries, include_meta=True)

    def _extract_total_comics_from_listing(self, response) -> int | None:
        """Ambil total komik langsung dari elemen `.page-info` halaman katalog."""
        for node in response.css(".page-info"):
            text = clean_text(node.get_all_text())
            if not text:
                continue

            match = re.search(r"\(([\d.,]+)\s+komik\)", text, flags=re.IGNORECASE)
            if not match:
                continue

            try:
                return int(match.group(1).replace(".", "").replace(",", ""))
            except ValueError:
                continue

        return None

    async def get_source_comic_count(self) -> int | None:
        """Ambil total komik Komiku dari metadata `.page-info` katalog publik."""
        first_page_url = f"{self.BASE_URL}/daftar-komik/"
        first_response = self._fetch_page(first_page_url)
        total_comics = self._extract_total_comics_from_listing(first_response)
        if total_comics is not None:
            return total_comics

        # Fallback minimal jika metadata total tidak tersedia.
        return len(first_response.css("article.manga-card"))
