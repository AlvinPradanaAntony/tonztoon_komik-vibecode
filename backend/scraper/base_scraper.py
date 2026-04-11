"""
Tonztoon Komik — Base Comic Scraper

Abstract Base Class yang harus diimplementasikan oleh setiap source scraper.
Scraper menggunakan model dari `app.models` untuk database operations
dan `app.schemas` untuk validasi data hasil scraping.
"""

from abc import ABC, abstractmethod
from typing import Any

from scrapling.fetchers import Fetcher, StealthyFetcher, DynamicFetcher


class BaseComicScraper(ABC):
    """
    Abstract Base Class untuk semua comic scraper.

    Setiap source (komiku, komikcast, shinigami) harus mengimplementasikan
    semua method abstract di bawah ini.
    """

    # Nama sumber — digunakan untuk identifikasi di database
    SOURCE_NAME: str = ""
    BASE_URL: str = ""

    def __init__(self):
        self.fetcher = Fetcher
        self.stealthy_fetcher = StealthyFetcher
        self.dynamic_fetcher = DynamicFetcher

    @abstractmethod
    async def get_latest_updates(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik yang baru di-update.

        Returns:
            List of dict berisi data komik sesuai ComicBase schema.
        """
        pass

    @abstractmethod
    async def get_popular(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik populer.

        Returns:
            List of dict berisi data komik sesuai ComicBase schema.
        """
        pass

    @abstractmethod
    async def get_comic_detail(self, url: str) -> dict[str, Any]:
        """
        Ambil detail lengkap komik (metadata + daftar chapter).

        Args:
            url: URL halaman detail komik di situs sumber.

        Returns:
            Dict berisi data lengkap komik sesuai ComicCreate schema.
        """
        pass

    @abstractmethod
    async def get_chapter_images(self, chapter_url: str) -> list[dict[str, Any]]:
        """
        Ambil semua URL gambar dari satu chapter.

        Args:
            chapter_url: URL halaman chapter di situs sumber.

        Returns:
            List of dict sesuai ChapterImageItem schema:
            [{"page": 1, "url": "..."}, {"page": 2, "url": "..."}, ...]
        """
        pass

    @abstractmethod
    async def search(self, query: str) -> list[dict[str, Any]]:
        """
        Cari komik berdasarkan keyword.

        Args:
            query: Keyword pencarian.

        Returns:
            List of dict berisi data komik hasil pencarian.
        """
        pass
