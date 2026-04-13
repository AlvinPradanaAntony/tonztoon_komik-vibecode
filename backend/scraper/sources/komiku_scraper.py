"""
Tonztoon Komik — Komiku Scraper (Priority 1)

Scraper untuk https://komiku.org/
Menggunakan Scrapling Fetcher untuk halaman statis.

DOM Structure (verified April 2026):
- Homepage (/) latest updates: section#Terbaru > div.ls4w > article.ls4
  - .ls4v img.lazy → cover (data-src)
  - .ls4j h3 a → title + link to /manga/{slug}/
  - .ls4j span.ls4s → "Manga Isekai  19 menit lalu"
  - .ls4j a.ls24 → latest chapter link + title

- Homepage (/) popular/ranking: section#Rekomendasi_Komik article.ls2
  - .ls2v a img.lazy → cover (data-src)
  - .ls2j h3 a → title + link
  - .ls2j span.ls2t → genre + views (e.g. "Fantasi 550rbx")
  - .ls2j a.ls2l → latest chapter link

- Listing page (/daftar-komik/): article.manga-card
  - h4 > a → title + link
  - img.lazy → cover (data-src)
  - p.meta → type & status

- Library page (/pustaka/): same as listing, article.ls4
  
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

    # Alternatif mirror
    MIRROR_URL = "https://01.komiku.asia"

    def _make_slug(self, title: str) -> str:
        """Generate slug dari judul komik."""
        slug = title.lower().strip()
        slug = re.sub(r"[^a-z0-9\s-]", "", slug)
        slug = re.sub(r"[\s-]+", "-", slug)
        return slug.strip("-")

    def _parse_chapter_number(self, text: str) -> float:
        """Extract chapter number dari text seperti 'Chapter 40' atau 'Chapter 10.5'."""
        match = re.search(r"chapter\s*([\d.]+)", text, re.IGNORECASE)
        if match:
            return float(match.group(1))
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

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik terbaru dari halaman utama Komiku.

        Menggunakan section#Terbaru > div.ls4w > article.ls4
        """
        # Halaman utama hanya punya 1 page terbaru
        # Untuk pagination, gunakan /pustaka/ (library page)
        if page > 1:
            url = f"{self.BASE_URL}/pustaka/page/{page}/"
        else:
            url = self.BASE_URL
        logger.info(f"Fetching latest updates page: {url}")

        response = self.fetcher.get(url)
        comics_data = []

        if page == 1:
            # Parse dari homepage section#Terbaru
            comic_entries = response.css("section#Terbaru article.ls4")
            logger.info(f"Found {len(comic_entries)} latest entries on homepage")

            for entry in comic_entries:
                try:
                    # Judul & link from .ls4j h3 a
                    title_el = entry.css(".ls4j h3 a")
                    if not title_el:
                        continue

                    title = self._clean_text(title_el[0].text)
                    if not title:
                        continue

                    # URL komik (link menuju /manga/{slug}/)
                    href = title_el[0].attrib.get("href", "")
                    comic_url = urljoin(self.BASE_URL, href)

                    # Cover image (lazy loaded with data-src)
                    img = entry.css(".ls4v img.lazy")
                    cover_url = None
                    if img:
                        cover_url = img[0].attrib.get("data-src") or img[0].attrib.get("src")
                        if cover_url and "lazy.jpg" in cover_url:
                            cover_url = img[0].attrib.get("data-src")

                    # Type & genre from span.ls4s (e.g. "Manga Isekai  19 menit lalu")
                    comic_type = None
                    meta_el = entry.css(".ls4j span.ls4s")
                    if meta_el:
                        meta_text = self._clean_text(meta_el[0].text)
                        comic_type = self._extract_type_from_text(meta_text)

                    # Latest chapter info
                    ch_el = entry.css(".ls4j a.ls24")
                    latest_chapter = None
                    if ch_el:
                        latest_chapter = self._clean_text(ch_el[0].text)

                    slug = self._make_slug(title)

                    comics_data.append({
                        "title": title,
                        "slug": slug,
                        "cover_image_url": cover_url,
                        "type": comic_type,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                        "latest_chapter": latest_chapter,
                    })

                except Exception as e:
                    logger.warning(f"Error parsing latest update entry: {e}")
                    continue
        else:
            # Pagination menggunakan /pustaka/ — sama dengan format ls4
            comic_entries = response.css("article.ls4")
            logger.info(f"Found {len(comic_entries)} entries on pustaka page {page}")

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

                    comic_type = None
                    meta_el = entry.css(".ls4j span.ls4s")
                    if meta_el:
                        meta_text = self._clean_text(meta_el[0].text)
                        comic_type = self._extract_type_from_text(meta_text)

                    slug = self._make_slug(title)

                    comics_data.append({
                        "title": title,
                        "slug": slug,
                        "cover_image_url": cover_url,
                        "type": comic_type,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                    })

                except Exception as e:
                    logger.warning(f"Error parsing pustaka entry: {e}")
                    continue

        return comics_data

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik populer.

        Halaman utama: section#Rekomendasi_Komik > article.ls2 (Peringkat)
        Atau juga section#Komik_Hot_Manga/Manhwa/Manhua > article.ls2

        Untuk pagination: /pustaka/?orderby=meta_value_num
        """
        if page > 1:
            url = f"{self.BASE_URL}/pustaka/?orderby=meta_value_num&paged={page}"
        else:
            url = self.BASE_URL
        logger.info(f"Fetching popular page: {url}")

        response = self.fetcher.get(url)
        comics_data = []

        if page == 1:
            # Parse dari homepage — ambil dari semua section populer
            # Peringkat + Hot Manga + Hot Manhwa + Hot Manhua
            comic_entries = response.css("article.ls2")
            logger.info(f"Found {len(comic_entries)} popular entries on homepage")

            seen_slugs = set()
            for entry in comic_entries:
                try:
                    # Judul & link from .ls2j h3 a
                    title_el = entry.css(".ls2j h3 a")
                    if not title_el:
                        continue

                    title = self._clean_text(title_el[0].text)
                    if not title:
                        continue

                    # URL komik
                    href = title_el[0].attrib.get("href", "")
                    comic_url = urljoin(self.BASE_URL, href)

                    # Cover image
                    img = entry.css(".ls2v img.lazy")
                    cover_url = None
                    if img:
                        cover_url = img[0].attrib.get("data-src") or img[0].attrib.get("src")
                        if cover_url and "lazy.jpg" in cover_url:
                            cover_url = img[0].attrib.get("data-src")

                    # Genre + views from span.ls2t (e.g. "Fantasi 550rbx")
                    genre_text = None
                    ls2t_el = entry.css(".ls2j span.ls2t")
                    if ls2t_el:
                        genre_text = self._clean_text(ls2t_el[0].text)

                    slug = self._make_slug(title)

                    # Deduplicate (comic may appear in multiple sections)
                    if slug in seen_slugs:
                        continue
                    seen_slugs.add(slug)

                    comics_data.append({
                        "title": title,
                        "slug": slug,
                        "cover_image_url": cover_url,
                        "source_url": comic_url,
                        "source_name": self.SOURCE_NAME,
                    })

                except Exception as e:
                    logger.warning(f"Error parsing popular entry: {e}")
                    continue
        else:
            # Pagination — gunakan ls4 format dari /pustaka/
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
                    logger.warning(f"Error parsing popular page entry: {e}")
                    continue

        return comics_data

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
        # Best source: span[itemprop=name] inside #Judul
        judul_name = response.css('#Judul span[itemprop="name"]')
        if judul_name:
            title = self._clean_text(judul_name[0].text)

        # Fallback: any span[itemprop=name] that isn't a chapter name
        if not title:
            name_els = response.css('span[itemprop="name"]')
            for el in name_els:
                text = self._clean_text(el.text)
                if text and text != "Komiku" and "chapter" not in text.lower():
                    title = text
                    break

        if not title:
            h1_el = response.css("#Judul h1")
            if h1_el:
                raw = self._clean_text(h1_el[0].text)
                title = re.sub(r"^Komik\s+", "", raw, flags=re.IGNORECASE)

        # --- Alternative title ---
        alt_title = None
        alt_el = response.css("#Judul .j2")
        if alt_el:
            alt_title = self._clean_text(alt_el[0].text)

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

                if "author" in key:
                    author = value
                elif "tipe" in key and not comic_type:
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
                    url_match = re.search(r"chapter-(\d+(?:-\d+)?)", ch_href)
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
