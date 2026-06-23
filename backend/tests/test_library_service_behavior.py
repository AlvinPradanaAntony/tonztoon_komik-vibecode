import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from app.schemas.library import (
    BookmarkLinkBatchRequest,
    DownloadBatchRequest,
    LibrarySyncImportRequest,
)
from app.services.library_service import (
    _bookmark_group_comic_ids,
    _propagate_completed_chapter,
    _synchronize_existing_completed_for_links,
    build_reader_preferences_response,
    enqueue_download_batch,
    get_collection_detail,
    import_library_snapshot,
    list_bookmarks,
    list_bookmark_link_candidates,
    set_bookmark_links,
    synchronize_completed_link_batch,
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

    def scalar_one(self):
        rows = self.scalar_rows if self.scalar_rows else self.rows
        value = rows[0]
        return value[0] if isinstance(value, tuple) else value


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
    async def test_reader_preferences_response_includes_autoscroll(self):
        preference = SimpleNamespace(
            default_reading_mode="vertical",
            reading_direction="ltr",
            mark_read_on_complete=False,
            default_binge_mode=True,
            auto_scroll_enabled=True,
            auto_scroll_speed=1.25,
            updated_at=datetime(2026, 6, 17, tzinfo=timezone.utc),
        )

        response = build_reader_preferences_response(preference)

        self.assertTrue(response.auto_scroll_enabled)
        self.assertEqual(response.auto_scroll_speed, 1.25)

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

    async def test_bookmark_group_contains_hub_and_all_spokes(self):
        db = FakeSession(
            [
                FakeResult(
                    scalar_rows=[SimpleNamespace(id=10, comic_id=1)],
                ),
                FakeResult(scalar_rows=[2, 3]),
            ]
        )

        comic_ids = await _bookmark_group_comic_ids(db, uuid4(), 2)

        self.assertEqual(comic_ids, {1, 2, 3})

    async def test_completed_chapter_propagates_to_every_group_spoke(self):
        db = FakeSession()
        chapter = SimpleNamespace(id=21, comic_id=2, chapter_number=15.0)
        group_lookup = AsyncMock(return_value={1, 2, 3})
        chapter_lookup = AsyncMock(return_value=[(11, 1), (31, 3)])
        upsert = AsyncMock(return_value=2)

        with (
            patch(
                "app.services.library_service._bookmark_group_comic_ids",
                group_lookup,
            ),
            patch(
                "app.services.library_service._group_chapters_for_number",
                chapter_lookup,
            ),
            patch(
                "app.services.library_service._upsert_completed_chapter_rows",
                upsert,
            ),
        ):
            propagated = await _propagate_completed_chapter(
                db,
                uuid4(),
                chapter,
                completed_at=SimpleNamespace(),
            )

        self.assertEqual(propagated, 2)
        self.assertEqual(chapter_lookup.await_args.args[1], {1, 3})
        self.assertEqual(chapter_lookup.await_args.args[2], 15.0)
        self.assertEqual(upsert.await_args.args[2], [(11, 1), (31, 3)])

    async def test_completed_link_backfill_uses_one_database_statement(self):
        db = FakeSession([FakeResult(rows=[(3,)])])

        propagated = await _synchronize_existing_completed_for_links(
            db,
            uuid4(),
        )

        self.assertEqual(propagated, 3)
        self.assertEqual(len(db.statements), 1)
        self.assertEqual(db.commit_count, 1)

    async def test_candidate_scan_only_queries_one_bookmark_page(self):
        bookmark_rows = [
            SimpleNamespace(
                id=index,
                comic_id=index,
                comic=SimpleNamespace(
                    **{
                        **comic().__dict__,
                        "id": index,
                        "slug": f"comic-{index}",
                        "alternative_titles": None,
                    }
                ),
                links=[],
            )
            for index in range(1, 12)
        ]
        db = FakeSession(
            [
                FakeResult(scalar_rows=bookmark_rows),
                *(FakeResult() for _ in range(10)),
            ]
        )

        page = await list_bookmark_link_candidates(
            db,
            uuid4(),
            page_size=10,
        )

        self.assertEqual(page.scanned_total, 10)
        self.assertEqual(page.next_offset, 10)
        self.assertTrue(page.has_more)
        self.assertEqual(len(db.statements), 11)

    async def test_candidate_scan_can_scope_to_one_bookmark(self):
        bookmark = SimpleNamespace(
            id=1,
            comic_id=1,
            comic=SimpleNamespace(
                **{
                    **comic().__dict__,
                    "alternative_titles": None,
                }
            ),
            links=[],
        )
        db = FakeSession(
            [
                FakeResult(scalar_rows=[bookmark]),
                FakeResult(),
            ]
        )

        page = await list_bookmark_link_candidates(
            db,
            uuid4(),
            source_name="source",
            comic_slug="comic",
        )

        self.assertEqual(page.scanned_total, 1)
        self.assertFalse(page.has_more)
        self.assertEqual(len(db.statements), 2)
        query_params = db.statements[0].compile().params
        self.assertIn("source", query_params.values())
        self.assertIn("comic", query_params.values())

    async def test_completed_sync_batch_scopes_backfill_to_owned_groups(self):
        db = FakeSession(
            [
                FakeResult(scalar_rows=[4, 7]),
                FakeResult(rows=[(3,)]),
            ]
        )

        response = await synchronize_completed_link_batch(
            db,
            uuid4(),
            [4, 7, 99],
        )

        self.assertEqual(response.processed_groups, 2)
        self.assertEqual(response.completed_propagated, 3)
        self.assertEqual(db.commit_count, 1)
        params = db.statements[1].compile().params
        self.assertIn([4, 7], params.values())

    async def test_bookmark_links_use_bulk_lookup_delete_and_upsert(self):
        user_id = uuid4()
        payload = BookmarkLinkBatchRequest.model_validate(
            {
                "links": [
                    {
                        "bookmark": {
                            "source_name": "source-a",
                            "comic_slug": f"origin-{index}",
                        },
                        "linked_comic": {
                            "source_name": "source-b",
                            "comic_slug": f"linked-{index}",
                        },
                        "confidence": 0.9,
                    }
                    for index in range(100)
                ]
            }
        )
        comic_ids = {
            ("source-a", f"origin-{index}"): index + 1
            for index in range(100)
        }
        comic_ids.update(
            {
                ("source-b", f"linked-{index}"): index + 1001
                for index in range(100)
            }
        )
        bookmark_rows = [
            SimpleNamespace(id=index + 5001, comic_id=index + 1)
            for index in range(100)
        ]
        db = FakeSession(
            [
                FakeResult(rows=bookmark_rows),
                FakeResult(),
                FakeResult(),
                FakeResult(),
            ]
        )

        with patch(
            "app.services.library_service._resolve_comic_selector_ids",
            return_value=comic_ids,
        ):
            response = await set_bookmark_links(db, user_id, payload)

        self.assertEqual(response.linked_total, 100)
        self.assertEqual(len(response.completion_sync_bookmark_ids), 100)
        self.assertEqual(len(db.statements), 4)
        self.assertEqual(db.commit_count, 1)


if __name__ == "__main__":
    unittest.main()
