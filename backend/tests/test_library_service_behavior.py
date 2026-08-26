import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from sqlalchemy.dialects import postgresql

from app.schemas.library import (
    BookmarkLinkBatchRequest,
    CompletedChapterBatchImportRequest,
    DownloadBatchRequest,
    LibrarySyncImportRequest,
)
from app.services.library_service import (
    _bookmark_group_comic_ids,
    _propagate_completed_chapter,
    _synchronize_existing_completed_for_links,
    build_bookmark_response,
    build_reader_preferences_response,
    enqueue_download_batch,
    get_collection_detail,
    import_library_snapshot,
    list_bookmarks,
    list_bookmark_link_candidates,
    mark_completed_chapter_batch,
    set_comic_collections,
    set_bookmark_links,
    set_bookmark_status,
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

    def scalar_one_or_none(self):
        rows = self.scalar_rows if self.scalar_rows else self.rows
        if not rows:
            return None
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
        self.refresh_count = 0
        self.rolled_back = False

    async def execute(self, statement):
        self.statements.append(statement)
        return self.results.pop(0) if self.results else FakeResult()

    async def commit(self):
        self.commit_count += 1

    async def refresh(self, instance):
        self.refresh_count += 1
        return None

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
    async def test_set_comic_collections_uses_bulk_writes_and_one_commit(self):
        db = FakeSession(
            [
                FakeResult(scalar_rows=[1, 2]),
                FakeResult(scalar_rows=[1]),
                FakeResult(),
                FakeResult(),
            ]
        )

        with patch(
            "app.services.library_service.resolve_comic_or_raise",
            return_value=comic(),
        ):
            await set_comic_collections(
                db,
                uuid4(),
                "source",
                "comic",
                {1, 2},
            )

        self.assertEqual(db.commit_count, 1)
        self.assertEqual(len(db.statements), 4)
        compiled = [
            str(statement.compile(dialect=postgresql.dialect()))
            for statement in db.statements
        ]
        self.assertIn("ON CONFLICT (collection_id, comic_id) DO NOTHING", compiled[2])
        self.assertIn("UPDATE user_collections", compiled[3])
        self.assertNotIn("JOIN comics", "\n".join(compiled))

    async def test_bookmark_response_uses_personal_status_override(self):
        now = datetime(2026, 8, 2, tzinfo=timezone.utc)
        bookmark = SimpleNamespace(
            id=1,
            comic=comic(),
            status_override="hiatus",
            links=[],
            created_at=now,
            updated_at=now,
        )

        response = build_bookmark_response(bookmark)

        self.assertEqual(response.comic.status, "hiatus")

    async def test_admin_bookmark_status_updates_comic_globally(self):
        comic_row = comic()
        linked_comic = comic()
        linked_comic.id = 2
        linked_comic.source_name = "source-b"
        bookmark = SimpleNamespace(
            id=1,
            comic=comic_row,
            status_override="completed",
            links=[SimpleNamespace(comic_id=linked_comic.id, comic=linked_comic)],
            updated_at=None,
        )
        db = FakeSession([FakeResult(scalar_rows=[bookmark])])

        with patch(
            "app.services.library_service.resolve_comic_or_raise",
            return_value=comic_row,
        ):
            await set_bookmark_status(
                db,
                uuid4(),
                "source",
                "comic",
                "hiatus",
                global_scope=True,
            )

        self.assertEqual(comic_row.status, "hiatus")
        self.assertEqual(linked_comic.status, "hiatus")
        self.assertIsNone(bookmark.status_override)
        self.assertEqual(db.commit_count, 1)
        self.assertEqual(db.refresh_count, 0)

    async def test_reader_bookmark_status_remains_personal(self):
        comic_row = comic()
        bookmark = SimpleNamespace(
            id=1,
            comic=comic_row,
            status_override=None,
            links=[],
            updated_at=None,
        )
        db = FakeSession([FakeResult(scalar_rows=[bookmark])])

        with patch(
            "app.services.library_service.resolve_comic_or_raise",
            return_value=comic_row,
        ):
            await set_bookmark_status(
                db,
                uuid4(),
                "source",
                "comic",
                "completed",
            )

        self.assertEqual(bookmark.status_override, "completed")
        self.assertIsNone(comic_row.status)

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
        db = FakeSession([FakeResult(rows=[bookmark])])

        response = await list_bookmarks(db, uuid4(), page_size=20, offset=0)

        self.assertEqual(response, [bookmark])
        self.assertEqual(len(db.statements), 1)
        self.assertNotIn("EXISTS", str(db.statements[0].whereclause))

    async def test_list_bookmarks_filters_and_sorts_by_title(self):
        db = FakeSession([FakeResult(rows=[])])

        await list_bookmarks(
            db,
            uuid4(),
            comic_type="manhwa",
            comic_status="hiatus",
            sort="az",
        )

        statement = db.statements[0]
        sql = str(statement.compile(dialect=postgresql.dialect()))
        self.assertIn("comics.type", sql)
        self.assertIn("status_override", sql)
        self.assertIn("ORDER BY lower(comics.title) ASC", sql)
        self.assertIn(["manhwa"], statement.compile().params.values())
        self.assertIn(["hiatus"], statement.compile().params.values())

    async def test_list_bookmarks_searches_title_with_user_scope(self):
        db = FakeSession([FakeResult(rows=[])])
        user_id = uuid4()

        await list_bookmarks(db, user_id, search="  Solo Leveling  ")

        statement = db.statements[0]
        sql = str(statement.compile(dialect=postgresql.dialect()))
        self.assertIn("lower(comics.title) LIKE", sql)
        self.assertIn("user_bookmarks.user_id =", sql)
        self.assertIn("solo leveling", statement.compile().params.values())

    async def test_list_bookmarks_latest_prioritizes_has_new_chapter(self):
        db = FakeSession([FakeResult(rows=[])])

        await list_bookmarks(db, uuid4(), sort="latest")

        sql = str(db.statements[0].compile(dialect=postgresql.dialect()))
        order_sql = sql.split("ORDER BY", 1)[1]
        self.assertTrue(order_sql.lstrip().startswith("has_new_chapter DESC"))
        self.assertNotIn("comics.updated_at", order_sql)
        self.assertIn("EXISTS", str(db.statements[0].whereclause))

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
                FakeResult(rows=[(bookmark, False) for bookmark in bookmark_rows]),
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

    async def test_completed_chapter_batch_uses_one_resolve_and_one_propagation(self):
        user_id = uuid4()
        payload = CompletedChapterBatchImportRequest.model_validate(
            {
                "chapters": [
                    {
                        "source_name": "source-a",
                        "comic_slug": "comic-a",
                        "chapter_number": 10,
                    },
                    {
                        "source_name": "source-b",
                        "comic_slug": "comic-b",
                        "chapter_number": 10,
                    },
                ]
            }
        )
        db = FakeSession([FakeResult(scalar_rows=[4, 7])])
        resolve = AsyncMock(
            return_value={
                ("source-a", "comic-a", 10.0): (101, 11),
                ("source-b", "comic-b", 10.0): (202, 22),
            }
        )
        upsert = AsyncMock(return_value=2)
        propagate = AsyncMock(return_value=3)

        with (
            patch("app.services.library_service._resolve_chapter_selector_ids", resolve),
            patch("app.services.library_service._upsert_completed_chapter_rows", upsert),
            patch(
                "app.services.library_service._synchronize_existing_completed_for_links",
                propagate,
            ),
        ):
            response = await mark_completed_chapter_batch(db, user_id, payload)

        self.assertEqual(response.completed_synced, 2)
        self.assertEqual(response.completed_propagated, 3)
        resolve.assert_awaited_once()
        upsert.assert_awaited_once()
        propagate.assert_awaited_once_with(
            db,
            user_id,
            bookmark_ids=[4, 7],
            commit=False,
        )
        self.assertEqual(len(db.statements), 1)
        self.assertEqual(db.commit_count, 1)

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
