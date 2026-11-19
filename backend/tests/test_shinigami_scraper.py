import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from app.services.image_service import (
    get_proxy_headers,
    validate_proxy_image_url,
)
from scraper.sources.registry import (
    create_scraper,
    get_source_metadata,
    get_supported_source_names,
)
from scraper.sources.shinigami_api import (
    SHINIGAMI_API_BASE_URL,
    SHINIGAMI_BASE_URL,
    build_shinigami_api_headers,
    build_shinigami_chapter_detail_url,
    build_shinigami_chapter_list_url,
    build_shinigami_chapter_url,
    build_shinigami_manga_detail_url,
    build_shinigami_manga_list_params,
    build_shinigami_manga_list_url,
    build_shinigami_series_url,
    normalize_shinigami_web_url,
    parse_shinigami_has_next,
    parse_shinigami_manga_list_payload,
    parse_shinigami_next_cursor,
    parse_shinigami_total_count,
)
from scraper.sources.shinigami_scraper import ShinigamiScraper


class ShinigamiApiHelperTests(unittest.TestCase):
    def test_base_urls_updated_to_new_host(self):
        self.assertEqual(SHINIGAMI_BASE_URL, "https://s1.shinigami.mx")
        self.assertEqual(SHINIGAMI_API_BASE_URL, "https://api.shinigami.io/v1")

    def test_normalize_shinigami_web_url(self):
        self.assertEqual(
            normalize_shinigami_web_url("https://e.shinigami.asia/series/abc-123/"),
            "https://s1.shinigami.mx/series/abc-123/",
        )
        self.assertEqual(
            normalize_shinigami_web_url("/chapter/def-456"),
            "https://s1.shinigami.mx/chapter/def-456",
        )
        self.assertEqual(normalize_shinigami_web_url(None), "https://s1.shinigami.mx/")

    def test_build_shinigami_api_headers_normalizes_legacy_referer(self):
        headers = build_shinigami_api_headers("https://e.shinigami.asia/series/abc-123/")
        self.assertEqual(headers["origin"], "https://s1.shinigami.mx")
        self.assertEqual(headers["referer"], "https://s1.shinigami.mx/series/abc-123/")
        self.assertEqual(headers["accept"], "application/json")

    def test_manga_list_params_use_offset_limit_and_sort_mapping(self):
        latest_params = build_shinigami_manga_list_params(page=2, page_size=24, sort="latest")
        self.assertEqual(latest_params["offset"], 24)
        self.assertEqual(latest_params["limit"], 24)
        self.assertEqual(latest_params["sort"], "latest")
        self.assertEqual(latest_params["sort_order"], "desc")
        self.assertNotIn("page", latest_params)
        self.assertNotIn("page_size", latest_params)

        popular_params = build_shinigami_manga_list_params(page=1, sort="popular")
        self.assertEqual(popular_params["sort"], "popularity")
        self.assertEqual(popular_params["sort_order"], "desc")

        az_params = build_shinigami_manga_list_params(page=1, sort="az")
        self.assertEqual(az_params["sort"], "title")
        self.assertEqual(az_params["sort_order"], "asc")

    def test_url_builders(self):
        list_url = build_shinigami_manga_list_url(page=3, page_size=24, query="solo")
        self.assertIn("https://api.shinigami.io/v1/manga/list?", list_url)
        self.assertIn("offset=48", list_url)
        self.assertIn("limit=24", list_url)
        self.assertIn("q=solo", list_url)

        detail_url = build_shinigami_manga_detail_url("manga-uuid")
        self.assertEqual(detail_url, "https://api.shinigami.io/v1/manga/detail/manga-uuid")

        chapter_list_url = build_shinigami_chapter_list_url("manga-uuid", limit=100, cursor="cur-1")
        self.assertIn("https://api.shinigami.io/v1/chapter/manga-uuid/list?", chapter_list_url)
        self.assertIn("limit=100", chapter_list_url)
        self.assertIn("cursor=cur-1", chapter_list_url)

        chapter_detail_url = build_shinigami_chapter_detail_url("chap-uuid")
        self.assertEqual(chapter_detail_url, "https://api.shinigami.io/v1/chapter/detail/chap-uuid")

        self.assertEqual(
            build_shinigami_series_url("manga-uuid"),
            "https://s1.shinigami.mx/series/manga-uuid/",
        )
        self.assertEqual(
            build_shinigami_chapter_url("chap-uuid"),
            "https://s1.shinigami.mx/chapter/chap-uuid",
        )

    def test_parse_meta_and_facets(self):
        payload = {
            "retcode": 0,
            "meta": {"has_next": True, "limit": 24, "offset": 0, "next_cursor": "eyJzIjo0Mn0"},
            "facet": {
                "taxonomy.Format.name": {"Manga": 178, "Manhua": 265, "Manhwa": 1138},
                "taxonomy.Type.name": {"Mirror": 1400, "Project": 179},
            },
            "data": [
                {
                    "manga_id": "bdfa64ce-9e83-4118-a472-7ea8e12bca7f",
                    "title": "Sample Manhwa",
                    "cover_image_url": "https://cdn.shinigami.gg/assets/cover/banner.png",
                    "cover_portrait_url": "https://cdn.shinigami.gg/assets/cover/portrait.jpg",
                    "latest_chapter_number": 46,
                    "latest_chapter_time": "2026-11-18T09:16:31Z",
                }
            ],
        }
        self.assertTrue(parse_shinigami_has_next(payload))
        self.assertEqual(parse_shinigami_next_cursor(payload), "eyJzIjo0Mn0")
        self.assertEqual(parse_shinigami_total_count(payload), 1581)

        items, has_next = parse_shinigami_manga_list_payload(payload)
        self.assertTrue(has_next)
        self.assertEqual(len(items), 1)
        self.assertEqual(
            items[0]["source_url"],
            "https://s1.shinigami.mx/series/bdfa64ce-9e83-4118-a472-7ea8e12bca7f/",
        )
        self.assertEqual(
            items[0]["cover_image_url"],
            "https://cdn.shinigami.gg/assets/cover/portrait.jpg",
        )
        self.assertEqual(items[0]["latest_chapter"], "CH.46")


class ShinigamiScraperRegistryTests(unittest.TestCase):
    def test_shinigami_in_supported_sources(self):
        self.assertIn("shinigami", get_supported_source_names())

    def test_create_scraper_shinigami(self):
        scraper = create_scraper("shinigami")
        self.assertIsInstance(scraper, ShinigamiScraper)
        self.assertEqual(scraper.SOURCE_NAME, "shinigami")
        self.assertEqual(scraper.BASE_URL, "https://s1.shinigami.mx")

    def test_source_metadata(self):
        meta = get_source_metadata("shinigami")
        self.assertEqual(meta["id"], "shinigami")
        self.assertEqual(meta["base_url"], "https://s1.shinigami.mx")
        self.assertTrue(meta["enabled"])


class ShinigamiImageProxyTests(unittest.TestCase):
    def test_new_shinigami_hosts_allowed_and_referer(self):
        cover_url = "https://cdn.shinigami.gg/assets/cover/banner_1.png"
        self.assertEqual(validate_proxy_image_url(cover_url), cover_url)
        self.assertEqual(get_proxy_headers(cover_url).get("Referer"), "https://s1.shinigami.mx/")

        web_asset = "https://s1.shinigami.mx/assets/favicon.png"
        self.assertEqual(validate_proxy_image_url(web_asset), web_asset)
        self.assertEqual(get_proxy_headers(web_asset).get("Referer"), "https://s1.shinigami.mx/")


class ShinigamiScraperFlowTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.scraper = ShinigamiScraper()

    async def test_get_source_comic_count_from_facets(self):
        mock_payload = {
            "retcode": 0,
            "meta": {"has_next": True, "limit": 1, "offset": 0},
            "facet": {"taxonomy.Format.name": {"Manga": 100, "Manhwa": 500}},
            "data": [],
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)) as mock_fetch:
            count = await self.scraper.get_source_comic_count()
            self.assertEqual(count, 600)
            self.assertIn("limit=1", mock_fetch.call_args.args[0])

    async def test_get_source_comic_count_returns_none_on_error(self):
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(side_effect=RuntimeError("boom"))):
            self.assertIsNone(await self.scraper.get_source_comic_count())

    async def test_get_latest_and_popular_use_expected_sort(self):
        mock_payload = {
            "retcode": 0,
            "meta": {"has_next": True, "limit": 24, "offset": 24},
            "data": [
                {
                    "manga_id": "05bbcbc4-56a6-47e6-ac36-1d482339a322",
                    "title": "Eleceed",
                    "cover_image_url": "https://cdn.shinigami.gg/assets/image/cover.jpg",
                    "latest_chapter_number": 427,
                    "latest_chapter_time": "2026-11-18T01:33:13Z",
                }
            ],
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)) as mock_fetch:
            latest = await self.scraper.get_latest_updates(page=2)
            self.assertEqual(len(latest), 1)
            self.assertIn("offset=24", mock_fetch.call_args_list[0].args[0])
            self.assertIn("sort=latest", mock_fetch.call_args_list[0].args[0])

            popular = await self.scraper.get_popular(page=1)
            self.assertEqual(len(popular), 1)
            self.assertIn("sort=popularity", mock_fetch.call_args_list[1].args[0])

    async def test_search(self):
        mock_payload = {
            "retcode": 0,
            "meta": {"has_next": False, "limit": 24, "offset": 0},
            "data": [
                {
                    "manga_id": "5c612573-fe38-42df-8618-dc3de1c9d04a",
                    "title": "Solo Leveling",
                    "cover_image_url": "https://cdn.shinigami.gg/assets/cover/solo.png",
                    "latest_chapter_number": 179,
                }
            ],
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=mock_payload)) as mock_fetch:
            items = await self.scraper.search("solo", page=1)
            self.assertEqual(len(items), 1)
            self.assertEqual(items[0]["title"], "Solo Leveling")
            self.assertIn("q=solo", mock_fetch.call_args.args[0])

        self.assertEqual(await self.scraper.search("   "), [])

    async def test_get_comic_detail_with_cursor_chapter_pagination(self):
        manga_id = "bdfa64ce-9e83-4118-a472-7ea8e12bca7f"
        detail_payload = {
            "retcode": 0,
            "data": {
                "manga_id": manga_id,
                "title": "Sample Series",
                "alternative_title": "Alt Sample",
                "cover_image_url": "https://cdn.shinigami.gg/assets/cover/banner.png",
                "cover_portrait_url": "https://cdn.shinigami.gg/assets/cover/portrait.png",
                "status": 1,
                "user_rate": 8.8,
                "view_count": 12345,
                "description": "Synopsis text",
                "taxonomy": {
                    "Genre": [{"name": "Action"}, {"name": "Fantasy"}],
                    "Author": [{"name": "Author A"}],
                    "Artist": [{"name": "Artist B"}],
                    "Format": [{"name": "Manhwa"}],
                    "Type": [{"name": "Project"}],
                },
            },
        }
        ch_page_1 = {
            "retcode": 0,
            "meta": {"has_next": True, "next_cursor": "cursor-2"},
            "data": [
                {
                    "chapter_id": "chap-2",
                    "chapter_number": 2,
                    "chapter_title": "",
                    "release_date": "2026-11-18T09:16:31Z",
                }
            ],
        }
        ch_page_2 = {
            "retcode": 0,
            "meta": {"has_next": False, "next_cursor": None},
            "data": [
                {
                    "chapter_id": "chap-1",
                    "chapter_number": 1,
                    "chapter_title": "Prologue",
                    "release_date": "2026-11-17T09:16:31Z",
                }
            ],
        }

        called_urls: list[str] = []

        async def fake_fetch(url: str, referer_url: str | None = None):
            called_urls.append(url)
            if "/manga/detail/" in url:
                return detail_payload
            if "cursor=cursor-2" in url:
                return ch_page_2
            return ch_page_1

        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(side_effect=fake_fetch)):
            # Accepts legacy URL and normalizes canonical source_url to s1.shinigami.mx
            detail = await self.scraper.get_comic_detail(
                f"https://e.shinigami.asia/series/{manga_id}/"
            )

        self.assertEqual(detail["source_url"], f"https://s1.shinigami.mx/series/{manga_id}/")
        self.assertEqual(detail["cover_image_url"], "https://cdn.shinigami.gg/assets/cover/portrait.png")
        self.assertEqual(detail["type"], "manhwa")
        self.assertEqual(detail["status"], "ongoing")
        self.assertEqual(detail["genres"], ["Action", "Fantasy"])
        self.assertEqual(len(detail["chapters"]), 2)
        self.assertEqual(detail["chapters"][0]["chapter_number"], 2.0)
        self.assertEqual(detail["chapters"][0]["source_url"], "https://s1.shinigami.mx/chapter/chap-2")
        self.assertEqual(detail["chapters"][1]["chapter_number"], 1.0)
        self.assertTrue(any("cursor=cursor-2" in u for u in called_urls))

    async def test_get_chapter_images(self):
        payload = {
            "retcode": 0,
            "data": {
                "base_url": "https://cdn.shinigami.gg",
                "chapter": {
                    "path": "/chapter/manga_1/chapter_2/",
                    "data": ["page-01.jpg", "page-02.jpg"],
                },
            },
        }
        with patch.object(self.scraper, "_fetch_api_json", new=AsyncMock(return_value=payload)):
            images = await self.scraper.get_chapter_images(
                "https://s1.shinigami.mx/chapter/32eba7cf-6444-42fb-af0c-e800bbfa4340"
            )
            self.assertEqual(
                images,
                [
                    {"page": 1, "url": "https://cdn.shinigami.gg/chapter/manga_1/chapter_2/page-01.jpg"},
                    {"page": 2, "url": "https://cdn.shinigami.gg/chapter/manga_1/chapter_2/page-02.jpg"},
                ],
            )

    async def test_fetch_api_json_uses_direct_scrapling_without_browser_on_success(self):
        direct_resp = SimpleNamespace(
            status=200,
            headers={"content-type": "application/json"},
            body=b'{"retcode":0,"data":[]}',
            json=lambda: {"retcode": 0, "data": [], "meta": {"has_next": False}},
        )

        with (
            patch(
                "scraper.sources.shinigami_scraper.Fetcher.get",
                return_value=direct_resp,
            ) as direct_get,
            patch.object(
                self.scraper,
                "_fetch_api_json_via_browser",
                new=AsyncMock(),
            ) as browser_fetch,
        ):
            result = await self.scraper._fetch_api_json(
                "https://api.shinigami.io/v1/manga/list?offset=0&limit=1"
            )

        self.assertEqual(result["retcode"], 0)
        direct_get.assert_called_once()
        browser_fetch.assert_not_awaited()

    async def test_fetch_api_json_falls_back_to_browser_on_403_cloudflare(self):
        blocked_resp = SimpleNamespace(
            status=403,
            headers={
                "content-type": "text/html; charset=UTF-8",
                "cf-mitigated": "challenge",
            },
            body=b"<!doctype html><title>Just a moment...</title>",
            json=lambda: {"retcode": -1},
        )

        with (
            patch(
                "scraper.sources.shinigami_scraper.Fetcher.get",
                return_value=blocked_resp,
            ) as direct_get,
            patch.object(
                self.scraper,
                "_fetch_api_json_via_browser",
                new=AsyncMock(return_value={"retcode": 0, "data": [], "meta": {"has_next": False}}),
            ) as browser_fetch,
        ):
            result = await self.scraper._fetch_api_json(
                "https://api.shinigami.io/v1/manga/list?offset=0&limit=1"
            )

        self.assertEqual(result["retcode"], 0)
        direct_get.assert_called_once()
        browser_fetch.assert_awaited_once()

    async def test_fetch_api_json_falls_back_to_browser_on_5xx_or_timeout(self):
        server_error_resp = SimpleNamespace(
            status=520,
            headers={"content-type": "text/plain"},
            body=b"upstream error",
            json=lambda: {},
        )

        with (
            patch(
                "scraper.sources.shinigami_scraper.Fetcher.get",
                return_value=server_error_resp,
            ),
            patch.object(
                self.scraper,
                "_fetch_api_json_via_browser",
                new=AsyncMock(return_value={"retcode": 0, "data": []}),
            ) as browser_fetch,
        ):
            result = await self.scraper._fetch_api_json(
                "https://api.shinigami.io/v1/manga/list?offset=0&limit=1"
            )
            self.assertEqual(result["retcode"], 0)
            browser_fetch.assert_awaited_once()

        with (
            patch(
                "scraper.sources.shinigami_scraper.Fetcher.get",
                side_effect=TimeoutError("read timed out"),
            ),
            patch.object(
                self.scraper,
                "_fetch_api_json_via_browser",
                new=AsyncMock(return_value={"retcode": 0, "data": []}),
            ) as browser_fetch_timeout,
        ):
            result = await self.scraper._fetch_api_json(
                "https://api.shinigami.io/v1/manga/list?offset=0&limit=1"
            )
            self.assertEqual(result["retcode"], 0)
            browser_fetch_timeout.assert_awaited_once()

    async def test_fetch_api_json_does_not_fallback_on_non_timeout_error(self):
        with (
            patch(
                "scraper.sources.shinigami_scraper.Fetcher.get",
                side_effect=ValueError("invalid url"),
            ),
            patch.object(
                self.scraper,
                "_fetch_api_json_via_browser",
                new=AsyncMock(),
            ) as browser_fetch,
        ):
            with self.assertRaises(RuntimeError):
                await self.scraper._fetch_api_json(
                    "https://api.shinigami.io/v1/manga/list?offset=0&limit=1"
                )
            browser_fetch.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
