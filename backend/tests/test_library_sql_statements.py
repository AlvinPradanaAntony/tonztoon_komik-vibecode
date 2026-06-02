import unittest
from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy.dialects import postgresql

from app.services.library_service import (
    _collection_summary_statement,
    _download_batch_upsert_statement,
    _download_projection_statement,
    _progress_projection_statement,
)


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class LibrarySqlStatementTests(unittest.TestCase):
    def test_download_batch_uses_on_conflict_upsert(self):
        now = datetime.now(UTC)
        sql = compile_sql(
            _download_batch_upsert_statement(
                [
                    {
                        "user_id": uuid4(),
                        "comic_id": 1,
                        "chapter_id": 2,
                        "status": "pending",
                        "source_device_id": None,
                        "last_error": None,
                        "updated_at": now,
                        "downloaded_at": None,
                    }
                ]
            )
        )
        self.assertIn("ON CONFLICT (user_id, chapter_id) DO UPDATE", sql)

    def test_collection_summary_uses_outer_join_and_count(self):
        sql = compile_sql(_collection_summary_statement(uuid4()))
        self.assertIn("LEFT OUTER JOIN user_collection_comics", sql)
        self.assertIn("count(user_collection_comics.id)", sql)

    def test_collection_summary_membership_does_not_reduce_count(self):
        sql = compile_sql(_collection_summary_statement(uuid4(), comic_id=9))
        self.assertIn("EXISTS", sql)
        self.assertIn("count(user_collection_comics.id)", sql)

    def test_progress_and_download_projection_do_not_select_images_blob(self):
        for statement in (
            _progress_projection_statement(uuid4()),
            _download_projection_statement(uuid4()),
        ):
            sql = compile_sql(statement)
            self.assertNotIn("chapters.images AS images", sql)
            self.assertIn("jsonb_array_length(chapters.images)", sql)


if __name__ == "__main__":
    unittest.main()
