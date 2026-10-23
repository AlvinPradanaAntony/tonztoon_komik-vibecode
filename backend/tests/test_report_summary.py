import unittest
from unittest.mock import patch

from scraper.report_summary import (
    build_latest_summary,
    build_popular_summary,
    build_stats_summary,
    clean_ansi,
    detect_log_has_errors,
)
from scraper.validate_config import validate_configuration


class ValidateConfigTests(unittest.TestCase):
    def test_missing_all_returns_errors(self):
        with patch.dict("os.environ", {}, clear=True):
            errors = validate_configuration()
            self.assertTrue(any("DATABASE_URL" in e for e in errors))
            self.assertTrue(any("FCM_SERVICE_ACCOUNT_JSON" in e for e in errors))

    def test_valid_config(self):
        valid_env = {
            "DATABASE_URL": "postgresql+asyncpg://user:pass@localhost:5432/db",
            "FCM_PROJECT_ID": "my-project",
            "FCM_SERVICE_ACCOUNT_JSON": '{"project_id": "my-project", "client_email": "a@b.com", "private_key": "xyz"}',
        }
        with patch.dict("os.environ", valid_env, clear=True):
            errors = validate_configuration()
            self.assertEqual(errors, [])

    def test_db_only_validation(self):
        with patch.dict("os.environ", {"DATABASE_URL": "postgresql+asyncpg://localhost/db"}, clear=True):
            errors = validate_configuration(require_fcm=False)
            self.assertEqual(errors, [])



class ReportSummaryTests(unittest.TestCase):
    def test_clean_ansi(self):
        self.assertEqual(clean_ansi("\x1b[32mSuccess\x1b[0m"), "Success")

    def test_detect_errors(self):
        self.assertTrue(detect_log_has_errors(["2026-10-24 00:00:00 [ERROR] failed: 403"]))
        self.assertTrue(detect_log_has_errors(["Selesai scraper voratoon: 1 errors"]))
        self.assertFalse(detect_log_has_errors(["Selesai scraper komiku: 0 errors"]))

    def test_build_latest_summary(self):
        lines = [
            "Scraper: komiku (https://komiku.org)",
            "Selesai scraper komiku: 2 pages, 20 listing items, 5 candidates, 15 unchanged, 5 comics, 50 chapter metadata, 10 chapter images pre-warmed, 1 push events, 1 push messages, 0 skipped, 0 errors",
            "Done: One Piece — 1 chapters metadata, 0 images pre-warmed",
            "Scraper: voratoon (https://voratoon.co)",
            "Last error voratoon: HTTPStatusError: 403 Forbidden",
            "Selesai scraper voratoon: 0 pages, 0 listing items, 0 candidates, 0 unchanged, 0 comics, 0 chapter metadata, 0 chapter images pre-warmed, 0 push events, 0 push messages, 0 skipped, 1 errors",
        ]
        summary = build_latest_summary(
            lines,
            trigger_source="manual",
            source="all",
            max_pages="10",
            early_stop="3",
            exit_status="0",
            completed_at="2026-10-24 00:00:00 UTC",
        )
        self.assertIn("## 🕷️ Scraper summary", summary)
        self.assertIn("komiku", summary)
        self.assertIn("voratoon", summary)
        self.assertIn("completed_with_errors", summary)
        self.assertIn("### ⚠️ Source Last Errors", summary)
        self.assertIn("HTTPStatusError: 403 Forbidden", summary)

    def test_build_popular_summary(self):
        lines = [
            "Scraper: komiku (https://komiku.org)",
            "Ringkasan popular page 1: 5 kandidat baru, 15 existing ditandai",
            "Selesai scraper komiku: 1 pages, 20 listing items, 5 candidates, 15 unchanged, 5 comics, 50 chapter metadata, 10 chapter images pre-warmed, 0 push events, 0 push messages, 0 skipped, 0 errors",
        ]
        summary = build_popular_summary(
            lines,
            trigger_source="cron",
            source="komiku",
            popular_pages="5",
            popular_no_early_stop="false",
            early_stop="3",
            exit_status="0",
            completed_at="2026-10-24 00:00:00 UTC",
        )
        self.assertIn("## 🔥 Popular sync summary", summary)
        self.assertIn("komiku", summary)
        self.assertIn("(success)", summary)

    def test_build_stats_summary(self):
        # Format tabel proporsional baru
        lines = [
            "  📗 Komiku         :  12,000 komik  |  Refreshed: 2026-10-24 00:00:00  |  ✅ [Sukses]",
            "  📙 Voratoon       :       - komik  |  Refreshed: 2026-10-24 00:00:00  |  ❌ [Gagal: HTTP 403 Forbidden]",
        ]
        summary = build_stats_summary(
            lines,
            trigger_source="manual",
            source_filter="all",
            exit_status="0",
            completed_at="2026-10-24 00:00:00 UTC",
        )
        self.assertIn("## 📊 Source stats refresh summary", summary)
        self.assertIn("12,000", summary)
        self.assertIn("⚠️ Gagal", summary)

    def test_build_stats_summary_fallback_format(self):
        # Backward compatibility format
        lines = [
            "[SOURCE_STAT_ROW] komiku: count=12000 last_refreshed_at=2026-10-24T00:00:00 last_error=None",
            "[SOURCE_STAT_ROW] voratoon: count=None last_refreshed_at=None last_error=HTTPStatusError: 403",
        ]
        summary = build_stats_summary(
            lines,
            trigger_source="manual",
            source_filter="all",
            exit_status="0",
            completed_at="2026-10-24 00:00:00 UTC",
        )
        self.assertIn("12,000", summary)
        self.assertIn("⚠️ Gagal", summary)


    def test_resolve_path(self):
        from scraper.report_summary import resolve_path
        self.assertIsNone(resolve_path(None))
        self.assertIsNone(resolve_path(""))
        # Cek file yang ada di repo
        found = resolve_path("backend/scraper/report_summary.py") or resolve_path("scraper/report_summary.py")
        self.assertIsNotNone(found)


if __name__ == "__main__":
    unittest.main()

