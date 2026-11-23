import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import httpx

from scraper.sync_cover_images import (
    CoverCandidate,
    DownloadedImage,
    download_cover,
    is_storage_sync_configured,
    try_download_voratoon_cover,
    upload_comic_cover_to_storage,
)


class TestSyncCoverImages(unittest.IsolatedAsyncioTestCase):
    def test_is_storage_sync_configured(self):
        with patch("scraper.sync_cover_images.settings") as mock_settings:
            mock_settings.SUPABASE_URL = "https://example.supabase.co"
            mock_settings.SUPABASE_SERVICE_ROLE_KEY = "dummy-service-role-key"
            mock_settings.SUPABASE_COVER_BUCKET = "thumbnail-comic"

            self.assertTrue(is_storage_sync_configured())

            mock_settings.SUPABASE_URL = None
            self.assertFalse(is_storage_sync_configured())

    async def test_try_download_voratoon_cover_ignores_non_voratoon(self):
        candidate = CoverCandidate(
            id=1,
            source_name="komiku",
            slug="test-comic",
            title="Test Comic",
            cover_image_url="https://example.com/cover.jpg",
            source_url="https://example.com",
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        result = await try_download_voratoon_cover(client, candidate)
        self.assertIsNone(result)

    async def test_try_download_voratoon_cover_fetches_fresh_url_and_downloads(self):
        candidate = CoverCandidate(
            id=1,
            source_name="voratoon",
            slug="second-life",
            title="Second Life",
            cover_image_url="https://cvr.voratoon.id/expired.webp",
            source_url="https://voratoon.co/series/second-life",
        )
        client = AsyncMock(spec=httpx.AsyncClient)

        mock_scraper = AsyncMock()
        mock_scraper._fetch_api_json.return_value = {
            "data": {
                "data": {"slug": "second-life", "title": "Second Life", "cover": "https://cvr.voratoon.id/fresh.webp"}
            }
        }
        mock_scraper._parse_series_item = MagicMock(return_value={
            "title": "Second Life",
            "slug": "second-life",
            "cover_image_url": "https://cvr.voratoon.id/fresh.webp",
        })
        mock_scraper.close = AsyncMock()

        expected_download = DownloadedImage(
            content=b"fresh-image-data",
            content_type="image/webp",
            origin_url="https://cvr.voratoon.id/fresh.webp",
        )

        with patch("scraper.sources.voratoon_scraper.VoratoonScraper", return_value=mock_scraper):
            with patch("scraper.sync_cover_images.try_download_http", new_callable=AsyncMock) as mock_download:
                mock_download.return_value = expected_download
                result = await try_download_voratoon_cover(client, candidate)

                self.assertIsNotNone(result)
                self.assertEqual(result.content, b"fresh-image-data")
                self.assertEqual(result.origin_url, "https://cvr.voratoon.id/fresh.webp")
                mock_download.assert_awaited_once_with(client, "https://cvr.voratoon.id/fresh.webp")
                mock_scraper.close.assert_awaited_once()

    async def test_download_cover_falls_back_to_voratoon(self):
        candidate = CoverCandidate(
            id=1,
            source_name="voratoon",
            slug="second-life",
            title="Second Life",
            cover_image_url="https://cvr.voratoon.id/expired.webp",
            source_url="https://voratoon.co/series/second-life",
        )
        client = AsyncMock(spec=httpx.AsyncClient)

        expected_download = DownloadedImage(
            content=b"fresh-data",
            content_type="image/webp",
            origin_url="https://cvr.voratoon.id/fresh.webp",
        )

        with patch("scraper.sync_cover_images.try_download_http", new_callable=AsyncMock) as mock_http:
            # First direct HTTP download returns None (expired / 403)
            mock_http.return_value = None
            with patch("scraper.sync_cover_images.try_download_voratoon_cover", new_callable=AsyncMock) as mock_vo:
                mock_vo.return_value = expected_download
                res = await download_cover(client, candidate, max_width=600)
                self.assertEqual(res, expected_download)
                mock_vo.assert_awaited_once_with(client, candidate)

    async def test_download_cover_falls_back_to_komiku(self):
        candidate = CoverCandidate(
            id=1,
            source_name="komiku",
            slug="one-piece",
            title="One Piece",
            cover_image_url="https://cdnkomiku.xyz/cover.jpg",
            source_url="https://komiku.org/manga/one-piece",
        )
        client = AsyncMock(spec=httpx.AsyncClient)

        expected_download = DownloadedImage(
            content=b"komiku-bytes",
            content_type="image/jpeg",
            origin_url="https://cdnkomiku.xyz/cover.jpg",
        )

        with patch("scraper.sync_cover_images.try_download_http", new_callable=AsyncMock) as mock_http:
            mock_http.return_value = None
            with patch("scraper.sync_cover_images.try_download_komiku_cover", new_callable=AsyncMock) as mock_km:
                mock_km.return_value = expected_download
                res = await download_cover(client, candidate, max_width=600)
                self.assertEqual(res, expected_download)
                mock_km.assert_awaited_once_with(client, candidate, max_width=600)

    async def test_try_download_komiku_cover_via_scrapling(self):
        from scraper.sync_cover_images import try_download_komiku_cover

        candidate = CoverCandidate(
            id=1,
            source_name="komiku",
            slug="one-piece",
            title="One Piece",
            cover_image_url="https://cdnkomiku.xyz/cover.jpg",
            source_url="https://komiku.org/manga/one-piece",
        )
        client = AsyncMock(spec=httpx.AsyncClient)

        expected = DownloadedImage(
            content=b"scrapling-bytes",
            content_type="image/jpeg",
            origin_url="https://cdnkomiku.xyz/cover.jpg",
        )

        with patch("scraper.sync_cover_images.try_download_scrapling", new_callable=AsyncMock) as mock_scrapling:
            mock_scrapling.return_value = expected
            result = await try_download_komiku_cover(client, candidate, max_width=600)
            self.assertEqual(result, expected)
            mock_scrapling.assert_awaited_once_with("https://cdnkomiku.xyz/cover.jpg")

    async def test_upload_comic_cover_to_storage_success(self):
        with patch("scraper.sync_cover_images.settings") as mock_settings:
            mock_settings.SUPABASE_URL = "https://example.supabase.co"
            mock_settings.SUPABASE_SERVICE_ROLE_KEY = "dummy-key"
            mock_settings.SUPABASE_COVER_BUCKET = "thumbnail-comic"

            downloaded = DownloadedImage(
                content=b"mock-image-bytes",
                content_type="image/webp",
                origin_url="https://cvr.voratoon.id/cover.webp",
            )

            with patch("scraper.sync_cover_images.download_cover", new_callable=AsyncMock) as mock_dl:
                mock_dl.return_value = downloaded
                with patch("scraper.sync_cover_images.optimize_cover_image", return_value=b"optimized-bytes"):
                    with patch("scraper.sync_cover_images.upload_cover", new_callable=AsyncMock) as mock_up:
                        result = await upload_comic_cover_to_storage(
                            source_name="voratoon",
                            slug="test-comic",
                            cover_url="https://cvr.voratoon.id/cover.webp",
                        )
                        self.assertEqual(
                            result,
                            "https://example.supabase.co/storage/v1/object/public/thumbnail-comic/covers/voratoon/test-comic.webp",
                        )
                        mock_up.assert_awaited_once()

    async def test_main_process_comic_uses_storage_cover(self):
        with patch("scraper.utils.configure_logging"):
            from scraper.main import process_comic, ScrapeStats
        from app.models import Comic

        mock_session = AsyncMock()
        mock_result = MagicMock()
        # Existing cover is not in storage
        mock_result.scalar_one_or_none.return_value = "https://cvr.voratoon.id/old_signed.webp"
        mock_session.execute.return_value = mock_result

        mock_scraper = AsyncMock()
        mock_scraper.SOURCE_NAME = "voratoon"
        mock_scraper.get_comic_detail.return_value = {
            "title": "Solo Leveling",
            "slug": "solo-leveling",
            "source_name": "voratoon",
            "source_url": "https://voratoon.co/series/solo-leveling",
            "cover_image_url": "https://cvr.voratoon.id/fresh_signed.webp",
            "chapters": [],
        }

        stats = ScrapeStats()

        with patch("scraper.main.is_storage_sync_configured", return_value=True):
            with patch(
                "scraper.main.upload_comic_cover_to_storage",
                new_callable=AsyncMock,
                return_value="https://example.supabase.co/storage/v1/object/public/thumbnail-comic/covers/voratoon/solo-leveling.webp",
            ) as mock_upload:
                with patch("scraper.main.upsert_comic_with_feed_markers", new_callable=AsyncMock, return_value=123):
                    with patch("scraper.main.sync_comic_genres", new_callable=AsyncMock):
                        with patch("scraper.main.get_current_latest_chapter_number", new_callable=AsyncMock, return_value=None):
                            with patch("scraper.main.save_chapter_metadata", new_callable=AsyncMock, return_value=0):
                                await process_comic(
                                    mock_session,
                                    mock_scraper,
                                    {"source_url": "https://voratoon.co/series/solo-leveling", "title": "Solo Leveling"},
                                    stats,
                                    latest_feed_batch_at=None,
                                    latest_feed_page=1,
                                    latest_feed_position=1,
                                    popular_feed_batch_at=None,
                                    popular_feed_page=None,
                                    popular_feed_position=None,
                                    comic_position=1,
                                    page_total=1,
                                )
                                mock_upload.assert_awaited_once_with(
                                    source_name="voratoon",
                                    slug="solo-leveling",
                                    title="Solo Leveling",
                                    cover_url="https://cvr.voratoon.id/fresh_signed.webp",
                                    source_url="https://voratoon.co/series/solo-leveling",
                                )
                                self.assertEqual(stats.total_comics, 1)


if __name__ == "__main__":
    unittest.main()
