import unittest
from datetime import UTC, datetime

from sqlalchemy.dialects import postgresql

from scraper.db_ops import (
    build_chapter_metadata_upsert_statement,
    build_latest_feed_marker_update_statement,
    build_popular_feed_marker_update_statement,
)


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class ScraperDbOpsBulkTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
