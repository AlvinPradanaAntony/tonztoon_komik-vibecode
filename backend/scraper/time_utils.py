"""Utility helper untuk timestamp scraper yang konsisten di GMT+7 (WIB)."""

from datetime import datetime, timedelta, timezone

TZ_WIB = timezone(timedelta(hours=7))


def now_wib() -> datetime:
    """Return current timezone-aware datetime in GMT+7 / WIB."""
    return datetime.now(TZ_WIB)
