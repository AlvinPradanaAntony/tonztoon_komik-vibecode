import unittest
from unittest.mock import AsyncMock, patch

from app.services.image_service import (
    get_proxy_headers,
    validate_proxy_image_url,
)
from scraper.sources.registry import (
    create_scraper,
    get_all_source_metadata,
    get_source_metadata,
    get_supported_source_names,
)
from scraper.sources.voratoon_api import (
    VORATOON_API_BASE_URL,
    VORATOON_BASE_URL,
    build_voratoon_api_headers,
    build_voratoon_chapter_detail_url,
    build_voratoon_popular_url,
    build_voratoon_series_chapters_url,
    build_voratoon_series_detail_url,
    build_voratoon_series_index_url,
    coalesce_voratoon_total_view,
    extract_voratoon_chapter_identity,
    extract_voratoon_series_slug,
    parse_voratoon_iso_datetime,
)
from scraper.sources.voratoon_scraper import VoratoonScraper


class VoratoonApiHelperTests(unittest.TestCase):
    def test_extract_series_slug(self):
        url = "https://v1.voratoon.com/series/gomi-ika-da-to-tsuihou-sareta-shiyounin"
        self.assertEqual(
            extract_voratoon_series_slug(url),
            "gomi-ika-da-to-tsuihou-sareta-shiyounin",
        )

    def test_extract_chapter_identity(self):
        url = "https://v1.voratoon.com/series/demon-x-angel/chapter/135.1"
        slug, chapter_number = extract_voratoon_chapter_identity(url)
        self.assertEqual(slug, "demon-x-angel")
        self.assertEqual(chapter_number, "135.1")

    def test_parse_iso_datetime(self):
        dt = parse_voratoon_iso_datetime("2026-08-15T03:22:32.352+00:00")
        self.assertIsNotNone(dt)
        self.assertEqual(dt.year, 2026)
        self.assertEqual(dt.month, 8)
        self.assertEqual(dt.day, 15)

    def test_coalesce_total_view(self):
        total = coalesce_voratoon_total_view(
            item_data={"totalViews": None},
            item_metadata={"views": {"total": "15000"}},
            item_data_metadata={"totalViewsComputed": "18000"},
        )
        self.assertEqual(total, 15000)

    def test_url_builders(self):
        index_url = build_voratoon_series_index_url(page=2, take=24, sort="latest")
        self.assertIn("page=2", index_url)
        self.assertIn("take=24", index_url)
        self.assertIn(VORATOON_API_BASE_URL, index_url)

        popular_url = build_voratoon_popular_url(page=1, take=20)
        self.assertIn("/series/most-read", popular_url)

        detail_url = build_voratoon_series_detail_url("sample-slug")
        self.assertEqual(detail_url, f"{VORATOON_API_BASE_URL}/series/sample-slug?includeMeta=true")

        chapters_url = build_voratoon_series_chapters_url("sample-slug")
        self.assertEqual(chapters_url, f"{VORATOON_API_BASE_URL}/series/sample-slug/chapters")

        chapter_detail_url = build_voratoon_chapter_detail_url("sample-slug", "11")
        self.assertEqual(chapter_detail_url, f"{VORATOON_API_BASE_URL}/series/sample-slug/chapters/11")


class VoratoonScraperRegistryTests(unittest.TestCase):
    def test_voratoon_in_supported_sources(self):
        supported = get_supported_source_names()
        self.assertIn("voratoon", supported)

    def test_create_scraper_voratoon(self):
        scraper = create_scraper("voratoon")
        self.assertIsInstance(scraper, VoratoonScraper)
        self.assertEqual(scraper.SOURCE_NAME, "voratoon")
        self.assertEqual(scraper.BASE_URL, VORATOON_BASE_URL)

    def test_source_metadata(self):
        meta = get_source_metadata("voratoon")
        self.assertEqual(meta["id"], "voratoon")
        self.assertEqual(meta["label"], "Voratoon")
        self.assertTrue(meta["enabled"])


class VoratoonImageProxySecurityTests(unittest.TestCase):
    def test_voratoon_image_hosts_allowed(self):
        cover_url = "https://cvr.voratoon.id/prod/series/sample/cover/cover.webp"
        self.assertEqual(validate_proxy_image_url(cover_url), cover_url)

        cdn_url = "https://cdn.voratoon.com/wp-content/img/sample/001/01.jpg"
        self.assertEqual(validate_proxy_image_url(cdn_url), cdn_url)

    def test_voratoon_referer_header(self):
        headers = get_proxy_headers("https://cdn.voratoon.com/wp-content/img/sample/001/01.jpg")
        self.assertEqual(headers.get("Referer"), "https://v1.voratoon.com/")


class VoratoonScraperFlowTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.scraper = VoratoonScraper()

    async def test_get_source_comic_count(self):
        mock_payload = {"meta": {"total": 10338}}
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)):
            count = await self.scraper.get_source_comic_count()
            self.assertEqual(count, 10338)

    async def test_get_latest_updates(self):
        mock_payload = {
            "data": [
                {
                    "id": 10111,
                    "data": {
                        "slug": "sample-comic",
                        "title": "Sample Comic Title",
                        "coverImage": "https://cvr.voratoon.id/cover.webp",
                        "status": "ongoing",
                        "format": "manga",
                        "rating": "8.5",
                        "genres": [{"data": {"name": "Action"}}],
                    },
                    "dataMetadata": {"totalViewsComputed": "1500"},
                }
            ]
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)):
            items = await self.scraper.get_latest_updates(page=1)
            self.assertEqual(len(items), 1)
            self.assertEqual(items[0]["title"], "Sample Comic Title")
            self.assertEqual(items[0]["source_url"], f"{VORATOON_BASE_URL}/series/sample-comic")
            self.assertEqual(items[0]["status"], "ongoing")
            self.assertEqual(items[0]["type"], "manga")
            self.assertEqual(items[0]["rating"], 8.5)
            self.assertEqual(items[0]["genres"], ["Action"])

    async def test_get_comic_detail(self):
        mock_detail = {
            "data": {
                "id": 10111,
                "data": {
                    "slug": "sample-comic",
                    "title": "Sample Comic Title",
                    "coverImage": "https://cvr.voratoon.id/cover.webp",
                    "status": "completed",
                    "format": "manhwa",
                    "rating": "9.0",
                    "author": "Sample Author",
                    "synopsis": "Sample synopsis description",
                    "genres": [{"data": {"name": "Fantasy"}}],
                },
                "dataMetadata": {"totalViewsComputed": "2000"},
            }
        }
        mock_chapters = {
            "data": [
                {
                    "id": 420341,
                    "createdAt": "2026-08-15T03:22:32.352+00:00",
                    "data": {"index": 1, "title": "Prologue"},
                },
                {
                    "id": 420342,
                    "createdAt": "2026-08-15T04:22:32.352+00:00",
                    "data": {"index": 2, "title": "Chapter 2"},
                },
            ]
        }

        async def fake_fetch(url, referer_url=None):
            if "chapters" in url:
                return mock_chapters
            return mock_detail

        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(side_effect=fake_fetch)):
            detail = await self.scraper.get_comic_detail("https://v1.voratoon.com/series/sample-comic")
            self.assertEqual(detail["title"], "Sample Comic Title")
            self.assertEqual(detail["status"], "completed")
            self.assertEqual(detail["type"], "manhwa")
            self.assertEqual(detail["author"], "Sample Author")
            self.assertEqual(len(detail["chapters"]), 2)
            # Checked sorted desc
            self.assertEqual(detail["chapters"][0]["chapter_number"], 2.0)
            self.assertEqual(detail["chapters"][1]["chapter_number"], 1.0)

    async def test_get_chapter_images(self):
        mock_payload = {
            "data": {
                "id": 420341,
                "data": {
                    "images": [
                        "https://cdn.voratoon.com/001.jpg",
                        "https://cdn.voratoon.com/002.jpg",
                    ]
                },
            }
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)):
            images = await self.scraper.get_chapter_images(
                "https://v1.voratoon.com/series/sample-comic/chapter/1"
            )
            self.assertEqual(len(images), 2)
            self.assertEqual(images[0], {"page": 1, "url": "https://cdn.voratoon.com/001.jpg"})
            self.assertEqual(images[1], {"page": 2, "url": "https://cdn.voratoon.com/002.jpg"})

    async def test_get_comic_metadata_patch(self):
        mock_payload = {
            "data": {
                "data": {
                    "rating": 7.8,
                    "status": "ongoing",
                    "coverImage": "https://cvr.voratoon.id/new-cover.webp",
                },
                "dataMetadata": {"totalViewsComputed": 8800},
            }
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)):
            patch_data = await self.scraper.get_comic_metadata_patch(
                "https://v1.voratoon.com/series/sample-comic"
            )
            self.assertEqual(patch_data["rating"], 7.8)
            self.assertEqual(patch_data["status"], "ongoing")
            self.assertEqual(patch_data["total_view"], 8800)
            self.assertEqual(patch_data["cover_image_url"], "https://cvr.voratoon.id/new-cover.webp")


if __name__ == "__main__":
    unittest.main()
