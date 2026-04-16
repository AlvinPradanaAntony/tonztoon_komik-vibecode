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
from urllib.parse import urljoin

from scrapling.fetchers import Fetcher

from scraper.base_scraper import BaseComicScraper

logger = logging.getLogger("scraper.komiku")


class KomikuScraper(BaseComicScraper):
    """Scraper implementation untuk Komiku.org."""

    SOURCE_NAME = "komiku"
    BASE_URL = "https://komiku.org"
    LATEST_UPDATES_API_BASE = "https://api.komiku.org/manga"
    POPULAR_API_BASE = "https://api.komiku.org/other/hot"

    # Alternatif mirror
    MIRROR_URL = "https://01.komiku.asia"

    def _make_slug(self, title: str) -> str:
        """Generate slug dari judul komik."""
        slug = title.lower().strip()
        slug = re.sub(r"[^a-z0-9\s-]", "", slug)
        slug = re.sub(r"[\s-]+", "-", slug)
        return slug.strip("-")

    def _parse_chapter_number(self, text: str) -> float:
        """
        Extract chapter number dari text seperti:
        - Chapter 40
        - Chapter 10.5
        - Ch. 01.1
        - Chapter 01-1
        """
        if not text:
            return 0.0

        patterns = [
            r"(?:chapter|chap|ch)\.?\s*([0-9]+(?:[.\-][0-9]+)?)",
            r"\b([0-9]+(?:[.\-][0-9]+)?)\b",
        ]

        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if not match:
                continue

            raw_number = match.group(1).replace("-", ".")
            try:
                return float(raw_number)
            except ValueError:
                continue

        return 0.0

    def _parse_date(self, date_str: str) -> datetime | None:
        """Parse tanggal dari format DD/MM/YYYY."""
        try:
            return datetime.strptime(date_str.strip(), "%d/%m/%Y")
        except (ValueError, AttributeError):
            return None

    def _clean_text(self, text: str | None) -> str:
        """Bersihkan whitespace berlebih dari text."""
        if not text:
            return ""
        return re.sub(r"\s+", " ", text).strip()

    def _extract_type_from_text(self, text: str) -> str | None:
        """Extract tipe komik (manga/manhwa/manhua) dari text."""
        text_lower = text.lower()
        for t in ["manhwa", "manhua", "manga"]:
            if t in text_lower:
                return t
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
        logger.info(f"Fetching latest updates page {page}: {url}")

        response = self.fetcher.get(url)
        comic_entries = response.css("div.bge")
        logger.info(f"Found {len(comic_entries)} latest entries from canonical API")
        return self._parse_library_entries(comic_entries)

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

                title = self._clean_text(title_el[0].text)
                if not title:
                    continue

                link_el = entry.css(".kan > a")
                if not link_el:
                    link_el = entry.css(".bgei a")
                if not link_el:
                    continue

                href = link_el[0].attrib.get("href", "")
                comic_url = urljoin(self.BASE_URL, href)

                img = entry.css(".bgei img")
                cover_url = None
                if img:
                    cover_url = img[0].attrib.get("src") or img[0].attrib.get("data-src")

                comic_type = None
                type_el = entry.css(".bgei .tpe1_inf b")
                if type_el:
                    comic_type = self._extract_type_from_text(type_el[0].text)

                meta_text = None
                meta_el = entry.css(".kan .judul2")
                if meta_el:
                    meta_text = self._clean_text(meta_el[0].text)

                summary = None
                summary_el = entry.css(".kan p")
                if summary_el:
                    summary = self._clean_text(summary_el[0].text)

                chapter_links = entry.css(".kan .new1 a")
                first_chapter = None
                first_chapter_url = None
                latest_chapter = None
                latest_chapter_url = None
                if chapter_links:
                    first_el = chapter_links[0]
                    latest_el = chapter_links[-1]

                    first_spans = first_el.css("span")
                    if len(first_spans) >= 2:
                        first_chapter = self._clean_text(first_spans[-1].text)
                    else:
                        first_chapter = self._clean_text(first_el.text)

                    first_href = first_el.attrib.get("href", "")
                    if first_href:
                        first_chapter_url = urljoin(self.BASE_URL, first_href)

                    latest_spans = latest_el.css("span")
                    if len(latest_spans) >= 2:
                        latest_chapter = self._clean_text(latest_spans[-1].text)
                    else:
                        latest_chapter = self._clean_text(latest_el.text)

                    latest_href = latest_el.attrib.get("href", "")
                    if latest_href:
                        latest_chapter_url = urljoin(self.BASE_URL, latest_href)

                slug = self._make_slug(title)

                comics_data.append({
                    "title": title,
                    "slug": slug,
                    "cover_image_url": cover_url,
                    "type": comic_type,
                    "source_url": comic_url,
                    "source_name": self.SOURCE_NAME,
                    "listing_meta": meta_text,
                    "summary": summary,
                    "first_chapter": first_chapter,
                    "first_chapter_url": first_chapter_url,
                    "latest_chapter": latest_chapter,
                    "latest_chapter_url": latest_chapter_url,
                })

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
        logger.info(f"Fetching popular page: {url}")

        response = self.fetcher.get(url)
        comic_entries = response.css("div.bge")
        logger.info(f"Found {len(comic_entries)} popular entries from canonical API")
        return self._parse_library_entries(comic_entries)

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
        logger.info(f"Fetching comic detail: {url}")
        response = self.fetcher.get(url)

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
            title = self._clean_text(title_elements[0].text)
            if title:
                break

        # Fallback: any span[itemprop=name] that isn't a chapter name
        if not title:
            name_els = response.css('span[itemprop="name"]')
            for el in name_els:
                text = self._clean_text(el.text)
                if text and text != "Komiku" and "chapter" not in text.lower():
                    title = text
                    break

        if not title:
            head_title_el = response.css("head title") 
            if head_title_el:
                head_title = self._clean_text(head_title_el[0].text)
                title = re.sub(r"\s*-\s*Komiku$", "", head_title, flags=re.IGNORECASE)

        if title:
            title = re.sub(r"^Komik\s+", "", title, flags=re.IGNORECASE)

        # --- Alternative title ---
        alt_title = None
        alt_selectors = ["#Judul .j2", "table.inftable tr:nth-child(2) td:last-child"]
        for selector in alt_selectors:
            alt_elements = response.css(selector)
            if not alt_elements:
                continue
            alt_title = self._clean_text(alt_elements[0].text)
            if alt_title:
                break

        # --- Cover image ---
        cover_url = None
        cover_img = response.css(".ims img")
        if cover_img:
            cover_url = cover_img[0].attrib.get("src")
        if not cover_url:
            cover_img2 = response.css('img[itemprop="image"]')
            if cover_img2:
                cover_url = cover_img2[0].attrib.get("src")

        # --- Type from meta ---
        comic_type = None
        type_meta = response.css('meta[itemprop="additionalType"]')
        if type_meta:
            comic_type = type_meta[0].attrib.get("content", "").lower()

        # --- Status from meta ---
        status = None
        status_meta = response.css('meta[itemprop="creativeWorkStatus"]')
        if status_meta:
            status = status_meta[0].attrib.get("content", "").lower()

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
                g = self._clean_text(gl.text)
                if g and g not in genres:
                    genres.append(g)

        # --- Author ---
        author = None
        # Try info table first (more reliable than meta)
        info_rows = response.css("table.inftable tr")
        for row in info_rows:
            tds = row.css("td")
            if len(tds) >= 2:
                key = self._clean_text(tds[0].text).lower().rstrip(":")
                value = self._clean_text(tds[1].text)

                if "judul komik" in key and not title:
                    title = value
                elif "judul indonesia" in key and not alt_title:
                    alt_title = value
                elif "author" in key or "pengarang" in key:
                    author = value
                elif "tipe" in key and not comic_type:
                    comic_type = value.lower()
                elif "jenis komik" in key and not comic_type:
                    comic_type = value.lower()
                elif "status" in key and not status:
                    status = value.lower()

        # --- Synopsis ---
        synopsis = None
        desc_el = response.css('p.desc[itemprop="description"]')
        if desc_el:
            synopsis = self._clean_text(desc_el[0].text)
        if not synopsis:
            desc_el2 = response.css("p.desc")
            if desc_el2:
                synopsis = self._clean_text(desc_el2[0].text)

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
                ch_url = urljoin(self.BASE_URL, ch_href)

                ch_name_el = ch_row.css("span[itemprop='name']")
                ch_title = ""
                if ch_name_el:
                    # The title text is inside a <b> tag within the span
                    b_el = ch_name_el[0].css("b")
                    if b_el:
                        ch_title = self._clean_text(b_el[0].text)
                    if not ch_title:
                        ch_title = self._clean_text(ch_name_el[0].text)

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

                chapters.append({
                    "chapter_number": ch_number,
                    "title": ch_title,
                    "source_url": ch_url,
                    "release_date": release_date,
                })

            except Exception as e:
                logger.warning(f"Error parsing chapter row: {e}")
                continue

        slug = self._make_slug(title)

        return {
            "title": title,
            "slug": slug,
            "alternative_titles": alt_title,
            "cover_image_url": cover_url,
            "author": author,
            "artist": None,  # Komiku doesn't separate artist
            "status": status,
            "type": comic_type,
            "synopsis": synopsis,
            "rating": None,  # Komiku doesn't expose a numeric rating
            "source_url": url,
            "source_name": self.SOURCE_NAME,
            "genres": genres,
            "chapters": chapters,
        }

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
        logger.info(f"Fetching chapter images: {chapter_url}")
        response = self.fetcher.get(chapter_url)

        images = []
        img_elements = response.css("#Baca_Komik img")

        for i, img in enumerate(img_elements, start=1):
            img_url = img.attrib.get("src", "")
            if not img_url or "lazy" in img_url:
                # Fallback ke data-src jika src adalah placeholder
                img_url = img.attrib.get("data-src", "")

            if img_url:
                images.append({
                    "page": i,
                    "url": img_url,
                })

        logger.info(f"Found {len(images)} images in chapter")
        return images

    async def search(self, query: str) -> list[dict[str, Any]]:
        """
        Cari komik berdasarkan keyword.

        Komiku search result menggunakan format yang sama dengan listing page.
        URL: https://komiku.org/?post_type=manga&s={query}

        Hasilnya menggunakan format daftar komik (article.manga-card atau article.ls4).
        """
        url = f"{self.BASE_URL}/?post_type=manga&s={query}"
        logger.info(f"Searching comics: {url}")

        response = self.fetcher.get(url)
        comics_data = []

        # Search results bisa pakai format manga-card atau ls4
        # Coba manga-card dulu
        comic_entries = response.css("article.manga-card")

        if not comic_entries:
            # Fallback ke format ls4
            comic_entries = response.css("article.ls4")

            for entry in comic_entries:
                try:
                    title_el = entry.css(".ls4j h3 a")
                    if not title_el:
                        continue

                    title = self._clean_text(title_el[0].text)
                    if not title:
                        continue

                    href = title_el[0].attrib.get("href", "")
                    comic_url = urljoin(self.BASE_URL, href)

                    img = entry.css(".ls4v img.lazy")
                    cover_url = None
                    if img:
                        cover_url = img[0].attrib.get("data-src") or img[0].attrib.get("src")
                        if cover_url and "lazy.jpg" in cover_url:
                            cover_url = img[0].attrib.get("data-src")

                    slug = self._make_slug(title)

                    comics_data.append({
                        "title": title,
                        "slug": slug,
                        "cover_image_url": cover_url,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                    })

                except Exception as e:
                    logger.warning(f"Error parsing search result (ls4): {e}")
                    continue
        else:
            # manga-card format
            for entry in comic_entries:
                try:
                    title_el = entry.css("h4 a")
                    if not title_el:
                        continue

                    title = self._clean_text(title_el[0].text)
                    if not title:
                        continue

                    href = title_el[0].attrib.get("href", "")
                    comic_url = urljoin(self.BASE_URL, href)

                    img = entry.css("img.lazy")
                    cover_url = None
                    if img:
                        cover_url = img[0].attrib.get("data-src") or img[0].attrib.get("src")
                        if cover_url and "lazy.jpg" in cover_url:
                            cover_url = img[0].attrib.get("data-src")

                    slug = self._make_slug(title)

                    comics_data.append({
                        "title": title,
                        "slug": slug,
                        "cover_image_url": cover_url,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                    })

                except Exception as e:
                    logger.warning(f"Error parsing search result (manga-card): {e}")
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
            
        logger.info(f"Fetching comic list: {url}")

        response = self.fetcher.get(url)
        comics_data = []

        comic_entries = response.css("article.manga-card")
        
        for entry in comic_entries:
            try:
                title_el = entry.css("h4 a")
                if not title_el:
                    continue

                title = self._clean_text(title_el[0].text)
                if not title:
                    continue

                href = title_el[0].attrib.get("href", "")
                comic_url = urljoin(self.BASE_URL, href)

                img = entry.css("img.lazy")
                cover_url = None
                if img:
                    cover_url = img[0].attrib.get("data-src") or img[0].attrib.get("src")
                    if cover_url and "lazy.jpg" in cover_url:
                        cover_url = img[0].attrib.get("data-src")

                # Type and status
                comic_type = None
                status = None
                meta_el = entry.css("p.meta")
                if meta_el:
                    meta_text = self._clean_text(meta_el[0].get_all_text())
                    comic_type = self._extract_type_from_text(meta_text)
                    if "Ongoing" in meta_text or "ongoing" in meta_text:
                        status = "ongoing"
                    elif "Completed" in meta_text or "End" in meta_text or "completed" in meta_text or "end" in meta_text:
                        status = "completed"

                slug = self._make_slug(title)

                comics_data.append({
                    "title": title,
                    "slug": slug,
                    "cover_image_url": cover_url,
                    "type": comic_type,
                    "status": status,
                    "source_url": comic_url,
                    "source_name": self.SOURCE_NAME,
                })

            except Exception as e:
                logger.warning(f"Error parsing comic list result: {e}")
                continue

        return comics_data
