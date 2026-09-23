import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import httpx

from scraper.refresh_voratoon_cover_urls import (
    CoverUrlCandidate,
    RefreshStats,
    _default_checkpoint,
    _normalize_checkpoint,
    fresh_url_is_reachable,
    parse_args,
    process_candidate,
    update_progress,
)


class RefreshVoratoonCoverUrlsUnitTests(unittest.IsolatedAsyncioTestCase):
    def test_parse_args_defaults(self):
        args = parse_args([])
        self.assertEqual(args.limit, 0)
        self.assertEqual(args.batch_size, 50)
        self.assertEqual(args.timeout, 30.0)
        self.assertIsNone(args.delay)
        self.assertEqual(args.delay_min, 1.5)
        self.assertEqual(args.delay_max, 4.0)
        self.assertFalse(args.dry_run)
        self.assertFalse(args.verify_image)
        self.assertFalse(args.reset)
        self.assertTrue(args.anti_blocking_enabled)

    def test_parse_args_custom_flags(self):
        args = parse_args([
            "--limit", "25",
            "--batch-size", "10",
            "--timeout", "15.0",
            "--dry-run",
            "--verify-image",
            "--reset",
            "--no-anti-blocking",
        ])
        self.assertEqual(args.limit, 25)
        self.assertEqual(args.batch_size, 10)
        self.assertEqual(args.timeout, 15.0)
        self.assertTrue(args.dry_run)
        self.assertTrue(args.verify_image)
        self.assertTrue(args.reset)
        self.assertFalse(args.anti_blocking_enabled)

    def test_parse_args_validation(self):
        with self.assertRaises(SystemExit):
            parse_args(["--limit", "-1"])
        with self.assertRaises(SystemExit):
            parse_args(["--batch-size", "0"])
        with self.assertRaises(SystemExit):
            parse_args(["--delay-min", "5", "--delay-max", "2"])

    def test_checkpoint_defaults_and_progress(self):
        cp = _default_checkpoint()
        self.assertEqual(cp["last_processed_comic_id"], 0)
        self.assertEqual(cp["stats"]["total_scanned"], 0)
        self.assertEqual(cp["progress"]["source"], "voratoon")

        update_progress(
            cp,
            current_comic_id=123,
            current_slug="test-slug",
            state="testing",
        )
        self.assertEqual(cp["progress"]["current_comic_id"], 123)
        self.assertEqual(cp["progress"]["current_slug"], "test-slug")
        self.assertEqual(cp["progress"]["state"], "testing")

        norm = _normalize_checkpoint({})
        self.assertIn("stats", norm)
        self.assertIn("progress", norm)

    async def test_process_candidate_unchanged(self):
        candidate = CoverUrlCandidate(
            id=1,
            slug="test-comic",
            title="Test Comic",
            cover_image_url="https://cvr.voratoon.id/prod/test.webp",
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        with patch(
            "scraper.refresh_voratoon_cover_urls.fetch_voratoon_cover_url_for_slug",
            new_callable=AsyncMock,
            return_value="https://cvr.voratoon.id/prod/test.webp",
        ):
            status = await process_candidate(client, candidate, dry_run=False, verify_image=False)
            self.assertEqual(status, "unchanged")

    async def test_process_candidate_dry_run_updated(self):
        candidate = CoverUrlCandidate(
            id=1,
            slug="test-comic",
            title="Test Comic",
            cover_image_url="https://cvr.voratoon.id/prod/old.webp",
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        with patch(
            "scraper.refresh_voratoon_cover_urls.fetch_voratoon_cover_url_for_slug",
            new_callable=AsyncMock,
            return_value="https://cvr.voratoon.id/prod/new.webp",
        ):
            status = await process_candidate(client, candidate, dry_run=True, verify_image=False)
            self.assertEqual(status, "updated")

    async def test_process_candidate_fetch_failed(self):
        candidate = CoverUrlCandidate(
            id=1,
            slug="test-comic",
            title="Test Comic",
            cover_image_url="https://cvr.voratoon.id/prod/old.webp",
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        with patch(
            "scraper.refresh_voratoon_cover_urls.fetch_voratoon_cover_url_for_slug",
            new_callable=AsyncMock,
            return_value=None,
        ):
            status = await process_candidate(client, candidate, dry_run=False, verify_image=False)
            self.assertEqual(status, "failed")

    async def test_process_candidate_verify_skipped(self):
        candidate = CoverUrlCandidate(
            id=1,
            slug="test-comic",
            title="Test Comic",
            cover_image_url="https://cvr.voratoon.id/prod/old.webp",
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        with patch(
            "scraper.refresh_voratoon_cover_urls.fetch_voratoon_cover_url_for_slug",
            new_callable=AsyncMock,
            return_value="https://cvr.voratoon.id/prod/unreachable.webp",
        ), patch(
            "scraper.refresh_voratoon_cover_urls.fresh_url_is_reachable",
            new_callable=AsyncMock,
            return_value=False,
        ):
            status = await process_candidate(client, candidate, dry_run=False, verify_image=True)
            self.assertEqual(status, "skipped")

    async def test_fresh_url_is_reachable(self):
        client = AsyncMock(spec=httpx.AsyncClient)
        response_ok = MagicMock()
        response_ok.status_code = 200
        client.head.return_value = response_ok
        self.assertTrue(await fresh_url_is_reachable(client, "https://cvr.voratoon.id/cover.webp"))

        response_fail = MagicMock()
        response_fail.status_code = 404
        client.head.return_value = response_fail
        self.assertFalse(await fresh_url_is_reachable(client, "https://cvr.voratoon.id/cover.webp"))


if __name__ == "__main__":
    unittest.main()
