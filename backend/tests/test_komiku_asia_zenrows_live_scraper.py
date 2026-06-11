import unittest

import httpx

from app.config import settings
from app.services import chapter_service
from app.services.komiku_asia_zenrows_live_scraper import (
    KomikuAsiaZenRowsChapterImageScraper,
    KomikuAsiaZenRowsError,
    parse_komiku_asia_chapter_images,
)


class FakeZenRowsClient:
    def __init__(self, response):
        self.response = response
        self.calls = []

    async def get(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return self.response


class KomikuAsiaZenRowsLiveScraperTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.original_provider = settings.KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER
        self.original_key = settings.ZENROWS_API_KEY
        self.original_wait_ms = settings.KOMIKU_ASIA_ZENROWS_WAIT_MS

    def tearDown(self):
        settings.KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER = self.original_provider
        settings.ZENROWS_API_KEY = self.original_key
        settings.KOMIKU_ASIA_ZENROWS_WAIT_MS = self.original_wait_ms

    def test_parse_chapter_images_uses_data_index_and_srcset(self):
        html = """
        <main>
          <img class="ts-main-image" data-index="0" data-src="/img/page-1.webp">
          <img class="ts-main-image" data-index="bad" srcset="https://cdnkomiku.xyz/p2.webp 800w, https://cdnkomiku.xyz/p2-small.webp 400w">
          <img class="ts-main-image" src="https://cdnkomiku.xyz/p3.webp">
        </main>
        """

        images = parse_komiku_asia_chapter_images(html, base_url="https://01.komiku.asia")

        self.assertEqual(
            images,
            [
                {"page": 1, "url": "https://01.komiku.asia/img/page-1.webp"},
                {"page": 2, "url": "https://cdnkomiku.xyz/p2.webp"},
                {"page": 3, "url": "https://cdnkomiku.xyz/p3.webp"},
            ],
        )

    async def test_fetch_chapter_html_calls_zenrows_with_cloudflare_params(self):
        client = FakeZenRowsClient(
            httpx.Response(
                200,
                text='<img class="ts-main-image" data-index="0" src="https://cdnkomiku.xyz/p1.webp">',
            )
        )
        scraper = KomikuAsiaZenRowsChapterImageScraper(
            api_key="secret",
            api_base_url="https://api.zenrows.com/v1/",
            wait_ms=2500,
            client=client,
        )

        images = await scraper.get_chapter_images(
            "https://01.komiku.asia/sample-chapter-1/"
        )

        self.assertEqual(images[0]["url"], "https://cdnkomiku.xyz/p1.webp")
        url, kwargs = client.calls[0]
        self.assertEqual(url, "https://api.zenrows.com/v1/")
        self.assertEqual(kwargs["params"]["url"], "https://01.komiku.asia/sample-chapter-1/")
        self.assertEqual(kwargs["params"]["apikey"], "secret")
        self.assertEqual(kwargs["params"]["js_render"], "true")
        self.assertEqual(kwargs["params"]["premium_proxy"], "true")
        self.assertEqual(kwargs["params"]["wait_for"], ".ts-main-image")
        self.assertEqual(kwargs["params"]["wait"], "2500")

    async def test_missing_api_key_raises_clear_error(self):
        scraper = KomikuAsiaZenRowsChapterImageScraper(api_key="")

        with self.assertRaises(KomikuAsiaZenRowsError):
            await scraper.fetch_chapter_html("https://01.komiku.asia/sample/")

    def test_auto_provider_uses_zenrows_when_key_exists(self):
        settings.KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER = "auto"
        settings.ZENROWS_API_KEY = "secret"

        scraper = chapter_service._get_scraper_for_source("komiku_asia")

        self.assertIsInstance(scraper, KomikuAsiaZenRowsChapterImageScraper)


if __name__ == "__main__":
    unittest.main()
