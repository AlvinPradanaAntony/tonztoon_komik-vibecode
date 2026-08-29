import unittest

from pydantic import ValidationError

from app.api.deps import is_admin_auth_user
from app.schemas.auth import AuthenticatedUser
from app.schemas.library import (
    BookmarkLinkCompletionSyncRequest,
    BookmarkStatusUpdateRequest,
    ComicCollectionsUpdateRequest,
    DownloadBatchRequest,
    LibrarySyncImportRequest,
    ReaderPreferenceUpdateRequest,
)


def comic(index: int) -> dict:
    return {"source_name": "source", "comic_slug": f"comic-{index}"}


def progress(index: int) -> dict:
    return {**comic(index), "chapter_number": float(index)}


class LibrarySchemaLimitTests(unittest.TestCase):
    def test_admin_role_is_resolved_from_auth_claims(self):
        admin = AuthenticatedUser(
            user_id="00000000-0000-0000-0000-000000000001",
            raw_claims={"app_metadata": {"account_role": "admin"}},
        )
        reader = AuthenticatedUser(
            user_id="00000000-0000-0000-0000-000000000002",
            role="reader",
        )

        self.assertTrue(is_admin_auth_user(admin))
        self.assertFalse(is_admin_auth_user(reader))

    def test_bookmark_status_only_accepts_supported_values(self):
        self.assertEqual(
            BookmarkStatusUpdateRequest(status="hiatus").status,
            "hiatus",
        )
        with self.assertRaises(ValidationError):
            BookmarkStatusUpdateRequest(status="dropped")

    def test_collection_membership_rejects_duplicate_or_invalid_ids(self):
        self.assertEqual(
            ComicCollectionsUpdateRequest(collection_ids=[1, 2]).collection_ids,
            [1, 2],
        )
        with self.assertRaises(ValidationError):
            ComicCollectionsUpdateRequest(collection_ids=[1, 1])
        with self.assertRaises(ValidationError):
            ComicCollectionsUpdateRequest(collection_ids=[0])

    def test_bookmark_links_count_toward_import_total(self):
        payload = {
            "bookmarks": [
                {"source_name": "source-a", "comic_slug": "comic"}
            ],
            "bookmark_links": [
                {
                    "bookmark": {
                        "source_name": "source-a",
                        "comic_slug": "comic",
                    },
                    "linked_comic": {
                        "source_name": "source-b",
                        "comic_slug": f"comic-{index}",
                    },
                    "confidence": 0.9,
                }
                for index in range(2_000)
            ],
        }

        parsed = LibrarySyncImportRequest.model_validate(payload)

        self.assertEqual(len(parsed.bookmark_links), 2_000)

    def test_import_at_total_limit_is_accepted(self):
        payload = LibrarySyncImportRequest.model_validate(
            {
                "bookmarks": [comic(index) for index in range(2_000)],
                "progress": [progress(index) for index in range(2_000)],
                "history": [progress(index) for index in range(2_000)],
                "completed_chapters": [progress(index) for index in range(2_000)],
                "downloads": [progress(index) for index in range(2_000)],
            }
        )
        self.assertEqual(len(payload.downloads), 2_000)

    def test_import_category_over_limit_is_rejected(self):
        with self.assertRaises(ValidationError):
            LibrarySyncImportRequest.model_validate(
                {"bookmarks": [comic(index) for index in range(2_001)]}
            )

    def test_import_nested_collection_over_limit_is_rejected(self):
        with self.assertRaises(ValidationError):
            LibrarySyncImportRequest.model_validate(
                {
                    "collections": [
                        {
                            "name": "Large",
                            "comics": [comic(index) for index in range(1_001)],
                        }
                    ]
                }
            )

    def test_import_total_over_limit_is_rejected(self):
        with self.assertRaises(ValidationError):
            LibrarySyncImportRequest.model_validate(
                {
                    "bookmarks": [comic(index) for index in range(2_000)],
                    "progress": [progress(index) for index in range(2_000)],
                    "history": [progress(index) for index in range(2_000)],
                    "completed_chapters": [
                        progress(index) for index in range(2_000)
                    ],
                    "downloads": [progress(index) for index in range(2_000)],
                    "collections": [{"name": "One"}],
                }
            )

    def test_download_batch_over_limit_is_rejected(self):
        with self.assertRaises(ValidationError):
            DownloadBatchRequest.model_validate(
                {
                    **comic(1),
                    "chapter_numbers": [float(index) for index in range(5_001)],
                }
            )

    def test_completed_sync_batch_over_limit_is_rejected(self):
        with self.assertRaises(ValidationError):
            BookmarkLinkCompletionSyncRequest(
                bookmark_ids=list(range(26)),
            )

    def test_reader_preferences_accept_autoscroll_speed_bounds(self):
        payload = ReaderPreferenceUpdateRequest.model_validate(
            {
                "auto_scroll_enabled": True,
                "auto_scroll_speed": 2.25,
            }
        )

        self.assertTrue(payload.auto_scroll_enabled)
        self.assertEqual(payload.auto_scroll_speed, 2.25)

    def test_reader_preferences_reject_autoscroll_speed_out_of_range(self):
        with self.assertRaises(ValidationError):
            ReaderPreferenceUpdateRequest.model_validate(
                {"auto_scroll_speed": 2.26}
            )


if __name__ == "__main__":
    unittest.main()
