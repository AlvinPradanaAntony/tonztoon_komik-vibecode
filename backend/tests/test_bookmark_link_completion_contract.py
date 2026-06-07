import unittest

from app.models import UserBookmarkLink
from app.schemas.library import BookmarkLinkBatchResponse


class BookmarkLinkCompletionContractTests(unittest.TestCase):
    def test_bookmark_link_only_stores_comic_pair_metadata(self):
        self.assertEqual(
            set(UserBookmarkLink.__table__.c.keys()),
            {
                "id",
                "user_id",
                "bookmark_id",
                "comic_id",
                "confidence",
                "created_at",
                "updated_at",
            },
        )

    def test_bookmark_link_response_includes_sync_counters(self):
        response = BookmarkLinkBatchResponse(linked_total=1)

        self.assertEqual(response.linked_total, 1)
        self.assertEqual(response.completed_propagated, 0)


if __name__ == "__main__":
    unittest.main()
