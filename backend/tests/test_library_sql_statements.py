import unittest
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

from sqlalchemy.dialects import postgresql

from app.services.library_service import (
    _collection_summary_statement,
    _bookmark_link_candidate_statement,
    _completed_link_backfill_statement,
    _download_batch_upsert_statement,
    _download_projection_statement,
    _progress_projection_statement,
)


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class LibrarySqlStatementTests(unittest.TestCase):
    def test_bookmark_candidate_query_uses_trigram_index_operators(self):
        bookmark = SimpleNamespace(
            comic=SimpleNamespace(
                title="Solo Leveling",
                alternative_titles="Na Honjaman Level Up",
                source_name="source-a",
            )
        )
        sql = compile_sql(
            _bookmark_link_candidate_statement(
                bookmark,
                uuid4(),
                minimum_confidence=0.38,
            )
        )

        self.assertIn("comics.title %%", sql)
        self.assertIn("comics.alternative_titles %%", sql)
        self.assertNotIn("lower(comics.title)", sql)

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

    def test_completed_link_backfill_is_one_set_based_upsert(self):
        sql = compile_sql(
            _completed_link_backfill_statement(
                uuid4(),
                completed_at=datetime.now(UTC),
            )
        )

        self.assertIn("WITH bookmark_group_members AS", sql)
        self.assertIn("completed_numbers_by_group AS", sql)
        self.assertIn("INSERT INTO user_completed_chapters", sql)
        self.assertIn("SELECT DISTINCT", sql)
        self.assertIn(
            "ON CONFLICT (user_id, comic_id, chapter_id) DO NOTHING",
            sql,
        )

    def test_completed_link_backfill_can_scope_bookmark_groups(self):
        sql = compile_sql(
            _completed_link_backfill_statement(
                uuid4(),
                completed_at=datetime.now(UTC),
                bookmark_ids=[4, 7],
            )
        )

        self.assertIn("user_bookmarks.id IN", sql)
        self.assertIn("user_bookmark_links.bookmark_id IN", sql)

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
