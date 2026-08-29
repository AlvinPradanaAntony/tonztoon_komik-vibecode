import types
import unittest
from unittest.mock import patch

from scraper import sync_chapter_images


class _FakeSession:
    def __init__(self, rows):
        self.rows = rows
        self.executed = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    async def execute(self, statement, params):
        self.executed.append((statement, params))
        return [types.SimpleNamespace(_mapping=row) for row in self.rows]


class DimensionAuditTests(unittest.IsolatedAsyncioTestCase):
    async def test_audit_is_read_only_and_fills_supported_sources(self):
        session = _FakeSession(
            [
                {
                    "source_name": "komiku",
                    "total_chapters": 10,
                    "chapters_without_valid_images": 2,
                    "chapters_with_complete_dimensions": 6,
                    "chapters_with_missing_dimensions": 2,
                }
            ]
        )

        with patch.object(sync_chapter_images, "async_session", return_value=session):
            rows = await sync_chapter_images.audit_dimension_completeness(
                source_name=None,
            )

        self.assertEqual(rows[0]["source_name"], "komiku")
        self.assertEqual(rows[0]["chapters_with_missing_dimensions"], 2)
        self.assertEqual(
            {row["source_name"] for row in rows},
            set(sync_chapter_images.SUPPORTED_SOURCES),
        )
        statement, params = session.executed[0]
        self.assertIn("SELECT", str(statement).upper())
        self.assertNotIn("UPDATE", str(statement).upper())
        self.assertEqual(params, {"source_name": None})

    def test_dry_run_requires_dimensions_mode(self):
        args = sync_chapter_images.parse_args(
            ["--mode", "dimensions", "--dry-run", "--source", "komiku"]
        )
        self.assertTrue(args["dry_run"])
        self.assertEqual(args["mode"], "dimensions")
        self.assertEqual(args["source"], "komiku")

        with self.assertRaisesRegex(ValueError, "hanya dapat digunakan"):
            sync_chapter_images.parse_args(["--dry-run"])


if __name__ == "__main__":
    unittest.main()
