"""
Registry scraper sources yang tersedia di backend.
"""

from typing import Any

from scraper.base_scraper import BaseComicScraper
from scraper.sources.komikcast_scraper import KomikcastScraper
from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper
from scraper.sources.komiku_scraper import KomikuScraper
from scraper.sources.shinigami_scraper import ShinigamiScraper

SCRAPER_FACTORIES: dict[str, type[BaseComicScraper]] = {
    "komiku": KomikuScraper,
    "komiku_asia": KomikuAsiaScraper,
    "komikcast": KomikcastScraper,
    "shinigami": ShinigamiScraper,
}

SOURCE_LABELS: dict[str, str] = {
    "komiku": "Komiku",
    "komiku_asia": "Komiku Asia",
    "komikcast": "Komikcast",
    "shinigami": "Shinigami",
}


def get_supported_source_names() -> list[str]:
    """Daftar source internal yang didukung backend."""
    return list(SCRAPER_FACTORIES.keys())


def get_source_metadata(source_name: str) -> dict[str, Any]:
    """Metadata publik satu source aktif."""
    normalized = source_name.lower()
    factory = SCRAPER_FACTORIES.get(normalized)
    if factory is None:
        supported = ", ".join(get_supported_source_names())
        raise ValueError(
            f"Source scraper tidak didukung: {source_name}. "
            f"Gunakan salah satu dari: {supported}"
        )

    return {
        "id": normalized,
        "label": SOURCE_LABELS.get(normalized, normalized.replace("_", " ").title()),
        "base_url": factory.BASE_URL,
        "enabled": True,
    }


def get_all_source_metadata() -> list[dict[str, Any]]:
    """Metadata publik semua source aktif."""
    return [get_source_metadata(source_name) for source_name in get_supported_source_names()]


def create_scraper(source_name: str) -> BaseComicScraper:
    """Buat instance scraper berdasarkan source internal name."""
    normalized = get_source_metadata(source_name)["id"]
    return SCRAPER_FACTORIES[normalized]()


def create_default_scrapers() -> list[BaseComicScraper]:
    """Instansiasi semua scraper yang aktif di pipeline default."""
    return [factory() for factory in SCRAPER_FACTORIES.values()]
