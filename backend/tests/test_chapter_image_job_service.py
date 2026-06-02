import unittest

from sqlalchemy.dialects import postgresql

from app.models import ChapterImageJob
from app.services.chapter_image_job_service import (
    build_chapter_image_job_upsert_statement,
    enqueue_komiku_asia_chapter_image_jobs,
)


class FakeSession:
    def __init__(self):
        self.statements = []
        self.commit_count = 0

    async def execute(self, statement):
        self.statements.append(statement)

    async def commit(self):
        self.commit_count += 1


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class ChapterImageJobServiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_enqueue_uses_bulk_chunks_without_commit(self):
        db = FakeSession()
        chapter_ids = list(range(1, 601))
        total = await enqueue_komiku_asia_chapter_image_jobs(
            db,
            chapter_ids,
            priority=100,
        )

        self.assertEqual(total, 600)
        self.assertEqual(len(db.statements), 2)
        self.assertEqual(db.commit_count, 0)

    async def test_enqueue_deduplicates_before_bulk_upsert(self):
        db = FakeSession()
        total = await enqueue_komiku_asia_chapter_image_jobs(
            db,
            [1, 1, 2],
            priority=10,
        )

        self.assertEqual(total, 2)
        self.assertEqual(len(db.statements), 1)

    def test_upsert_statement_uses_on_conflict_chapter_id(self):
        sql = compile_sql(
            build_chapter_image_job_upsert_statement(
                [1, 2],
                priority=100,
            )
        )

        self.assertIn("ON CONFLICT (chapter_id) DO UPDATE", sql)
        self.assertIn("greatest(chapter_image_jobs.priority", sql)
        self.assertIn("VALUES", sql)

    def test_duplicate_chapter_id_index_is_not_declared_in_model(self):
        index_names = {index.name for index in ChapterImageJob.__table__.indexes}
        self.assertNotIn("ix_chapter_image_jobs_chapter_id", index_names)
        self.assertIn("ix_chapter_image_jobs_status_priority_available", index_names)


if __name__ == "__main__":
    unittest.main()
