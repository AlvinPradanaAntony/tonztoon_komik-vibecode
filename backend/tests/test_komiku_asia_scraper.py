import unittest
from unittest.mock import AsyncMock, patch

from scraper.sources.komiku_asia_api import (
    build_komiku_asia_chapter_detail_url,
    build_komiku_asia_comic_chapters_url,
    build_komiku_asia_comic_detail_url,
    build_komiku_asia_comics_url,
    build_komiku_asia_filters_url,
    build_komiku_asia_search_url,
    extract_komiku_asia_chapter_identity,
    extract_komiku_asia_slug,
)
from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper


class KomikuAsiaScraperTests(unittest.TestCase):
    def setUp(self):
        self.scraper = KomikuAsiaScraper()

    def test_api_url_helpers_extract_source_identities(self):
        self.assertEqual(
            extract_komiku_asia_chapter_identity(
                "https://01.komiku.asia/read/id/billy-bat/ch17-483359"
            ),
            ("billy-bat", 483359),
        )
        self.assertEqual(
            extract_komiku_asia_slug("https://01.komiku.asia/manga/billy-bat"),
            "billy-bat",
        )

    def test_api_url_helpers_reject_dom_or_legacy_urls(self):
        with self.assertRaises(ValueError):
            extract_komiku_asia_chapter_identity(
                "https://01.komiku.asia/read/billy-bat-17/"
            )

    def test_api_module_builds_official_endpoint_urls(self):
        self.assertEqual(
            build_komiku_asia_comics_url(
                page=3,
                sort="az",
                order="asc",
            ),
            "https://01.komiku.asia/api/v2/comics?sort=az&order=asc&page=3&perPage=20",
        )
        self.assertEqual(
            build_komiku_asia_search_url("billy"),
            "https://01.komiku.asia/api/v2/comics/search?q=billy&limit=20",
        )


class KomikuAsiaAsyncTests(unittest.IsolatedAsyncioTestCase):
    class FakeApiResponse:
        def __init__(self, payload, *, status=200, headers=None, body=None):
            self.status = status
            self.headers = headers or {"content-type": "application/json"}
            self._payload = payload
            self.body = body if body is not None else b"{}"

        def json(self):
            return self._payload

    async def test_api_fetch_uses_direct_scrapling_without_browser_on_success(self):
        scraper = KomikuAsiaScraper()
        response = self.FakeApiResponse(
            {"status": "ok"},
            body=b'{"status":"ok"}',
        )

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            return_value=response,
        ) as direct_get, patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(),
        ) as browser_fetch:
            payload = await scraper._fetch_api_json(
                "https://01.komiku.asia/api/v2/healthz"
            )

        self.assertEqual(payload, {"status": "ok"})
        direct_get.assert_called_once_with(
            "https://01.komiku.asia/api/v2/healthz",
            stealthy_headers=True,
            timeout=120_000,
        )
        browser_fetch.assert_not_awaited()

    async def test_api_fetch_falls_back_to_browser_on_cloudflare_challenge(self):
        scraper = KomikuAsiaScraper()
        response = self.FakeApiResponse(
            {"error": "challenge"},
            status=403,
            headers={
                "content-type": "text/html; charset=UTF-8",
                "cf-mitigated": "challenge",
            },
            body=b"<!doctype html><title>Just a moment...</title>",
        )

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            return_value=response,
        ) as direct_get, patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(return_value={"recovered": True}),
        ) as browser_fetch:
            payload = await scraper._fetch_api_json(
                "https://01.komiku.asia/api/v2/comics/billy-bat"
            )

        self.assertEqual(payload, {"recovered": True})
        direct_get.assert_called_once()
        browser_fetch.assert_awaited_once_with(
            "https://01.komiku.asia/api/v2/comics/billy-bat",
            timeout_ms=120_000,
        )

    async def test_api_fetch_falls_back_on_any_server_error(self):
        scraper = KomikuAsiaScraper()
        response = self.FakeApiResponse(
            {"error": "upstream"},
            status=520,
            headers={"content-type": "text/plain"},
            body=b"upstream error",
        )

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            return_value=response,
        ), patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(return_value={"recovered": True}),
        ) as browser_fetch:
            payload = await scraper._fetch_api_json(
                "https://01.komiku.asia/api/v2/comics/billy-bat"
            )

        self.assertEqual(payload, {"recovered": True})
        browser_fetch.assert_awaited_once()

    async def test_api_fetch_falls_back_on_transport_timeout(self):
        scraper = KomikuAsiaScraper()

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            side_effect=TimeoutError("read timed out"),
        ), patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(return_value={"recovered": True}),
        ) as browser_fetch:
            payload = await scraper._fetch_api_json(
                "https://01.komiku.asia/api/v2/comics/billy-bat"
            )

        self.assertEqual(payload, {"recovered": True})
        browser_fetch.assert_awaited_once()

    async def test_api_fetch_does_not_fallback_on_non_timeout_transport_error(self):
        scraper = KomikuAsiaScraper()

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            side_effect=ConnectionError("temporary connection reset"),
        ), patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(),
        ) as browser_fetch:
            with self.assertRaises(RuntimeError):
                await scraper._fetch_api_json(
                    "https://01.komiku.asia/api/v2/comics/billy-bat"
                )

        browser_fetch.assert_not_awaited()

    async def test_api_fetch_keeps_200_response_on_invalid_json_without_fallback(self):
        scraper = KomikuAsiaScraper()
        response = self.FakeApiResponse(
            None,
            headers={"content-type": "application/json"},
            body=b"not-json",
        )
        response.json = lambda: (_ for _ in ()).throw(ValueError("invalid json"))

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            return_value=response,
        ), patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(),
        ) as browser_fetch:
            with self.assertRaises(RuntimeError):
                await scraper._fetch_api_json(
                    "https://01.komiku.asia/api/v2/comics/billy-bat"
                )

        browser_fetch.assert_not_awaited()

    async def test_api_fetch_falls_back_when_200_body_is_cloudflare_challenge(self):
        scraper = KomikuAsiaScraper()
        response = self.FakeApiResponse(
            {"error": "challenge"},
            headers={"content-type": "text/html; charset=UTF-8"},
            body=b"<!doctype html><title>Just a moment...</title>",
        )

        with patch(
            "scraper.sources.komiku_asia_scraper.Fetcher.get",
            return_value=response,
        ), patch.object(
            scraper,
            "_fetch_api_json_via_browser",
            new=AsyncMock(return_value={"recovered": True}),
        ) as browser_fetch:
            payload = await scraper._fetch_api_json(
                "https://01.komiku.asia/api/v2/comics/billy-bat"
            )

        self.assertEqual(payload, {"recovered": True})
        browser_fetch.assert_awaited_once()

    async def test_count_api_failure_is_not_silently_replaced_by_dom(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(side_effect=RuntimeError("API unavailable"))

        with self.assertRaises(RuntimeError):
            await scraper.get_source_comic_count()

    async def test_search_uses_first_party_search_endpoint(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            return_value=[
                {
                    "slug": "billy-bat",
                    "title": "Billy Bat",
                    "type": "Manga",
                    "latestChapter": 17,
                    "coverUrl": "https://img.example/billy.webp",
                }
            ]
        )

        results = await scraper.search_comics("billy")

        self.assertEqual(results[0]["source_url"], "https://01.komiku.asia/manga/billy-bat")
        scraper._fetch_api_json.assert_awaited_once_with(
            build_komiku_asia_search_url("billy"),
        )

    async def test_full_catalog_uses_source_az_ascending_contract(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            return_value={
                "items": [
                    {
                        "slug": "plus-99-wooden-stick",
                        "title": "+99 Wooden Stick",
                        "type": "Manhwa",
                    }
                ],
                "total": 4005,
            }
        )

        results = await scraper.get_comic_list(page=3)

        self.assertEqual(results[0]["title"], "+99 Wooden Stick")
        scraper._fetch_api_json.assert_awaited_once_with(
            build_komiku_asia_comics_url(page=3, sort="az", order="asc"),
        )

    async def test_latest_api_items_keep_latest_chapter_reader_url(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            return_value={
                "items": [
                    {
                        "comic": {
                            "slug": "billy-bat",
                            "title": "Billy Bat",
                            "latestChapter": 17,
                        },
                        "chapters": [{"n": 17, "id": 483359}],
                    }
                ]
            }
        )

        results = await scraper.get_latest_updates(page=1)

        self.assertEqual(
            results[0]["latest_chapter_url"],
            "https://01.komiku.asia/read/id/billy-bat/ch17-483359",
        )

    async def test_detail_api_uses_numeric_id_for_chapter_endpoint(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            side_effect=[
                {
                    "id": 483323,
                    "slug": "billy-bat",
                    "title": "Billy Bat",
                    "latestChapter": 17,
                },
                [{"n": 17, "id": 483359}],
            ]
        )

        result = await scraper.get_comic_detail(
            "https://01.komiku.asia/manga/billy-bat"
        )

        self.assertEqual(len(result["chapters"]), 1)
        self.assertEqual(
            scraper._fetch_api_json.await_args_list[1].args,
            (build_komiku_asia_comic_chapters_url(483323),),
        )

    async def test_detail_resolves_legacy_slug_via_official_search(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            side_effect=[
                RuntimeError(
                    "Gagal fetch halaman target: "
                    "https://01.komiku.asia/api/v2/comics/solo-leveling "
                    "(status=404)"
                ),
                [
                    {
                        "slug": "060624-solo-leveling",
                        "title": "Solo Leveling",
                    },
                    {
                        "slug": "solo-leveling-ragnarok",
                        "title": "Solo Leveling: Ragnarok",
                    },
                ],
                {
                    "id": 131401,
                    "slug": "060624-solo-leveling",
                    "title": "Solo Leveling",
                    "latestChapter": 179.6,
                },
                [{"n": 150, "id": 131550}],
            ]
        )

        result = await scraper.get_comic_detail(
            "https://01.komiku.asia/manga/solo-leveling"
        )

        self.assertEqual(result["source_url"], "https://01.komiku.asia/manga/060624-solo-leveling")
        self.assertEqual(
            result["chapters"][0]["source_url"],
            "https://01.komiku.asia/read/id/060624-solo-leveling/ch150-131550",
        )
        self.assertEqual(
            [call.args for call in scraper._fetch_api_json.await_args_list],
            [
                (build_komiku_asia_comic_detail_url("solo-leveling"),),
                (build_komiku_asia_search_url("solo leveling"),),
                (build_komiku_asia_comic_detail_url("060624-solo-leveling"),),
                (build_komiku_asia_comic_chapters_url(131401),),
            ],
        )

    async def test_detail_prefers_title_for_legacy_slug_search(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            side_effect=[
                RuntimeError(
                    "Gagal fetch halaman target: "
                    "https://01.komiku.asia/api/v2/comics/solo-leveling "
                    "(status=404)"
                ),
                [
                    {
                        "slug": "060624-solo-leveling",
                        "title": "Solo Leveling",
                    }
                ],
                {
                    "id": 131401,
                    "slug": "060624-solo-leveling",
                    "title": "Solo Leveling",
                    "latestChapter": 179.6,
                },
                [{"n": 150, "id": 131550}],
            ]
        )

        result = await scraper.get_comic_detail(
            "https://01.komiku.asia/manga/solo-leveling",
            search_title="Solo Leveling",
        )

        self.assertEqual(
            result["source_url"],
            "https://01.komiku.asia/manga/060624-solo-leveling",
        )
        self.assertEqual(
            [call.args for call in scraper._fetch_api_json.await_args_list],
            [
                (build_komiku_asia_comic_detail_url("solo-leveling"),),
                (build_komiku_asia_search_url("Solo Leveling"),),
                (build_komiku_asia_comic_detail_url("060624-solo-leveling"),),
                (build_komiku_asia_comic_chapters_url(131401),),
            ],
        )

    async def test_chapter_images_use_first_party_pages_endpoint(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            side_effect=[
                {"id": 483323, "slug": "billy-bat", "title": "Billy Bat"},
                {
                    "id": 483359,
                    "comicId": 483323,
                    "n": 17,
                    "pages": [
                        {"index": 0, "url": "https://cdnkomiku.xyz/page-1.webp"},
                        {"index": 1, "url": "https://cdnkomiku.xyz/page-2.webp"},
                    ],
                },
            ]
        )

        images = await scraper.get_chapter_images(
            "https://01.komiku.asia/read/id/billy-bat/ch17-483359"
        )

        self.assertEqual(
            images,
            [
                {"page": 1, "url": "https://cdnkomiku.xyz/page-1.webp"},
                {"page": 2, "url": "https://cdnkomiku.xyz/page-2.webp"},
            ],
        )
        self.assertEqual(
            [call.args for call in scraper._fetch_api_json.await_args_list],
            [
                (build_komiku_asia_comic_detail_url("billy-bat"),),
                (build_komiku_asia_chapter_detail_url(483323, 483359),),
            ],
        )

    async def test_catalog_filters_use_first_party_endpoint(self):
        scraper = KomikuAsiaScraper()
        scraper._fetch_api_json = AsyncMock(
            return_value={"genres": ["Action"], "statuses": ["Ongoing"]}
        )

        filters = await scraper.get_catalog_filters()

        self.assertEqual(filters, {"genres": ["Action"], "statuses": ["Ongoing"]})
        scraper._fetch_api_json.assert_awaited_once_with(build_komiku_asia_filters_url())


if __name__ == "__main__":
    unittest.main()
