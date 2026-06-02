import unittest
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

from app.schemas.library import DownloadBatchRequest, LibrarySyncImportRequest
from app.services.library_service import (
    enqueue_download_batch,
    get_collection_detail,
    import_library_snapshot,
    list_bookmarks,
)


class FakeResult:
    def __init__(self, rows=None, scalar_rows=None):
        self.rows = rows or []
        self.scalar_rows = scalar_rows or []
        self.scalar_mode = False

    def all(self):
        return self.scalar_rows if self.scalar_mode else self.rows

    def scalars(self):
        self.scalar_mode = True
        return self

    def first(self):
        return self.scalar_rows[0] if self.scalar_rows else None


class FakeTransaction:
    def __init__(self, db):
        self.db = db

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        self.db.rolled_back = exc_type is not None


class FakeSession:
    def __init__(self, results=None):
        self.results = list(results or [])
        self.statements = []
        self.commit_count = 0
        self.rolled_back = False

    async def execute(self, statement):
        self.statements.append(statement)
        return self.results.pop(0) if self.results else FakeResult()

    async def commit(self):
        self.commit_count += 1

    def begin(self):
        return FakeTransaction(self)


def comic():
    return SimpleNamespace(
        id=1,
        source_name="source",
        slug="comic",
        title="Comic",
        cover_image_url=None,
        author=None,
        status=None,
        type=None,
        rating=None,
        total_view=None,
    )


def chapters(total: int):
    return [
        SimpleNamespace(
            chapter_id=index,
            comic_id=1,
            chapter_number=float(index),
        )
        for index in range(1, total + 1)
    ]


class LibraryServiceBehaviorTests(unittest.IsolatedAsyncioTestCase):
    async def test_download_batch_500_uses_one_bulk_write_and_one_commit(self):
        db = FakeSession([FakeResult(rows=chapters(500)), FakeResult()])
        payload = DownloadBatchRequest(source_name="source", comic_slug="comic")
        with patch(
            "app.services.library_service.resolve_comic_or_raise",
            return_value=comic(),
        ):
            response = await enqueue_download_batch(db, uuid4(), payload)

        self.assertEqual(response.created_total, 500)
        self.assertEqual(response.updated_total, 0)
        self.assertEqual(len(db.statements), 3)
        self.assertEqual(db.commit_count, 1)

    async def test_download_batch_retry_counts_existing_rows_as_updates(self):
        existing_ids = list(range(1, 501))
        db = FakeSession(
            [
                FakeResult(rows=chapters(500)),
                FakeResult(scalar_rows=existing_ids),
            ]
        )
        payload = DownloadBatchRequest(source_name="source", comic_slug="comic")
        with patch(
            "app.services.library_service.resolve_comic_or_raise",
            return_value=comic(),
        ):
            response = await enqueue_download_batch(db, uuid4(), payload)

        self.assertEqual(response.created_total, 0)
        self.assertEqual(response.updated_total, 500)
        self.assertEqual(db.commit_count, 1)

    async def test_invalid_import_selector_rolls_back_transaction(self):
        db = FakeSession([FakeResult()])
        payload = LibrarySyncImportRequest.model_validate(
            {
                "progress": [
                    {
                        "source_name": "missing",
                        "comic_slug": "missing",
                        "chapter_number": 1,
                    }
                ]
            }
        )
        with self.assertRaises(LookupError):
            await import_library_snapshot(db, uuid4(), payload)
        self.assertTrue(db.rolled_back)
        self.assertEqual(db.commit_count, 0)

    async def test_collection_detail_filters_one_collection_id(self):
        db = FakeSession([FakeResult()])
        await get_collection_detail(db, uuid4(), 42)
        params = db.statements[0].compile().params
        self.assertIn(42, params.values())

    async def test_list_bookmarks_returns_query_rows(self):
        bookmark = SimpleNamespace(id=7)
        db = FakeSession([FakeResult(scalar_rows=[bookmark])])

        response = await list_bookmarks(db, uuid4(), page_size=20, offset=0)

        self.assertEqual(response, [bookmark])
        self.assertEqual(len(db.statements), 1)


if __name__ == "__main__":
    unittest.main()
