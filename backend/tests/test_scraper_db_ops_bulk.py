import unittest
from datetime import UTC, datetime

from sqlalchemy.dialects import postgresql

from scraper.db_ops import (
    _mark_bookmarks_ongoing_for_new_chapters,
    build_bookmark_status_ongoing_statement,
    build_comic_status_ongoing_statement,
    build_chapter_metadata_upsert_statement,
    build_latest_feed_marker_update_statement,
    build_popular_feed_marker_update_statement,
)


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class _LatestChapterResult:
    def __init__(self, latest_chapter):
        self.latest_chapter = latest_chapter

    def scalar_one_or_none(self):
        return self.latest_chapter


class _ChapterSyncSession:
    def __init__(self, latest_chapter):
        self.latest_chapter = latest_chapter
        self.statements = []

    async def execute(self, statement):
        self.statements.append(statement)
        if len(self.statements) == 1:
            return _LatestChapterResult(self.latest_chapter)
        return None


class ScraperDbOpsBulkTests(unittest.TestCase):
    def test_new_chapter_status_update_targets_bookmarks_only(self):
        sql = compile_sql(build_bookmark_status_ongoing_statement(10))

        self.assertIn("UPDATE user_bookmarks SET", sql)
        self.assertIn("status_override=%(status_override)s", sql)
        self.assertIn("user_bookmarks.comic_id", sql)

    def test_new_chapter_status_update_targets_comic_globally(self):
        sql = compile_sql(build_comic_status_ongoing_statement(10))

        self.assertIn("UPDATE comics SET", sql)
        self.assertIn("status=%(status)s", sql)
        self.assertIn("comics.id", sql)
        self.assertIn("user_bookmark_links", sql)


class ScraperBookmarkStatusTests(unittest.IsolatedAsyncioTestCase):
    async def test_new_chapter_resets_bookmarks_to_ongoing(self):
        session = _ChapterSyncSession(latest_chapter=20)

        await _mark_bookmarks_ongoing_for_new_chapters(
            session,
            10,
            [{"chapter_number": 21}],
        )

        self.assertEqual(len(session.statements), 3)
        self.assertIn(
            "UPDATE comics SET",
            compile_sql(session.statements[1]),
        )
        self.assertIn(
            "UPDATE user_bookmarks SET",
            compile_sql(session.statements[2]),
        )

    async def test_existing_chapter_does_not_reset_bookmark_status(self):
        session = _ChapterSyncSession(latest_chapter=20)

        await _mark_bookmarks_ongoing_for_new_chapters(
            session,
            10,
            [{"chapter_number": 20}],
        )

        self.assertEqual(len(session.statements), 1)

    def test_latest_feed_marker_update_uses_values_table(self):
        now = datetime.now(UTC)
        sql = compile_sql(
            build_latest_feed_marker_update_statement(
                [
                    {
                        "comic_id": 1,
                        "latest_feed_batch_at": now,
                        "latest_feed_page": 1,
                        "latest_feed_position": 2,
                    },
                    {
                        "comic_id": 2,
                        "latest_feed_batch_at": now,
                        "latest_feed_page": 1,
                        "latest_feed_position": 3,
                    },
                ]
            )
        )

        self.assertIn("UPDATE comics SET", sql)
        self.assertIn("FROM (VALUES", sql)
        self.assertIn("latest_feed_markers", sql)

    def test_popular_feed_marker_update_uses_values_table(self):
        now = datetime.now(UTC)
        sql = compile_sql(
            build_popular_feed_marker_update_statement(
                [
                    {
                        "comic_id": 1,
                        "popular_feed_batch_at": now,
                        "popular_feed_page": 4,
                        "popular_feed_position": 5,
                    }
                ]
            )
        )

        self.assertIn("UPDATE comics SET", sql)
        self.assertIn("FROM (VALUES", sql)
        self.assertIn("popular_feed_markers", sql)

    def test_chapter_metadata_bulk_upsert_uses_constraint(self):
        sql = compile_sql(
            build_chapter_metadata_upsert_statement(
                10,
                [
                    {
                        "chapter_number": 1,
                        "title": "Chapter 1",
                        "source_url": "https://example.test/ch-1",
                        "release_date": None,
                    },
                    {
                        "chapter_number": 2,
                        "title": "Chapter 2",
                        "source_url": "https://example.test/ch-2",
                        "release_date": None,
                    },
                ],
            )
        )

        self.assertIn("INSERT INTO chapters", sql)
        self.assertIn("ON CONFLICT ON CONSTRAINT uq_comic_chapter", sql)
        self.assertIn("excluded.source_url", sql)

    def test_chapter_metadata_bulk_upsert_dedupes_chapter_numbers(self):
        compiled = build_chapter_metadata_upsert_statement(
            10,
            [
                {
                    "chapter_number": 1,
                    "title": "Chapter 1",
                    "source_url": "https://example.test/ch-1",
                    "release_date": None,
                },
                {
                    "chapter_number": 1.0,
                    "title": "Chapter 1 duplicate",
                    "source_url": "https://example.test/ch-1-dupe",
                    "release_date": None,
                },
                {
                    "chapter_number": 2,
                    "title": "Chapter 2",
                    "source_url": "https://example.test/ch-2",
                    "release_date": None,
                },
            ],
        ).compile(dialect=postgresql.dialect())

        chapter_numbers = [
            value
            for key, value in compiled.params.items()
            if key.startswith("chapter_number")
        ]
        source_urls = [
            value
            for key, value in compiled.params.items()
            if key.startswith("source_url")
        ]

        self.assertEqual(chapter_numbers, [1, 2])
        self.assertEqual(
            source_urls,
            ["https://example.test/ch-1", "https://example.test/ch-2"],
        )


if __name__ == "__main__":
    unittest.main()
