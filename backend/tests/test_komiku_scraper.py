import unittest
from unittest.mock import AsyncMock, patch

from scraper.sources.komiku_scraper import KomikuScraper


class KomikuScraperUnitTests(unittest.TestCase):
    def setUp(self):
        self.scraper = KomikuScraper()

    def test_url_helpers(self):
        self.assertEqual(
            self.scraper._build_latest_updates_url(1),
            "https://api.komiku.org/manga/",
        )
        self.assertEqual(
            self.scraper._build_latest_updates_url(3),
            "https://api.komiku.org/manga/page/3/",
        )
        self.assertEqual(
            self.scraper._build_popular_url(1),
            "https://api.komiku.org/other/hot/",
        )
        self.assertEqual(
            self.scraper._build_popular_url(2),
            "https://api.komiku.org/other/hot/page/2/",
        )

    def test_parse_date(self):
        dt = self.scraper._parse_date("23/11/2026")
        self.assertIsNotNone(dt)
        self.assertEqual(dt.year, 2026)
        self.assertEqual(dt.month, 11)
        self.assertEqual(dt.day, 23)
        self.assertIsNone(self.scraper._parse_date("invalid-date"))


class KomikuAsyncTests(unittest.IsolatedAsyncioTestCase):
    class FakePageResponse:
        def __init__(self, *, status=200, headers=None, body=None):
            self.status = status
            self.headers = headers or {"content-type": "text/html; charset=UTF-8"}
            self.body = body if body is not None else b"<html><body><div class='bge'>test</div></body></html>"

        def css(self, selector):
            return []

    async def test_fetch_page_uses_direct_scrapling_without_browser_on_200(self):
        scraper = KomikuScraper()
        response = self.FakePageResponse(status=200)

        with patch(
            "scraper.sources.komiku_scraper.Fetcher.get",
            return_value=response,
        ) as direct_get, patch.object(
            scraper,
            "_fetch_page_via_browser",
            new=AsyncMock(),
        ) as browser_fetch:
            page = await scraper._fetch_page("https://komiku.org/manga/sample")

        self.assertEqual(page.status, 200)
        direct_get.assert_called_once_with(
            "https://komiku.org/manga/sample",
            stealthy_headers=True,
            timeout=120_000,
        )
        browser_fetch.assert_not_awaited()

    async def test_fetch_page_falls_back_to_browser_on_403_waf(self):
        scraper = KomikuScraper()
        blocked_403 = self.FakePageResponse(
            status=403,
            headers={
                "content-type": "text/html; charset=UTF-8",
                "cf-mitigated": "challenge",
            },
            body=b"<!doctype html><title>Just a moment...</title>",
        )
        recovered_200 = self.FakePageResponse(
            status=200,
            body=b"<html><body><h1>Manga Real Content</h1></body></html>",
        )

        with patch(
            "scraper.sources.komiku_scraper.Fetcher.get",
            return_value=blocked_403,
        ) as direct_get, patch.object(
            scraper,
            "_fetch_page_via_browser",
            new=AsyncMock(return_value=recovered_200),
        ) as browser_fetch:
            page = await scraper._fetch_page("https://komiku.org/manga/sample")

        self.assertEqual(page.status, 200)
        direct_get.assert_called_once()
        browser_fetch.assert_awaited_once_with(
            "https://komiku.org/manga/sample",
            timeout_ms=120_000,
        )

    async def test_fetch_page_falls_back_on_cloudflare_challenge_body(self):
        scraper = KomikuScraper()
        challenge_response = self.FakePageResponse(
            status=200,
            headers={"content-type": "text/html"},
            body=b"<html><head><title>Attention Required! | Cloudflare</title></head><body>Please turnstile security verification</body></html>",
        )
        recovered_200 = self.FakePageResponse(status=200)

        with patch(
            "scraper.sources.komiku_scraper.Fetcher.get",
            return_value=challenge_response,
        ) as direct_get, patch.object(
            scraper,
            "_fetch_page_via_browser",
            new=AsyncMock(return_value=recovered_200),
        ) as browser_fetch:
            page = await scraper._fetch_page("https://api.komiku.org/manga/")

        self.assertEqual(page.status, 200)
        direct_get.assert_called_once()
        browser_fetch.assert_awaited_once()

    async def test_fetch_page_falls_back_on_timeout(self):
        scraper = KomikuScraper()
        recovered_200 = self.FakePageResponse(status=200)

        with patch(
            "scraper.sources.komiku_scraper.Fetcher.get",
            side_effect=TimeoutError("Request timed out"),
        ) as direct_get, patch.object(
            scraper,
            "_fetch_page_via_browser",
            new=AsyncMock(return_value=recovered_200),
        ) as browser_fetch:
            page = await scraper._fetch_page("https://komiku.org/daftar-komik/")

        self.assertEqual(page.status, 200)
        direct_get.assert_called_once()
        browser_fetch.assert_awaited_once()

    async def test_fetch_page_raises_on_non_timeout_exception(self):
        scraper = KomikuScraper()

        with patch(
            "scraper.sources.komiku_scraper.Fetcher.get",
            side_effect=ValueError("Invalid URL configuration"),
        ), patch.object(
            scraper,
            "_fetch_page_via_browser",
            new=AsyncMock(),
        ) as browser_fetch:
            with self.assertRaises(RuntimeError) as ctx:
                await scraper._fetch_page("https://komiku.org/bad-url")

        self.assertIn("Direct fetch Komiku gagal", str(ctx.exception))
        browser_fetch.assert_not_awaited()

    async def test_close_calls_close_shared_session(self):
        scraper = KomikuScraper()
        with patch.object(
            KomikuScraper,
            "close_shared_session",
            new=AsyncMock(),
        ) as close_session:
            await scraper.close()

        close_session.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
