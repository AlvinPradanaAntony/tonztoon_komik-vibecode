"""
Tonztoon Komik — Komiku Scraper (Priority 1)

Scraper untuk https://komiku.org/ dan https://01.komiku.asia/
Menggunakan Fetcher untuk halaman statis.

TODO: Implementasi penuh setelah analisis struktur DOM situs.
"""

import re
from typing import Any
from urllib.parse import urljoin

from scrapling.fetchers import Fetcher

from scraper.base_scraper import BaseComicScraper


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

    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil daftar komik terbaru dari halaman utama Komiku."""
        # TODO: Implementasi setelah analisis DOM
        # Contoh flow:
        # url = f"{self.BASE_URL}/daftar-komik/page/{page}/"
        # response = self.fetcher.get(url)
        # comics = response.css('.daftar .bge')
        # ...
        return []

    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """Ambil daftar komik populer."""
        # TODO: Implementasi setelah analisis DOM
        return []

    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        """Ambil detail lengkap komik dari halaman detail."""
        # TODO: Implementasi setelah analisis DOM
        # Contoh flow:
        # response = self.fetcher.get(url)
        # title = response.css('#Judul h1::text').get()
        # ...
        return {}

    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        """Ambil semua gambar dari halaman chapter."""
        # TODO: Implementasi setelah analisis DOM
        # Contoh flow:
        # response = self.fetcher.get(chapter_url)
        # imgs = response.css('.bc img::attr(src)').getall()
        # return [{"page": i+1, "url": url} for i, url in enumerate(imgs)]
        return []

    async def search(self, query: str) -> list[dict[str, Any]]:
        """Cari komik berdasarkan keyword."""
        # TODO: Implementasi setelah analisis DOM
        # url = f"{self.BASE_URL}/?post_type=manga&s={query}"
        # response = self.fetcher.get(url)
        # ...
        return []
