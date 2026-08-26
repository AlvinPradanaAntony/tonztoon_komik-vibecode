import types
import unittest
from unittest.mock import AsyncMock, patch

from app.services import chapter_service


class FakeChapterDb:
    def __init__(self):
        self.commit = AsyncMock()
        self.rollback = AsyncMock()

    async def refresh(self, chapter):
        return None

    async def execute(self, statement):
        return types.SimpleNamespace(
            one_or_none=lambda: types.SimpleNamespace(
                source_name="komiku_asia",
                slug="sample-comic",
                title="Sample Comic",
            )
        )


class ExpiringChapter:
    def __init__(self):
        self.id = 42
        self.chapter_number = 5
        self.source_url = "https://01.komiku.asia/legacy-chapter-05/"
        self.images = None
        self.expired = False

    @property
    def comic_id(self):
        if self.expired:
            raise AssertionError("expired ORM attribute was accessed after rollback")
        return 7


class KomikuAsiaChapterFallbackTests(unittest.IsolatedAsyncioTestCase):
    async def test_metadata_refresh_upserts_listing_without_images(self):
        chapter = types.SimpleNamespace(
            source_url="https://01.komiku.asia/legacy-chapter-05/",
        )
        db = FakeChapterDb()
        scraper = types.SimpleNamespace(
            get_comic_detail=AsyncMock(
                return_value={
                    "chapters": [
                        {
                            "chapter_number": 5,
                            "title": "Chapter 5",
                            "source_url": "https://01.komiku.asia/read/id/demo/ch5-99",
                            "release_date": None,
                            "images": [{"page": 1, "url": "must-not-be-saved"}],
                        }
                    ]
                }
            )
        )
        upsert = AsyncMock(return_value=1)

        with (
            patch.object(chapter_service, "_get_komiku_asia_live_scraper", return_value=scraper),
            patch("scraper.db_ops.upsert_chapter_metadata_many", upsert),
        ):
            refreshed = await chapter_service._refresh_komiku_asia_chapter_metadata(
                db,
                comic_id=9,
                comic_slug="demo",
                chapter=chapter,
            )

        self.assertTrue(refreshed)
        db.commit.assert_awaited_once()
        upsert.assert_awaited_once()
        upserted_rows = upsert.await_args.args[2]
        self.assertEqual(upserted_rows[0]["source_url"], "https://01.komiku.asia/read/id/demo/ch5-99")
        self.assertNotIn("images", upserted_rows[0])

    async def test_invalid_chapter_url_refreshes_metadata_then_retries_images(self):
        chapter = ExpiringChapter()
        db = FakeChapterDb()

        async def fail_then_retry(**kwargs):
            chapter.expired = True
            if fail_then_retry.calls == 0:
                fail_then_retry.calls += 1
                raise chapter_service.ImageFetchError("URL chapter tidak valid")
            return True

        fail_then_retry.calls = 0
        fetch = AsyncMock(
            side_effect=fail_then_retry,
        )
        refresh_metadata = AsyncMock(return_value=True)

        with (
            patch.object(chapter_service, "fetch_and_save_chapter_images", fetch),
            patch.object(
                chapter_service,
                "_refresh_komiku_asia_chapter_metadata",
                refresh_metadata,
            ),
        ):
            result = await chapter_service._ensure_chapter_images_loaded(
                db,
                chapter,
                source_name="komiku_asia",
                comic_slug="superhuman-battlefield",
            )

        self.assertIs(result, chapter)
        self.assertEqual(fetch.await_count, 2)
        refresh_metadata.assert_awaited_once_with(
            db,
            comic_id=7,
            comic_slug="superhuman-battlefield",
            comic_title="Sample Comic",
            chapter=chapter,
        )

    async def test_empty_image_response_also_uses_metadata_repair_once(self):
        chapter = types.SimpleNamespace(
            id=43,
            comic_id=8,
            chapter_number=12,
            source_url="https://01.komiku.asia/legacy-chapter-12/",
            images=None,
        )
        db = FakeChapterDb()
        fetch = AsyncMock(side_effect=[False, True])
        refresh_metadata = AsyncMock(return_value=True)

        with (
            patch.object(chapter_service, "fetch_and_save_chapter_images", fetch),
            patch.object(
                chapter_service,
                "_refresh_komiku_asia_chapter_metadata",
                refresh_metadata,
            ),
        ):
            await chapter_service._ensure_chapter_images_loaded(
                db,
                chapter,
                source_name="komiku_asia",
                comic_slug="sample-comic",
            )

        self.assertEqual(fetch.await_count, 2)
        refresh_metadata.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
