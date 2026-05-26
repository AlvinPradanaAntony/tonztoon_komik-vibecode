"""
Registry scraper sources yang tersedia di backend.

`enabled=True` berarti source aktif dan boleh masuk pipeline DB/catalog utama.
`enabled=False` berarti source backup: tetap bisa dihitung di `source_stats`
dan dipakai backfill live-scrape, tetapi tidak muncul di pipeline ingest.
"""

from typing import Any

from scraper.base_scraper import BaseComicScraper
from scraper.sources.komikcast_scraper import KomikcastScraper
from scraper.sources.kiryuu_scraper import KiryuuScraper
from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper
from scraper.sources.komiku_scraper import KomikuScraper
from scraper.sources.shinigami_scraper import ShinigamiScraper

SCRAPER_FACTORIES: dict[str, type[BaseComicScraper]] = {
    "komiku": KomikuScraper,
    "komiku_asia": KomikuAsiaScraper,
    "komikcast": KomikcastScraper,
    "shinigami": ShinigamiScraper,
    "kiryuu": KiryuuScraper,
}

SOURCE_ENABLED: dict[str, bool] = {
    "komiku": True,
    "komiku_asia": True,
    "komikcast": True,
    "shinigami": True,
    "kiryuu": False,
}

SOURCE_LABELS: dict[str, str] = {
    "komiku": "Komiku",
    "komiku_asia": "Komiku Asia",
    "komikcast": "Komikcast",
    "shinigami": "Shinigami",
    "kiryuu": "Kiryuu",
}


def get_supported_source_names() -> list[str]:
    """Daftar source aktif yang didukung backend."""
    return [
        source_name
        for source_name in SCRAPER_FACTORIES
        if SOURCE_ENABLED.get(source_name, False)
    ]


def get_backup_source_names() -> list[str]:
    """Daftar source backup yang tidak masuk pipeline default."""
    return [
        source_name
        for source_name in SCRAPER_FACTORIES
        if not SOURCE_ENABLED.get(source_name, False)
    ]


def get_observable_source_names() -> list[str]:
    """Daftar source yang boleh muncul di source_stats/count endpoint."""
    return list(SCRAPER_FACTORIES.keys())


def get_source_metadata(source_name: str, *, require_enabled: bool = True) -> dict[str, Any]:
    """Metadata publik satu source."""
    normalized = source_name.lower()
    factory = SCRAPER_FACTORIES.get(normalized)
    enabled = SOURCE_ENABLED.get(normalized, False)
    if factory is None or (require_enabled and not enabled):
        supported = ", ".join(get_supported_source_names())
        raise ValueError(
            f"Source scraper tidak aktif: {source_name}. "
            f"Gunakan salah satu dari: {supported}"
        )

    return {
        "id": normalized,
        "label": SOURCE_LABELS.get(normalized, normalized.replace("_", " ").title()),
        "base_url": factory.BASE_URL,
        "enabled": enabled,
    }


def get_backup_source_metadata(source_name: str) -> dict[str, Any]:
    """Metadata internal untuk source backup."""
    normalized = source_name.lower()
    factory = SCRAPER_FACTORIES.get(normalized)
    enabled = SOURCE_ENABLED.get(normalized, False)
    if factory is None or enabled:
        supported = ", ".join(get_backup_source_names())
        raise ValueError(
            f"Source backup tidak didukung: {source_name}. "
            f"Gunakan salah satu dari: {supported}"
        )

    return {
        "id": normalized,
        "label": SOURCE_LABELS.get(normalized, normalized.replace("_", " ").title()),
        "base_url": factory.BASE_URL,
        "enabled": False,
    }


def get_all_source_metadata() -> list[dict[str, Any]]:
    """Metadata publik semua source yang observable/countable."""
    return [
        get_source_metadata(source_name, require_enabled=False)
        for source_name in get_observable_source_names()
    ]


def create_scraper(source_name: str) -> BaseComicScraper:
    """Buat instance scraper berdasarkan source internal name."""
    normalized = get_source_metadata(source_name)["id"]
    return SCRAPER_FACTORIES[normalized]()


def create_backup_scraper(source_name: str) -> BaseComicScraper:
    """Buat instance scraper backup berdasarkan source internal name."""
    normalized = get_backup_source_metadata(source_name)["id"]
    return SCRAPER_FACTORIES[normalized]()


def create_observable_scraper(source_name: str) -> BaseComicScraper:
    """Buat scraper untuk kebutuhan observability/count source."""
    normalized = source_name.lower()
    if normalized in SCRAPER_FACTORIES:
        return SCRAPER_FACTORIES[normalized]()

    supported = ", ".join(get_observable_source_names())
    raise ValueError(
        f"Source scraper tidak didukung untuk observability: {source_name}. "
        f"Gunakan salah satu dari: {supported}"
    )


def create_default_scrapers() -> list[BaseComicScraper]:
    """Instansiasi semua scraper yang aktif di pipeline default."""
    return [SCRAPER_FACTORIES[source_name]() for source_name in get_supported_source_names()]
