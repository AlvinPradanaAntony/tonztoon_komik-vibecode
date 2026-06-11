import unittest

from app.services import chapter_service


class ChapterPrefetchCooldownTests(unittest.TestCase):
    def setUp(self):
        self.original_seconds = chapter_service.PREFETCH_COOLDOWN_SECONDS
        self.original_max_entries = chapter_service.PREFETCH_COOLDOWN_MAX_ENTRIES
        chapter_service._prefetch_cooldowns.clear()

    def tearDown(self):
        chapter_service.PREFETCH_COOLDOWN_SECONDS = self.original_seconds
        chapter_service.PREFETCH_COOLDOWN_MAX_ENTRIES = self.original_max_entries
        chapter_service._prefetch_cooldowns.clear()

    def test_cooldown_blocks_then_allows_after_ttl(self):
        chapter_service.PREFETCH_COOLDOWN_SECONDS = 10

        allowed, elapsed = chapter_service._register_prefetch_cooldown(
            42,
            now=100.0,
        )
        self.assertTrue(allowed)
        self.assertEqual(elapsed, 10)

        allowed, elapsed = chapter_service._register_prefetch_cooldown(
            42,
            now=105.0,
        )
        self.assertFalse(allowed)
        self.assertEqual(elapsed, 5)

        allowed, elapsed = chapter_service._register_prefetch_cooldown(
            42,
            now=111.0,
        )
        self.assertTrue(allowed)
        self.assertEqual(elapsed, 10)

    def test_cooldown_map_is_bounded(self):
        chapter_service.PREFETCH_COOLDOWN_SECONDS = 60
        chapter_service.PREFETCH_COOLDOWN_MAX_ENTRIES = 3

        for comic_id in range(1, 5):
            allowed, _ = chapter_service._register_prefetch_cooldown(
                comic_id,
                now=100.0 + comic_id,
            )
            self.assertTrue(allowed)

        self.assertEqual(len(chapter_service._prefetch_cooldowns), 3)
        self.assertNotIn(1, chapter_service._prefetch_cooldowns)
        self.assertIn(4, chapter_service._prefetch_cooldowns)

    def test_prune_removes_expired_entries(self):
        chapter_service.PREFETCH_COOLDOWN_SECONDS = 10
        chapter_service.PREFETCH_COOLDOWN_MAX_ENTRIES = 10
        chapter_service._prefetch_cooldowns[1] = 90.0
        chapter_service._prefetch_cooldowns[2] = 105.0

        chapter_service._prune_prefetch_cooldowns(now=101.0)

        self.assertNotIn(1, chapter_service._prefetch_cooldowns)
        self.assertIn(2, chapter_service._prefetch_cooldowns)

    def test_komiku_asia_prefetch_window_is_conservative(self):
        self.assertEqual(chapter_service.KOMIKU_ASIA_PREFETCH_WINDOW, 2)
        self.assertLess(chapter_service.KOMIKU_ASIA_PREFETCH_WINDOW, chapter_service.PREFETCH_WINDOW)


if __name__ == "__main__":
    unittest.main()
