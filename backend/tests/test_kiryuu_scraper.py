import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.image_service import (
    get_proxy_headers,
    validate_proxy_image_url,
)
from scraper.sources.kiryuu_api import (
    DEFAULT_KIRYUU_BASE_URL,
    build_kiryuu_advanced_search_form,
    build_kiryuu_advanced_search_url,
    build_kiryuu_chapter_list_url,
    build_kiryuu_headers,
    build_kiryuu_manga_detail_url,
    build_kiryuu_manga_list_url,
    build_kiryuu_nonce_url,
    discover_kiryuu_base_url,
    get_kiryuu_base_url,
    normalize_kiryuu_url,
    set_kiryuu_base_url,
)
from scraper.sources.kiryuu_scraper import KiryuuScraper
from scraper.sources.registry import (
    get_all_source_metadata,
    get_source_metadata,
)


class KiryuuApiHelperTests(unittest.TestCase):
    def setUp(self):
        set_kiryuu_base_url(DEFAULT_KIRYUU_BASE_URL)

    def test_default_base_url(self):
        self.assertEqual(get_kiryuu_base_url(), "https://v7.kiryuu.to")

    def test_normalize_kiryuu_url_legacy_domains(self):
        self.assertEqual(
            normalize_kiryuu_url("https://v5.kiryuu.to/manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(
            normalize_kiryuu_url("http://v5.kiryuu.to/manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(
            normalize_kiryuu_url("https://kiryuu03.com/manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(
            normalize_kiryuu_url("https://kiryuu.co/manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(
            normalize_kiryuu_url("https://kiryuu.id/manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(
            normalize_kiryuu_url("manga/solo-leveling/"),
            "https://v7.kiryuu.to/manga/solo-leveling/",
        )
        self.assertEqual(normalize_kiryuu_url(None), "https://v7.kiryuu.to/")

    def test_build_kiryuu_headers(self):
        headers = build_kiryuu_headers("https://v5.kiryuu.to/manga/sample")
        self.assertEqual(headers["Referer"], "https://v7.kiryuu.to/manga/sample")
        self.assertIn("User-Agent", headers)

    def test_build_kiryuu_endpoints(self):
        self.assertEqual(
            build_kiryuu_nonce_url(),
            "https://v7.kiryuu.to/wp-admin/admin-ajax.php?type=search_form&action=get_nonce",
        )
        self.assertEqual(
            build_kiryuu_advanced_search_url(),
            "https://v7.kiryuu.to/wp-admin/admin-ajax.php?action=advanced_search",
        )
        self.assertEqual(
            build_kiryuu_chapter_list_url("12345", page=2),
            "https://v7.kiryuu.to/wp-admin/admin-ajax.php?manga_id=12345&page=2&action=chapter_list",
        )
        self.assertIn(
            "https://v7.kiryuu.to/wp-json/wp/v2/manga?",
            build_kiryuu_manga_list_url(page=1),
        )
        self.assertIn(
            "https://v7.kiryuu.to/wp-json/wp/v2/manga?",
            build_kiryuu_manga_detail_url("sample-slug"),
        )


class KiryuuScraperTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        set_kiryuu_base_url(DEFAULT_KIRYUU_BASE_URL)

    def test_base_url_class_and_instance(self):
        # Class level
        self.assertEqual(KiryuuScraper.BASE_URL, "https://v7.kiryuu.to")
        # Instance level
        scraper = KiryuuScraper()
        self.assertEqual(scraper.BASE_URL, "https://v7.kiryuu.to")

    def test_registry_metadata_base_urls_are_strings(self):
        kiryuu_meta = get_source_metadata("kiryuu", require_enabled=False)
        self.assertIsInstance(kiryuu_meta["base_url"], str)
        self.assertEqual(kiryuu_meta["base_url"], "https://v7.kiryuu.to")

    def test_extract_series_slug(self):
        scraper = KiryuuScraper()
        self.assertEqual(
            scraper._extract_series_slug("https://v7.kiryuu.to/manga/solo-leveling/"),
            "solo-leveling",
        )
        self.assertEqual(
            scraper._extract_series_slug("https://v7.kiryuu.to/manga/solo-leveling"),
            "solo-leveling",
        )
        self.assertEqual(
            scraper._extract_series_slug("solo-leveling"),
            "solo-leveling",
        )

    def test_normalize_image_url(self):
        scraper = KiryuuScraper()
        self.assertEqual(
            scraper._normalize_image_url("http://v7.kiryuu.to/wp-content/uploads/cover.jpg"),
            "https://v7.kiryuu.to/wp-content/uploads/cover.jpg",
        )
        self.assertEqual(
            scraper._normalize_image_url("/wp-content/uploads/cover.jpg"),
            "https://v7.kiryuu.to/wp-content/uploads/cover.jpg",
        )

    def test_image_proxy_referer_mapping(self):
        headers = get_proxy_headers("https://yuucdn.com/wp-content/uploads/imgsc/1/1.jpg")
        self.assertEqual(headers["Referer"], "https://v7.kiryuu.to/")

        headers_kiryuu = get_proxy_headers("https://v7.kiryuu.to/wp-content/uploads/cover.jpg")
        self.assertEqual(headers_kiryuu["Referer"], "https://v7.kiryuu.to/")

    async def test_get_source_comic_count_parsing(self):
        scraper = KiryuuScraper()
        with patch.object(
            scraper,
            "_fetch_rest_manga_list",
            return_value=([], {"x-wp-total": "9300"}),
        ):
            count = await scraper.get_source_comic_count()
            self.assertEqual(count, 9300)

    def test_live_self_healing_domain_rotation(self):
        set_kiryuu_base_url("https://v5.kiryuu.to")
        scraper = KiryuuScraper()

        mock_page_failed = MagicMock(status=403)
        mock_page_success = MagicMock(status=200)

        with patch.object(scraper.fetcher, "get", side_effect=[mock_page_failed, mock_page_success]) as mock_get, \
             patch("scraper.sources.kiryuu_scraper.discover_kiryuu_base_url", side_effect=lambda: set_kiryuu_base_url("https://v7.kiryuu.to") or "https://v7.kiryuu.to"):
            page = scraper._fetch_get("https://v5.kiryuu.to/manga/test-comic")
            self.assertEqual(getattr(page, "status", 0), 200)
            self.assertEqual(get_kiryuu_base_url(), "https://v7.kiryuu.to")
            self.assertEqual(mock_get.call_count, 2)
            self.assertEqual(mock_get.call_args_list[1][0][0], "https://v7.kiryuu.to/manga/test-comic")


if __name__ == "__main__":
    unittest.main()
