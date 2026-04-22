"""
Tonztoon Komik — Base Comic Scraper

Abstract Base Class yang harus diimplementasikan oleh setiap source scraper.
Scraper menggunakan model dari `app.models` untuk database operations
dan `app.schemas` untuk validasi data hasil scraping.
"""

from abc import ABC, abstractmethod
from typing import Any

from scrapling.fetchers import DynamicFetcher, DynamicSession, Fetcher, StealthyFetcher


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
        self.dynamic_session_factory = DynamicSession

    async def close(self) -> None:
        """
        Hook cleanup opsional untuk scraper yang memakai browser/session persisten.

        Default: no-op.
        """
        return None

    async def get_comic_metadata_patch(
        self,
        url: str,
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        """
        Ambil patch metadata ringan untuk comic existing tanpa full detail sync.

        Default: return kosong. Source yang punya endpoint API/detail ringan
        bisa override method ini agar pipeline dapat meng-update kolom tertentu
        seperti `total_view`, `rating`, atau `status` tanpa ikut sync chapter.
        """
        return {}

    async def get_source_comic_count(self) -> int | None:
        """
        Ambil total komik yang tersedia langsung pada source asal.

        Default: tidak tersedia. Source individual boleh override dengan
        implementasi yang memakai API/pagination mereka masing-masing.
        """
        return None

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
    async def get_comic_list(self, page: int = 1) -> list[dict[str, Any]]:
        """
        Ambil daftar komik keseluruhan (direktori/list).

        Args:
            page: Nomor halaman.

        Returns:
            List of dict berisi data komik.
        """
        pass
