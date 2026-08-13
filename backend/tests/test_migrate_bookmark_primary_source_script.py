import unittest

from scripts.migrate_bookmark_primary_source import (
    BookmarkLinkRecord,
    BookmarkRecord,
    build_migration_plan,
)


def bookmark(bookmark_id: int, comic_id: int, source_name: str) -> BookmarkRecord:
    return BookmarkRecord(
        bookmark_id=bookmark_id,
        comic_id=comic_id,
        source_name=source_name,
        title=f"{source_name}-{comic_id}",
        slug=f"{source_name}-{comic_id}",
    )


def link(link_id: int, bookmark_id: int, comic_id: int, source_name: str) -> BookmarkLinkRecord:
    return BookmarkLinkRecord(
        link_id=link_id,
        bookmark_id=bookmark_id,
        comic_id=comic_id,
        source_name=source_name,
        title=f"{source_name}-{comic_id}",
        slug=f"{source_name}-{comic_id}",
        confidence=0.9,
    )


class BookmarkPrimarySourceMigrationPlanTests(unittest.TestCase):
    def test_moves_only_bookmarks_with_target_source_alternative(self):
        bookmarks = [
            bookmark(1, 10, "komikcast"),
            bookmark(2, 20, "komiku"),
            bookmark(3, 30, "shinigami"),
        ]
        links = [
            link(101, 1, 11, "shinigami"),
            link(102, 2, 21, "komikcast"),
        ]

        plan = build_migration_plan(bookmarks, links, "shinigami")

        self.assertEqual([(item.bookmark.bookmark_id, item.target.comic_id) for item in plan.actions], [(1, 11)])
        self.assertEqual(
            [(item.bookmark.bookmark_id, item.reason) for item in plan.skips],
            [
                (2, "tidak memiliki alternatif pada source tujuan"),
                (3, "sudah memakai source tujuan"),
            ],
        )

    def test_skips_target_that_is_another_direct_bookmark(self):
        bookmarks = [
            bookmark(1, 10, "komikcast"),
            bookmark(2, 11, "shinigami"),
        ]
        links = [link(101, 1, 11, "shinigami")]

        plan = build_migration_plan(bookmarks, links, "shinigami")

        self.assertEqual(plan.actions, [])
        self.assertEqual(plan.skips[0].reason, "komik tujuan sudah menjadi bookmark utama lain")

    def test_skips_ambiguous_target_source_links(self):
        bookmarks = [bookmark(1, 10, "komikcast")]
        links = [
            link(101, 1, 11, "shinigami"),
            link(102, 1, 12, "shinigami"),
        ]

        plan = build_migration_plan(bookmarks, links, "shinigami")

        self.assertEqual(plan.actions, [])
        self.assertEqual(
            plan.skips[0].reason,
            "memiliki lebih dari satu alternatif pada source tujuan",
        )


if __name__ == "__main__":
    unittest.main()
