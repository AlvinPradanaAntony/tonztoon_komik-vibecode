import types
import unittest
from unittest.mock import AsyncMock, patch

from app.services import chapter_service


class ChapterTransactionScopeTests(unittest.IsolatedAsyncioTestCase):
    async def test_fetch_releases_read_transaction_before_scrape(self):
        chapter = types.SimpleNamespace(
            id=10,
            chapter_number=3,
            source_url="https://source.example/chapter-3",
        )
        db = types.SimpleNamespace(
            execute=AsyncMock(),
            commit=AsyncMock(),
            rollback=AsyncMock(),
        )
        images = [
            {
                "page": 1,
                "url": "https://cdn.example/page-1.jpg",
                "width": 720,
                "height": 1200,
            }
        ]

        async def scrape(url):
            self.assertEqual(url, chapter.source_url)
            self.assertEqual(db.rollback.await_count, 1)
            self.assertEqual(db.execute.await_count, 0)
            return images

        scraper = types.SimpleNamespace(get_chapter_images=AsyncMock(side_effect=scrape))
        with (
            patch.object(chapter_service, "_get_scraper_for_source", return_value=scraper),
            patch.object(
                chapter_service,
                "enrich_chapter_image_dimensions",
                AsyncMock(return_value=images),
            ),
        ):
            result = await chapter_service.fetch_and_save_chapter_images(
                chapter=chapter,
                source_name="example",
                timeout_seconds=1,
                db=db,
            )

        self.assertTrue(result)
        db.execute.assert_awaited_once()
        db.commit.assert_awaited_once()

    async def test_dimension_probe_releases_read_transaction_before_network_io(self):
        chapter = types.SimpleNamespace(
            id=11,
            images=[
                {
                    "page": 1,
                    "url": "https://cdn.example/page-1.jpg",
                }
            ],
        )
        db = types.SimpleNamespace(
            execute=AsyncMock(),
            commit=AsyncMock(),
            rollback=AsyncMock(),
        )
        enriched = [
            {
                "page": 1,
                "url": "https://cdn.example/page-1.jpg",
                "width": 720,
                "height": 1200,
            }
        ]

        async def enrich(images):
            self.assertEqual(db.rollback.await_count, 1)
            self.assertEqual(db.execute.await_count, 0)
            return enriched

        with patch.object(
            chapter_service,
            "enrich_chapter_image_dimensions",
            AsyncMock(side_effect=enrich),
        ):
            result = await chapter_service._ensure_chapter_image_dimensions(
                db,
                chapter,
            )

        self.assertIs(result, chapter)
        self.assertEqual(chapter.images, enriched)
        db.execute.assert_awaited_once()
        db.commit.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
