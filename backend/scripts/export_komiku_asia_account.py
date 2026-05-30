"""
Export/import personal Komiku Asia account data.

The account pages on https://01.komiku.asia/user/history/ and
https://01.komiku.asia/user/bookmark/ render their lists from the official
member API at https://api.komiku.dev/api. The API requires the browser
localStorage value named `access_token` as a Bearer token. The `fpestid`
localStorage/cookie value is a browser fingerprint value and is not enough to
authenticate these API calls.

Usage:
    set KOMIKU_ASIA_ACCESS_TOKEN=<localStorage access_token>
    python -m scraper.export_komiku_asia_account export
    python -m scraper.export_komiku_asia_account import
"""

from __future__ import annotations

import argparse
import asyncio
from collections.abc import Iterable
from datetime import UTC, datetime
from getpass import getpass
import json
import logging
import math
import os
from pathlib import Path
import re
import sys
from typing import Any
import unicodedata
import uuid
import difflib

import httpx
from dotenv import load_dotenv
from sqlalchemy import case, func, select
from sqlalchemy.dialects.postgresql import insert

from app.database import async_session
from app.models import (
    Chapter,
    Comic,
    UserBookmark,
    UserCompletedChapter,
    UserHistoryEntry,
    UserProgress,
)
from scraper.utils import (
    CliLiveProgress,
    RealtimeConsoleHandler,
    backoff_delay,
    configure_external_loggers,
    configure_logging,
    format_elapsed_duration,
    random_delay,
)
from scraper.sources.common import ScraperCommonMixin

_COMMON_MIXIN = ScraperCommonMixin()

API_BASE_URL = "https://api.komiku.dev/api"
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "exports"
DEFAULT_TIMEOUT_SECONDS = 45.0
DEFAULT_RETRIES = 2
DEFAULT_LOG_FILE = Path("komiku_asia_account.log")
DEFAULT_SOURCE_NAME = "komiku_asia"
CHAPTER_NUMBER_TOLERANCE = 0.0001
SOURCE_SLUG_PREFIX_RE = re.compile(r"^\d{5,6}-")
API_RETRYABLE_STATUSES = {429, 500, 502, 503, 504}
DEFAULT_API_DELAY_MIN = 0.75
DEFAULT_API_DELAY_MAX = 1.75
DEFAULT_API_COOLDOWN_EVERY_PAGES = 12
DEFAULT_API_COOLDOWN_MIN = 8.0
DEFAULT_API_COOLDOWN_MAX = 16.0
DEFAULT_BACKOFF_MAX = 90.0
DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE = 5000
IMPORT_SCOPES = ("both", "bookmarks", "history")

logger = logging.getLogger("komiku-asia-account")


class KomikuAsiaAccountExportError(RuntimeError):
    """Raised when the Komiku Asia account export cannot continue."""


class KomikuAsiaAccountImportError(RuntimeError):
    """Raised when the Komiku Asia account import cannot continue."""


class KomikuAsiaAPIRequestError(KomikuAsiaAccountExportError):
    """Raised when a Komiku Asia API response is not successful."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        retry_after: float | None = None,
        payload: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.retry_after = retry_after
        self.payload = payload


def utc_now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def default_output_path() -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
    return DEFAULT_OUTPUT_DIR / f"komiku_asia_account_export_{timestamp}.json"


def default_import_summary_path() -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
    return DEFAULT_OUTPUT_DIR / f"komiku_asia_import_summary_{timestamp}.json"


def latest_export_path() -> Path | None:
    if not DEFAULT_OUTPUT_DIR.exists():
        return None
    exports = sorted(
        DEFAULT_OUTPUT_DIR.glob("komiku_asia_account_export*.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return exports[0] if exports else None


def detected_export_paths() -> list[Path]:
    if not DEFAULT_OUTPUT_DIR.exists():
        return []
    return sorted(
        DEFAULT_OUTPUT_DIR.glob("komiku_asia_account_export*.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def setup_cli_logging(log_file: str | Path | None) -> None:
    configure_logging(
        log_file,
        default_filename=DEFAULT_LOG_FILE,
        stdout_handler=RealtimeConsoleHandler(),
    )
    configure_external_loggers()
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


def bearer_headers(access_token: str) -> dict[str, str]:
    return {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
        "User-Agent": "Tonztoon-KomikuAsiaAccountExporter/1.0",
    }


def parse_retry_after(value: str | None) -> float | None:
    if not value:
        return None
    try:
        delay = float(value)
    except ValueError:
        return None
    return max(delay, 0.0)


def normalize_absolute_url(url: str | None) -> str | None:
    if not url:
        return None
    if url.startswith(("http://", "https://")):
        return url
    return f"https://01.komiku.asia/{url.lstrip('/')}"


def normalize_bookmark_item(item: dict[str, Any]) -> dict[str, Any]:
    latest = item.get("latest_chapter")
    if not isinstance(latest, dict):
        latest = {}

    return {
        "manga_id": item.get("manga_id") or item.get("id"),
        "title": item.get("title"),
        "slug": item.get("slug") or item.get("post_name"),
        "link": normalize_absolute_url(item.get("link")),
        "type": item.get("type"),
        "status": item.get("status"),
        "image": item.get("image"),
        "latest_chapter": {
            "chapter": latest.get("chapter"),
            "link": normalize_absolute_url(latest.get("link")),
        },
        "created_at": item.get("created_at"),
        "updated_at": item.get("updated_at"),
        "raw": item,
    }


def normalize_history_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": item.get("id"),
        "manga_id": item.get("manga_id"),
        "title": item.get("title"),
        "slug": item.get("slug"),
        "link": normalize_absolute_url(item.get("link") or item.get("slug")),
        "chapter": item.get("chapter"),
        "chapter_link": normalize_absolute_url(item.get("chapter_link")),
        "created_at": item.get("created_at"),
        "time": item.get("time"),
        "raw": item,
    }


def parse_results_payload(payload: dict[str, Any]) -> dict[str, Any]:
    results = payload.get("results")
    if not isinstance(results, dict):
        raise KomikuAsiaAccountExportError(
            f"Unexpected API response shape: missing object field 'results': {payload!r}"
        )
    data = results.get("data", [])
    if not isinstance(data, list):
        raise KomikuAsiaAccountExportError(
            f"Unexpected API response shape: 'results.data' is not a list: {payload!r}"
        )
    return results


async def get_json(
    client: httpx.AsyncClient,
    url: str,
    *,
    access_token: str,
) -> dict[str, Any]:
    response = await client.get(url, headers=bearer_headers(access_token))
    content_type = response.headers.get("content-type", "")
    if "application/json" not in content_type:
        raise KomikuAsiaAccountExportError(
            f"Expected JSON from {url}, got status={response.status_code} content-type={content_type}"
        )

    payload = response.json()
    if response.status_code == 401:
        raise KomikuAsiaAPIRequestError(
            "Komiku Asia API rejected the token. Use localStorage['access_token'], not fpestid.",
            status_code=response.status_code,
            payload=payload,
        )
    if response.status_code >= 400:
        retry_after = parse_retry_after(response.headers.get("retry-after"))
        raise KomikuAsiaAPIRequestError(
            f"Komiku Asia API request failed for {url}: status={response.status_code} payload={payload!r}",
            status_code=response.status_code,
            retry_after=retry_after,
            payload=payload,
        )
    return payload


async def get_json_with_retries(
    client: httpx.AsyncClient,
    url: str,
    *,
    access_token: str,
    retries: int,
    backoff_max: float,
) -> dict[str, Any]:
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            return await get_json(client, url, access_token=access_token)
        except KomikuAsiaAPIRequestError as exc:
            last_error = exc
            retryable = exc.status_code in API_RETRYABLE_STATUSES
            if attempt >= retries or not retryable:
                break
            if exc.retry_after is not None:
                logger.warning(
                    "API rate-limit status=%s untuk %s; mengikuti Retry-After %.1fs "
                    "(attempt %s/%s).",
                    exc.status_code,
                    url,
                    exc.retry_after,
                    attempt + 1,
                    retries + 1,
                )
                await asyncio.sleep(exc.retry_after)
            else:
                logger.warning(
                    "API retryable status=%s untuk %s (attempt %s/%s).",
                    exc.status_code,
                    url,
                    attempt + 1,
                    retries + 1,
                )
                await backoff_delay(
                    attempt,
                    f"retry API Komiku Asia status {exc.status_code}",
                    maximum=backoff_max,
                )
        except KomikuAsiaAccountExportError as exc:
            last_error = exc
            if attempt >= retries:
                break
            await backoff_delay(
                attempt,
                "retry API Komiku Asia",
                maximum=backoff_max,
            )
    raise last_error or KomikuAsiaAccountExportError(f"Request failed for {url}")


async def fetch_profile(
    client: httpx.AsyncClient,
    *,
    access_token: str,
    retries: int,
    backoff_max: float,
) -> dict[str, Any] | None:
    payload = await get_json_with_retries(
        client,
        f"{API_BASE_URL}/auth/profile",
        access_token=access_token,
        retries=retries,
        backoff_max=backoff_max,
    )
    if not payload.get("success"):
        return None
    user = payload.get("user")
    return user if isinstance(user, dict) else payload


async def fetch_paginated_collection(
    client: httpx.AsyncClient,
    endpoint: str,
    *,
    access_token: str,
    page_limit: int | None,
    retries: int,
    stop_on_error: bool,
    delay_min: float,
    delay_max: float,
    cooldown_every_pages: int,
    cooldown_min: float,
    cooldown_max: float,
    backoff_max: float,
    label: str | None = None,
) -> dict[str, Any]:
    first_url = endpoint if endpoint.startswith("http") else f"{API_BASE_URL}{endpoint}"
    progress_label = label or endpoint.strip("/") or "api"
    pages: list[dict[str, Any]] = []
    items: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    progress = CliLiveProgress(
        label=f"fetch {progress_label}",
        total_steps=1,
    )
    progress.start()

    async def fetch_page(url: str, page_number: int) -> dict[str, Any] | None:
        try:
            progress.set_detail(f"request page {page_number}")
            return await get_json_with_retries(
                client,
                url,
                access_token=access_token,
                retries=retries,
                backoff_max=backoff_max,
            )
        except KomikuAsiaAccountExportError as exc:
            error = {
                "page": page_number,
                "url": url,
                "error": str(exc),
            }
            errors.append(error)
            if stop_on_error:
                raise
            progress.set_detail(f"page {page_number} error, lanjut")
            return None

    try:
        first_payload = await fetch_page(first_url, 1)
        if first_payload is None:
            return {
                "count": 0,
                "reported_total": None,
                "items": [],
                "pages": [],
                "errors": errors,
                "incomplete": True,
                "truncated_by_page_limit": False,
            }

        def append_page(payload: dict[str, Any], url: str) -> dict[str, Any]:
            if not payload.get("success", False):
                raise KomikuAsiaAccountExportError(
                    f"Komiku Asia API returned success=false for {url}: {payload!r}"
                )

            results = parse_results_payload(payload)
            page_items = results.get("data", [])
            items.extend(page_items)
            pages.append(
                {
                    "url": url,
                    "current_page": results.get("current_page"),
                    "from": results.get("from"),
                    "to": results.get("to"),
                    "per_page": results.get("per_page"),
                    "total": results.get("total"),
                    "next_page_url": results.get("next_page_url"),
                    "prev_page_url": results.get("prev_page_url"),
                    "raw": payload,
                }
            )
            return results

        first_results = append_page(first_payload, first_url)
        reported_total = first_results.get("total")
        per_page = first_results.get("per_page") or len(first_results.get("data", []))
        last_page = first_results.get("last_page")
        if not isinstance(last_page, int) and isinstance(reported_total, int) and isinstance(per_page, int) and per_page > 0:
            last_page = math.ceil(reported_total / per_page)
        if not isinstance(last_page, int) or last_page < 1:
            last_page = 1

        requested_last_page = last_page
        if page_limit is not None:
            last_page = min(last_page, page_limit)

        progress.total_steps = max(last_page, 1)
        progress.current_step = 0
        progress.advance(f"page 1/{last_page}: {len(items)} item")
        logger.info(
            "Fetch %s page 1/%s selesai: %s item terkumpul.",
            progress_label,
            last_page,
            len(items),
        )

        for page_number in range(2, last_page + 1):
            if cooldown_every_pages > 0 and (page_number - 1) % cooldown_every_pages == 0:
                progress.set_detail(f"cooldown sebelum page {page_number}/{last_page}")
                await random_delay(
                    cooldown_min,
                    cooldown_max,
                    f"cooldown API {endpoint} page {page_number}",
                )
            elif delay_max > 0:
                progress.set_detail(f"delay sebelum page {page_number}/{last_page}")
                await random_delay(
                    delay_min,
                    delay_max,
                    f"delay API {endpoint} page {page_number}",
                )

            page_url = str(httpx.URL(first_url).copy_set_param("page", str(page_number)))
            payload = await fetch_page(page_url, page_number)
            if payload is None:
                progress.advance(f"page {page_number}/{last_page}: error")
                continue
            append_page(payload, page_url)
            progress.advance(f"page {page_number}/{last_page}: {len(items)} item")
            logger.info(
                "Fetch %s page %s/%s selesai: %s item terkumpul.",
                progress_label,
                page_number,
                last_page,
                len(items),
            )

        return {
            "count": len(items),
            "reported_total": reported_total,
            "items": items,
            "pages": pages,
            "errors": errors,
            "incomplete": bool(errors),
            "truncated_by_page_limit": page_limit is not None and page_limit < requested_last_page,
        }
    finally:
        await progress.stop()


async def export_account(args: argparse.Namespace) -> dict[str, Any]:
    if args.delay_min < 0 or args.delay_max < 0:
        raise KomikuAsiaAccountExportError("--delay-min/--delay-max tidak boleh negatif.")
    if args.delay_min > args.delay_max:
        raise KomikuAsiaAccountExportError("--delay-min tidak boleh lebih besar dari --delay-max.")
    if args.cooldown_min < 0 or args.cooldown_max < 0:
        raise KomikuAsiaAccountExportError("--cooldown-min/--cooldown-max tidak boleh negatif.")
    if args.cooldown_min > args.cooldown_max:
        raise KomikuAsiaAccountExportError(
            "--cooldown-min tidak boleh lebih besar dari --cooldown-max."
        )

    access_token = args.access_token or os.getenv("KOMIKU_ASIA_ACCESS_TOKEN")
    if not access_token:
        if os.getenv("KOMIKU_ASIA_FPESTID"):
            raise KomikuAsiaAccountExportError(
                "KOMIKU_ASIA_FPESTID is present, but this export needs KOMIKU_ASIA_ACCESS_TOKEN."
            )
        raise KomikuAsiaAccountExportError(
            "Missing access token. Set KOMIKU_ASIA_ACCESS_TOKEN from localStorage['access_token']."
        )

    timeout = httpx.Timeout(args.timeout)
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        profile = None
        if args.include_profile:
            profile = await fetch_profile(
                client,
                access_token=access_token,
                retries=args.retries,
                backoff_max=args.backoff_max,
            )

        bookmarks = await fetch_paginated_collection(
            client,
            "/bookmark",
            access_token=access_token,
            page_limit=args.page_limit,
            retries=args.retries,
            stop_on_error=args.stop_on_error,
            delay_min=args.delay_min,
            delay_max=args.delay_max,
            cooldown_every_pages=args.cooldown_every_pages,
            cooldown_min=args.cooldown_min,
            cooldown_max=args.cooldown_max,
            backoff_max=args.backoff_max,
            label="bookmark",
        )
        history = await fetch_paginated_collection(
            client,
            "/history",
            access_token=access_token,
            page_limit=args.page_limit,
            retries=args.retries,
            stop_on_error=args.stop_on_error,
            delay_min=args.delay_min,
            delay_max=args.delay_max,
            cooldown_every_pages=args.cooldown_every_pages,
            cooldown_min=args.cooldown_min,
            cooldown_max=args.cooldown_max,
            backoff_max=args.backoff_max,
            label="history",
        )

    return {
        "exported_at": utc_now_iso(),
        "source": "komiku_asia",
        "site_base_url": "https://01.komiku.asia",
        "api_base_url": API_BASE_URL,
        "auth_note": "Token redacted. Source token must be localStorage['access_token']; fpestid is not an API bearer token.",
        "profile": profile,
        "bookmarks": {
            **bookmarks,
            "items": [normalize_bookmark_item(item) for item in bookmarks["items"]],
        },
        "history": {
            **history,
            "items": [normalize_history_item(item) for item in history["items"]],
        },
    }


def load_export_payload(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise KomikuAsiaAccountImportError(f"File JSON tidak ditemukan: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise KomikuAsiaAccountImportError(f"File JSON tidak valid: {path}") from exc
    if not isinstance(payload, dict):
        raise KomikuAsiaAccountImportError("Root JSON harus berupa object.")
    return payload


def read_collection_items(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    section = payload.get(key, {})
    if not isinstance(section, dict):
        return []
    items = section.get("items", [])
    if not isinstance(items, list):
        return []
    return [item for item in items if isinstance(item, dict)]


def coerce_user_id(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(value.strip())
    except ValueError as exc:
        raise KomikuAsiaAccountImportError(
            "User ID harus berupa UUID Supabase/Auth user yang valid."
        ) from exc


def prompt_text(label: str, *, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{label}{suffix}: ").strip()
    return value or (default or "")


def prompt_yes_no(label: str, *, default: bool = False) -> bool:
    default_text = "Y/n" if default else "y/N"
    value = input(f"{label} [{default_text}]: ").strip().lower()
    if not value:
        return default
    return value in {"y", "yes", "ya", "iya", "1", "true"}


def prompt_import_scope() -> str:
    while True:
        print()
        print("Pilih data yang ingin diimport:")
        print("  1. Bookmark saja")
        print("  2. History saja")
        print("  3. Bookmark dan history")
        choice = prompt_text("Pilihan", default="3")
        if choice == "1":
            return "bookmarks"
        if choice == "2":
            return "history"
        if choice == "3":
            return "both"
        print("Pilihan tidak dikenal.")


def prompt_completed_chapters(scope: str) -> bool:
    if scope not in {"both", "history"}:
        return False
    print()
    print("Completed chapters:")
    print("- Jika aktif, chapter sebelum history/progress tertinggi per komik akan ditandai selesai.")
    print("- Chapter tertinggi itu sendiri tetap menjadi progress aktif dan tidak otomatis selesai.")
    return prompt_yes_no("Tandai chapter sebelum progress sebagai completed", default=False)


def choose_export_path() -> Path:
    exports = detected_export_paths()
    if not exports:
        value = prompt_text("Path file export JSON")
        if not value:
            raise KomikuAsiaAccountImportError("Path file export JSON wajib diisi.")
        return Path(value)

    print()
    print("File JSON export yang terdeteksi:")
    for index, path in enumerate(exports, start=1):
        stat = path.stat()
        modified = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        size_mb = stat.st_size / (1024 * 1024)
        print(f"  {index}. {path} ({size_mb:.2f} MB, {modified})")
    print("  0. Masukkan path lain")

    while True:
        choice = prompt_text("Pilih file JSON", default="1")
        if choice == "0":
            custom = prompt_text("Path file export JSON")
            if custom:
                return Path(custom)
            continue
        try:
            selected_index = int(choice)
        except ValueError:
            print("Pilihan harus berupa angka.")
            continue
        if 1 <= selected_index <= len(exports):
            return exports[selected_index - 1]
        print("Pilihan di luar daftar.")


def prompt_import_args(args: argparse.Namespace) -> argparse.Namespace:
    if args.file is None:
        args.file = choose_export_path()

    if args.scope in {"both", "history"} and not getattr(args, "use_completed_chapters", False):
        args.use_completed_chapters = prompt_completed_chapters(args.scope)

    if not args.user_id:
        args.user_id = prompt_text("Target user_id")
    if not args.user_id:
        raise KomikuAsiaAccountImportError("Target user_id wajib diisi.")

    return args


def extract_slug_from_link(link: str | None) -> str | None:
    if not link:
        return None
    cleaned = link.strip().rstrip("/")
    if not cleaned:
        return None
    return cleaned.split("/")[-1] or None


def strip_source_slug_prefix(slug: str | None) -> str | None:
    if not slug:
        return None
    stripped = SOURCE_SLUG_PREFIX_RE.sub("", slug.strip().strip("/"))
    return stripped or None


def slugify_text(text: str | None) -> str | None:
    if not text:
        return None
    normalized = unicodedata.normalize("NFKD", text)
    normalized = normalized.encode("ascii", "ignore").decode("ascii")
    normalized = normalized.lower().strip()
    normalized = re.sub(r"[^a-z0-9\s-]", "", normalized)
    normalized = re.sub(r"[\s-]+", "-", normalized)
    return normalized.strip("-") or None


def remove_chapter_suffix(text: str | None) -> str | None:
    if not text:
        return None
    return re.sub(
        r"\s+chapter\s+[0-9]+(?:[.\-][0-9]+)?\s*$",
        "",
        text.strip(),
        flags=re.IGNORECASE,
    ).strip() or None


def comic_slug_candidates(*values: str | None) -> list[str]:
    candidates: list[str] = []
    for value in values:
        if not value:
            continue
        raw = value.strip().strip("/")
        if not raw:
            continue
        stripped = strip_source_slug_prefix(raw)
        for candidate in (stripped, raw, slugify_text(raw)):
            if candidate and candidate not in candidates:
                candidates.append(candidate)
    return candidates


def bookmark_slug(item: dict[str, Any]) -> str | None:
    raw = item.get("raw") if isinstance(item.get("raw"), dict) else {}
    return (
        item.get("slug")
        or raw.get("slug")
        or raw.get("post_name")
        or extract_slug_from_link(item.get("link") or raw.get("link"))
    )


def bookmark_slug_candidates(item: dict[str, Any]) -> list[str]:
    raw = item.get("raw") if isinstance(item.get("raw"), dict) else {}
    primary_slug = bookmark_slug(item)
    return comic_slug_candidates(
        primary_slug,
        extract_slug_from_link(item.get("link") or raw.get("link")),
        slugify_text(item.get("title") or raw.get("title")),
    )


CHAPTER_SLUG_RE = re.compile(r"^(?P<comic_slug>.+)-chapter-(?P<chapter>[0-9]+(?:[.-][0-9]+)?)$")


def parse_history_selector(item: dict[str, Any]) -> dict[str, Any] | None:
    slug = item.get("slug") or extract_slug_from_link(item.get("link"))
    if not isinstance(slug, str):
        return None
        
    title = item.get("title")
    chapter_number_from_title = _COMMON_MIXIN._parse_chapter_number(title) if title else 0.0
        
    match = CHAPTER_SLUG_RE.match(slug.strip().rstrip("/"))
    if not match:
        return None
        
    if chapter_number_from_title > 0:
        chapter_number = chapter_number_from_title
    else:
        chapter_text = match.group("chapter").replace("-", ".")
        try:
            chapter_number = float(chapter_text)
        except ValueError:
            return None
            
    raw_comic_slug = match.group("comic_slug")
    title_slug = slugify_text(remove_chapter_suffix(item.get("title")))
    candidates = comic_slug_candidates(raw_comic_slug, title_slug)
    if not candidates:
        return None
    return {
        "comic_slug": candidates[0],
        "raw_comic_slug": raw_comic_slug,
        "slug_candidates": candidates,
        "chapter_number": chapter_number,
        "raw": item,
    }


def latest_history_per_comic(
    items: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    latest: dict[str, dict[str, Any]] = {}
    stats = {
        "parseable": 0,
        "unparseable": 0,
        "older_duplicate": 0,
    }
    for item in items:
        selector = parse_history_selector(item)
        if selector is None:
            stats["unparseable"] += 1
            continue
        stats["parseable"] += 1
        comic_slug = selector["comic_slug"]
        if comic_slug in latest:
            stats["older_duplicate"] += 1
            continue
        latest[comic_slug] = selector
    return list(latest.values()), stats


def build_import_summary() -> dict[str, Any]:
    return {
        "bookmarks": {
            "total": 0,
            "upserted": 0,
            "skipped_missing_slug": 0,
            "skipped_missing_comic": 0,
            "matched_by_canonical_slug": 0,
            "errors": [],
        },
        "history": {
            "total_raw": 0,
            "total_latest_per_comic": 0,
            "upserted": 0,
            "skipped_unparseable": 0,
            "skipped_older_duplicate": 0,
            "skipped_missing_comic_or_chapter": 0,
            "matched_by_canonical_slug": 0,
            "errors": [],
        },
        "completed_chapters": {
            "enabled": False,
            "candidate_total": 0,
            "upserted": 0,
            "chunk_size": DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE,
        },
    }


def unique_in_order(values: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(value for value in values if value))


def get_fuzzy_slug_match(requested_slug: str, all_slugs: list[str]) -> str | None:
    # Coba match persis
    if requested_slug in all_slugs:
        return requested_slug
        
    # Coba tanpa '-'
    requested_clean = requested_slug.replace("-", "")
    for s in all_slugs:
        if s.replace("-", "") == requested_clean:
            return s
            
    # Coba hilangkan artikel seperti "the", "a", "an", "of" etc
    def _strip_articles(text: str) -> str:
        return re.sub(r'-(the|a|an|of|in|to|and|or)-', '-', f"-{text}-").strip("-")
    
    requested_stripped = _strip_articles(requested_slug)
    for s in all_slugs:
        if _strip_articles(s) == requested_stripped:
            return s
            
    # Substring match (misal legend-of-northern-blade vs legend-of-the-northern-blade)
    # difflib memberikan toleransi typo/tambahan huruf (ratio >= 0.85)
    matches = difflib.get_close_matches(requested_slug, all_slugs, n=1, cutoff=0.8)
    if matches:
        return matches[0]
        
    return None

async def resolve_comic_ids_by_slug(db, source_name: str, slugs: list[str]) -> dict[str, int]:
    if not slugs:
        return {}
    
    all_comics_res = await db.execute(
        select(Comic.slug, Comic.id).where(Comic.source_name == source_name)
    )
    all_comics = dict(all_comics_res.all())
    all_slugs_list = list(all_comics.keys())
    
    resolved = {}
    for req_slug in slugs:
        matched = get_fuzzy_slug_match(req_slug, all_slugs_list)
        if matched:
            resolved[req_slug] = all_comics[matched]
            
    return resolved


async def resolve_history_chapters(
    db,
    source_name: str,
    history_items: list[dict[str, Any]],
) -> dict[tuple[str, float], tuple[int, int]]:
    slugs = unique_in_order(
        candidate
        for item in history_items
        for candidate in item["slug_candidates"]
    )
    if not slugs:
        return {}

    # Ambil semua chapter untuk source_name secara fuzzy
    # Supaya tidak OOM untuk source besar mungkin harusnya kita query comic id dari fuzzy
    all_comics_res = await db.execute(
        select(Comic.slug, Comic.id).where(Comic.source_name == source_name)
    )
    all_comics = dict(all_comics_res.all())
    all_slugs_list = list(all_comics.keys())
    
    # Kumpulkan semua komik yg perlu diambil chapterny
    matched_slug_to_id = {}
    requested_slug_to_db_slug = {}
    for req_slug in slugs:
        matched = get_fuzzy_slug_match(req_slug, all_slugs_list)
        if matched:
            matched_slug_to_id[matched] = all_comics[matched]
            requested_slug_to_db_slug[req_slug] = matched

    if not matched_slug_to_id:
        return {}

    result = await db.execute(
        select(Comic.slug, Comic.id, Chapter.id, Chapter.chapter_number)
        .join(Chapter, Chapter.comic_id == Comic.id)
        .where(
            Comic.source_name == source_name,
            Comic.slug.in_(list(matched_slug_to_id.keys())),
        )
    )

    requested = [
        (
            item["comic_slug"],
            item["chapter_number"],
            item["slug_candidates"],
        )
        for item in history_items
    ]
    requested_by_slug: dict[str, set[float]] = {}
    canonical_by_candidate: dict[tuple[str, float], tuple[str, float]] = {}
    for canonical_slug, chapter_number, candidates in requested:
        for candidate in candidates:
            # Petakan ke nama aslinya di DB jika fuzzy sukses
            mapped_db_slug = requested_slug_to_db_slug.get(candidate)
            if mapped_db_slug:
                requested_by_slug.setdefault(mapped_db_slug, set()).add(chapter_number)
                canonical_by_candidate[(mapped_db_slug, chapter_number)] = (canonical_slug, chapter_number)

    resolved: dict[tuple[str, float], tuple[int, int]] = {}
    for comic_slug_from_db, comic_id, chapter_id, chapter_number_from_db in result.all():
        for chapter_number in requested_by_slug.get(comic_slug_from_db, set()):
            if abs(chapter_number_from_db - chapter_number) <= CHAPTER_NUMBER_TOLERANCE:
                resolved[canonical_by_candidate[(comic_slug_from_db, chapter_number)]] = (
                    comic_id,
                    chapter_id,
                )
    return resolved


async def bulk_upsert_bookmarks(db, user_id: uuid.UUID, comic_ids: list[int]) -> None:
    if not comic_ids:
        return
    now = datetime.now(UTC)
    statement = (
        insert(UserBookmark)
        .values(
            [
                {
                    "user_id": user_id,
                    "comic_id": comic_id,
                    "updated_at": now,
                }
                for comic_id in comic_ids
            ]
        )
        .on_conflict_do_update(
            index_elements=[UserBookmark.user_id, UserBookmark.comic_id],
            set_={"updated_at": now},
        )
    )
    await db.execute(statement)


def chunked(values: list[dict[str, Any]], chunk_size: int) -> Iterable[list[dict[str, Any]]]:
    for start in range(0, len(values), chunk_size):
        yield values[start : start + chunk_size]


async def build_completed_chapter_values(
    db,
    user_id: uuid.UUID,
    rows: list[dict[str, Any]],
    completed_at: datetime,
) -> list[dict[str, Any]]:
    if not rows:
        return []

    latest_chapter_number_by_comic = {
        row["comic_id"]: row["chapter_number"]
        for row in rows
        if row.get("chapter_number") is not None
    }
    if not latest_chapter_number_by_comic:
        return []

    result = await db.execute(
        select(Chapter.id, Chapter.comic_id, Chapter.chapter_number).where(
            Chapter.comic_id.in_(list(latest_chapter_number_by_comic.keys()))
        )
    )

    values: list[dict[str, Any]] = []
    for chapter_id, comic_id, chapter_number in result.all():
        latest_chapter_number = latest_chapter_number_by_comic.get(comic_id)
        if latest_chapter_number is None:
            continue
        if chapter_number < latest_chapter_number - CHAPTER_NUMBER_TOLERANCE:
            values.append(
                {
                    "user_id": user_id,
                    "comic_id": comic_id,
                    "chapter_id": chapter_id,
                    "completed_at": completed_at,
                }
            )
    values.sort(key=lambda value: (value["comic_id"], value["chapter_id"]))
    return values


async def bulk_upsert_completed_chapters(
    db,
    values: list[dict[str, Any]],
    *,
    chunk_size: int,
) -> int:
    if not values:
        return 0
    if chunk_size < 1:
        raise KomikuAsiaAccountImportError("--completed-chunk-size harus lebih besar dari 0.")

    upserted = 0
    completed_insert = insert(UserCompletedChapter)
    for chunk in chunked(values, chunk_size):
        statement = (
            completed_insert.values(chunk)
            .on_conflict_do_update(
                index_elements=[
                    UserCompletedChapter.user_id,
                    UserCompletedChapter.comic_id,
                    UserCompletedChapter.chapter_id,
                ],
                set_={"completed_at": completed_insert.excluded.completed_at},
            )
        )
        await db.execute(statement)
        upserted += len(chunk)
    return upserted


async def bulk_upsert_history_progress(
    db,
    user_id: uuid.UUID,
    rows: list[dict[str, Any]],
) -> None:
    if not rows:
        return
    now = datetime.now(UTC)
    progress_values = [
        {
            "user_id": user_id,
            "comic_id": row["comic_id"],
            "chapter_id": row["chapter_id"],
            "reading_mode": row["reading_mode"],
            "scroll_offset": 0.0,
            "page_index": 0,
            "last_read_page_item_index": 0,
            "is_completed": False,
            "last_read_at": now,
            "updated_at": now,
        }
        for row in rows
    ]
    progress_insert = insert(UserProgress)
    same_progress_chapter = UserProgress.chapter_id == progress_insert.excluded.chapter_id
    progress_statement = (
        progress_insert.values(progress_values)
        .on_conflict_do_update(
            index_elements=[UserProgress.user_id, UserProgress.comic_id],
            set_={
                "chapter_id": progress_insert.excluded.chapter_id,
                "reading_mode": progress_insert.excluded.reading_mode,
                "scroll_offset": case(
                    (
                        same_progress_chapter,
                        func.coalesce(UserProgress.scroll_offset, 0.0),
                    ),
                    else_=progress_insert.excluded.scroll_offset,
                ),
                "page_index": case(
                    (same_progress_chapter, func.coalesce(UserProgress.page_index, 0)),
                    else_=progress_insert.excluded.page_index,
                ),
                "last_read_page_item_index": case(
                    (
                        same_progress_chapter,
                        func.coalesce(UserProgress.last_read_page_item_index, 0),
                    ),
                    else_=progress_insert.excluded.last_read_page_item_index,
                ),
                "total_page_items": None,
                "is_completed": False,
                "last_read_at": now,
                "updated_at": now,
            },
        )
    )

    history_values = [
        {
            "user_id": user_id,
            "comic_id": row["comic_id"],
            "chapter_id": row["chapter_id"],
            "reading_mode": row["reading_mode"],
            "scroll_offset": 0.0,
            "page_index": 0,
            "last_read_page_item_index": 0,
            "last_read_at": now,
            "updated_at": now,
        }
        for row in rows
    ]
    history_insert = insert(UserHistoryEntry)
    history_statement = (
        history_insert.values(history_values)
        .on_conflict_do_update(
            index_elements=[UserHistoryEntry.user_id, UserHistoryEntry.chapter_id],
            set_={
                "comic_id": history_insert.excluded.comic_id,
                "chapter_id": history_insert.excluded.chapter_id,
                "reading_mode": history_insert.excluded.reading_mode,
                "scroll_offset": func.coalesce(UserHistoryEntry.scroll_offset, 0.0),
                "page_index": func.coalesce(UserHistoryEntry.page_index, 0),
                "last_read_page_item_index": func.coalesce(
                    UserHistoryEntry.last_read_page_item_index,
                    0,
                ),
                "total_page_items": None,
                "last_read_at": now,
                "updated_at": now,
            },
        )
    )
    await db.execute(progress_statement)
    await db.execute(history_statement)


async def import_account(args: argparse.Namespace) -> dict[str, Any]:
    args = prompt_import_args(args) if args.interactive else args
    if args.file is None:
        raise KomikuAsiaAccountImportError("Path file export JSON wajib diisi.")
    if args.scope not in IMPORT_SCOPES:
        raise KomikuAsiaAccountImportError(
            f"Scope import tidak valid: {args.scope}. Pilih salah satu: {', '.join(IMPORT_SCOPES)}."
        )
    if getattr(args, "completed_chunk_size", DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE) < 1:
        raise KomikuAsiaAccountImportError("--completed-chunk-size harus lebih besar dari 0.")
    import_bookmarks = args.scope in {"both", "bookmarks"}
    import_history = args.scope in {"both", "history"}
    use_completed_chapters = bool(getattr(args, "use_completed_chapters", False) and import_history)
    user_id = coerce_user_id(args.user_id)
    payload = load_export_payload(args.file.expanduser())

    bookmark_items = read_collection_items(payload, "bookmarks") if import_bookmarks else []
    history_items = read_collection_items(payload, "history") if import_history else []
    history_latest, history_stats = latest_history_per_comic(history_items)

    summary = build_import_summary()
    summary["file"] = str(args.file)
    summary["user_id"] = str(user_id)
    summary["source_name"] = args.source_name
    summary["dry_run"] = args.dry_run
    summary["scope"] = args.scope
    summary["completed_chapters"]["enabled"] = use_completed_chapters
    summary["completed_chapters"]["chunk_size"] = getattr(
        args,
        "completed_chunk_size",
        DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE,
    )
    summary["bookmarks"]["total"] = len(bookmark_items)
    summary["history"]["total_raw"] = len(history_items)
    summary["history"]["total_latest_per_comic"] = len(history_latest)
    summary["history"]["skipped_unparseable"] = history_stats["unparseable"]
    summary["history"]["skipped_older_duplicate"] = history_stats["older_duplicate"]

    total_steps = (
        (2 if import_bookmarks else 0)
        + (2 if import_history else 0)
        + (1 if use_completed_chapters else 0)
        + 1
    )
    progress = CliLiveProgress(label="import Komiku Asia account", total_steps=max(total_steps, 1))
    progress.start()

    async with async_session() as db:
        bookmark_comic_ids: list[int] = []
        if import_bookmarks:
            progress.set_detail("matching bookmark comics")
            bookmark_entries = [
                {
                    "input_slug": bookmark_slug(item),
                    "slug_candidates": bookmark_slug_candidates(item),
                }
                for item in bookmark_items
            ]
            bookmark_slugs = unique_in_order(
                candidate
                for entry in bookmark_entries
                for candidate in entry["slug_candidates"]
            )
            bookmark_comic_ids_by_slug = await resolve_comic_ids_by_slug(
                db,
                args.source_name,
                bookmark_slugs,
            )
            progress.advance("bookmark comics matched")

            seen_bookmark_comic_ids: set[int] = set()
            for entry in bookmark_entries:
                input_slug = entry["input_slug"]
                candidates = entry["slug_candidates"]
                if not candidates:
                    summary["bookmarks"]["skipped_missing_slug"] += 1
                    continue

                matched_slug = next(
                    (candidate for candidate in candidates if candidate in bookmark_comic_ids_by_slug),
                    None,
                )
                if matched_slug is None:
                    summary["bookmarks"]["skipped_missing_comic"] += 1
                    summary["bookmarks"]["errors"].append(
                        {
                            "slug": input_slug,
                            "slug_candidates": candidates,
                            "error": (
                                f"Comic {args.source_name}/{input_slug} tidak ditemukan "
                                "dari semua kandidat slug."
                            ),
                        }
                    )
                    continue
                if matched_slug != input_slug:
                    summary["bookmarks"]["matched_by_canonical_slug"] += 1

                comic_id = bookmark_comic_ids_by_slug[matched_slug]
                if comic_id in seen_bookmark_comic_ids:
                    continue
                seen_bookmark_comic_ids.add(comic_id)
                bookmark_comic_ids.append(comic_id)

        history_rows: list[dict[str, Any]] = []
        if import_history:
            progress.set_detail("matching history chapters")
            history_chapters = await resolve_history_chapters(db, args.source_name, history_latest)
            progress.advance("history chapters matched")

            seen_history_comic_ids: set[int] = set()
            for item in history_latest:
                key = (item["comic_slug"], item["chapter_number"])
                resolved = history_chapters.get(key)
                if resolved is None:
                    summary["history"]["skipped_missing_comic_or_chapter"] += 1
                    summary["history"]["errors"].append(
                        {
                            "comic_slug": item["comic_slug"],
                            "raw_comic_slug": item["raw_comic_slug"],
                            "slug_candidates": item["slug_candidates"],
                            "chapter_number": item["chapter_number"],
                            "error": (
                                f"Chapter {item['chapter_number']} untuk "
                                f"{args.source_name}/{item['raw_comic_slug']} tidak ditemukan "
                                "dari semua kandidat slug."
                            ),
                        }
                    )
                    continue
                if item["comic_slug"] != item["raw_comic_slug"]:
                    summary["history"]["matched_by_canonical_slug"] += 1
                comic_id, chapter_id = resolved
                if comic_id in seen_history_comic_ids:
                    summary["history"]["skipped_older_duplicate"] += 1
                    continue
                seen_history_comic_ids.add(comic_id)
                history_rows.append(
                    {
                        "comic_id": comic_id,
                        "chapter_id": chapter_id,
                        "chapter_number": item["chapter_number"],
                        "reading_mode": args.reading_mode,
                    }
                )

        summary["bookmarks"]["upserted"] = len(bookmark_comic_ids)
        summary["history"]["upserted"] = len(history_rows)
        completed_chapter_values: list[dict[str, Any]] = []
        if use_completed_chapters:
            progress.set_detail("building completed chapter rows")
            completed_chapter_values = await build_completed_chapter_values(
                db,
                user_id,
                history_rows,
                datetime.now(UTC),
            )
            summary["completed_chapters"]["candidate_total"] = len(completed_chapter_values)
            progress.advance(
                f"completed chapter candidates: {len(completed_chapter_values)}"
            )

        progress.set_detail("writing database rows" if not args.dry_run else "dry-run complete")
        if not args.dry_run:
            if import_bookmarks:
                await bulk_upsert_bookmarks(db, user_id, bookmark_comic_ids)
            if import_history:
                await bulk_upsert_history_progress(db, user_id, history_rows)
            if use_completed_chapters:
                completed_upserted = await bulk_upsert_completed_chapters(
                    db,
                    completed_chapter_values,
                    chunk_size=summary["completed_chapters"]["chunk_size"],
                )
                summary["completed_chapters"]["upserted"] = completed_upserted
            await db.commit()
        progress.advance("database phase complete")

    progress.advance("summary ready")
    await progress.stop()
    return summary


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--log-file",
        type=Path,
        default=DEFAULT_LOG_FILE,
        help="Path log relatif ke backend/logs kecuali absolut.",
    )


def print_script_intro() -> None:
    print()
    print("Komiku Asia Account Tool")
    print("=" * 24)
    print("Scrape bookmark/history dari API resmi Komiku Asia ke JSON,")
    print("atau import JSON tersebut ke user library Tonztoon lokal.")
    print()
    print("Catatan:")
    print("- Scrape membutuhkan localStorage['access_token'] dari akun Komiku Asia.")
    print("- Import membutuhkan target user_id UUID dari akun Tonztoon/Supabase.")
    print("- Detail log ditulis ke backend/logs/komiku_asia_account.log.")
    print()


def prompt_menu_action() -> str:
    while True:
        print("Pilih tindakan:")
        print("  1. Scrape data akun Komiku Asia ke JSON")
        print("  2. Import data dari JSON ke user Tonztoon")
        print("  0. Keluar")
        choice = prompt_text("Pilihan", default="1")
        if choice == "1":
            return "export"
        if choice == "2":
            return "import"
        if choice == "0":
            return "exit"
        print("Pilihan tidak dikenal.")


def build_interactive_export_args() -> argparse.Namespace:
    access_token = os.getenv("KOMIKU_ASIA_ACCESS_TOKEN")
    if not access_token:
        print()
        print("Masukkan access_token Komiku Asia.")
        print("Token tidak akan disimpan ke file konfigurasi.")
        access_token = getpass("access_token: ").strip()

    output_text = prompt_text("Output JSON", default=str(default_output_path()))
    return argparse.Namespace(
        command="export",
        log_file=DEFAULT_LOG_FILE,
        access_token=access_token or None,
        output=Path(output_text),
        page_limit=None,
        timeout=DEFAULT_TIMEOUT_SECONDS,
        retries=DEFAULT_RETRIES,
        delay_min=DEFAULT_API_DELAY_MIN,
        delay_max=DEFAULT_API_DELAY_MAX,
        cooldown_every_pages=DEFAULT_API_COOLDOWN_EVERY_PAGES,
        cooldown_min=DEFAULT_API_COOLDOWN_MIN,
        cooldown_max=DEFAULT_API_COOLDOWN_MAX,
        backoff_max=DEFAULT_BACKOFF_MAX,
        stop_on_error=False,
        include_profile=True,
    )


def build_interactive_import_args() -> argparse.Namespace:
    file_path = choose_export_path()
    scope = prompt_import_scope()
    use_completed_chapters = prompt_completed_chapters(scope)
    user_id = prompt_text("Target user_id UUID")
    dry_run = prompt_yes_no("Jalankan dry-run dulu", default=True)
    return argparse.Namespace(
        command="import",
        log_file=DEFAULT_LOG_FILE,
        file=file_path,
        user_id=user_id,
        scope=scope,
        source_name=DEFAULT_SOURCE_NAME,
        reading_mode="vertical",
        use_completed_chapters=use_completed_chapters,
        completed_chunk_size=DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE,
        dry_run=dry_run,
        summary_output=default_import_summary_path(),
        yes=True,
        interactive=False,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    if not raw_argv:
        return argparse.Namespace(command="menu", log_file=DEFAULT_LOG_FILE)
    if raw_argv[0].startswith("-"):
        raw_argv.insert(0, "export")

    parser = argparse.ArgumentParser(
        description="Export/import Komiku Asia account bookmarks and history."
    )
    subparsers = parser.add_subparsers(dest="command")

    export_parser = subparsers.add_parser(
        "export",
        aliases=["scrape"],
        help="Export Komiku Asia API bookmark/history ke JSON.",
    )
    add_common_arguments(export_parser)
    export_parser.add_argument(
        "--access-token",
        help="Komiku Asia API token from browser localStorage['access_token']. Prefer env KOMIKU_ASIA_ACCESS_TOKEN.",
    )
    export_parser.add_argument(
        "--output",
        type=Path,
        default=default_output_path(),
        help="Output JSON path. Defaults to backend/exports/komiku_asia_account_export_<timestamp>.json.",
    )
    export_parser.add_argument(
        "--page-limit",
        type=int,
        default=None,
        help="Optional maximum number of API pages to fetch per collection.",
    )
    export_parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help="HTTP timeout in seconds.",
    )
    export_parser.add_argument(
        "--retries",
        type=int,
        default=DEFAULT_RETRIES,
        help="Retries per API page before recording an error.",
    )
    export_parser.add_argument(
        "--delay-min",
        type=float,
        default=DEFAULT_API_DELAY_MIN,
        help="Delay acak minimum antar halaman API.",
    )
    export_parser.add_argument(
        "--delay-max",
        type=float,
        default=DEFAULT_API_DELAY_MAX,
        help="Delay acak maksimum antar halaman API.",
    )
    export_parser.add_argument(
        "--cooldown-every-pages",
        type=int,
        default=DEFAULT_API_COOLDOWN_EVERY_PAGES,
        help="Cooldown berkala setiap N halaman API. 0 untuk nonaktif.",
    )
    export_parser.add_argument(
        "--cooldown-min",
        type=float,
        default=DEFAULT_API_COOLDOWN_MIN,
        help="Cooldown acak minimum saat jeda berkala API.",
    )
    export_parser.add_argument(
        "--cooldown-max",
        type=float,
        default=DEFAULT_API_COOLDOWN_MAX,
        help="Cooldown acak maksimum saat jeda berkala API.",
    )
    export_parser.add_argument(
        "--backoff-max",
        type=float,
        default=DEFAULT_BACKOFF_MAX,
        help="Batas maksimum exponential backoff saat API rate-limit/error.",
    )
    export_parser.add_argument(
        "--stop-on-error",
        action="store_true",
        help="Abort on the first failed paginated API request instead of writing a partial export.",
    )
    export_parser.add_argument(
        "--skip-profile",
        action="store_false",
        dest="include_profile",
        help="Do not call /auth/profile before exporting bookmark/history.",
    )
    export_parser.set_defaults(include_profile=True)

    import_parser = subparsers.add_parser(
        "import",
        help="Import bookmark/history dari JSON export ke user lokal.",
    )
    add_common_arguments(import_parser)
    import_parser.add_argument(
        "--file",
        type=Path,
        default=None,
        help="Path JSON export. Jika kosong pada mode interaktif, memakai export terbaru.",
    )
    import_parser.add_argument(
        "--user-id",
        default=None,
        help="Target user_id UUID. Jika kosong pada mode interaktif, akan diminta lewat input.",
    )
    import_parser.add_argument(
        "--scope",
        choices=IMPORT_SCOPES,
        default="both",
        help="Data yang diimport: bookmarks, history, atau both.",
    )
    import_parser.add_argument(
        "--source-name",
        default=DEFAULT_SOURCE_NAME,
        help="Source lokal target untuk matching comic/chapter.",
    )
    import_parser.add_argument(
        "--reading-mode",
        default="vertical",
        choices=("vertical", "paged"),
        help="Reading mode default untuk progress/history yang diimpor.",
    )
    import_parser.add_argument(
        "--use-completed-chapters",
        action="store_true",
        help=(
            "Saat import history, tandai semua chapter sebelum chapter progress "
            "tertinggi per komik sebagai completed."
        ),
    )
    import_parser.add_argument(
        "--completed-chunk-size",
        type=int,
        default=DEFAULT_COMPLETED_CHAPTER_CHUNK_SIZE,
        help=(
            "Jumlah row user_completed_chapters per batch insert/update. "
            "Dibuat kecil agar tidak melewati limit parameter PostgreSQL."
        ),
    )
    import_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validasi/matching tanpa menulis ke database.",
    )
    import_parser.add_argument(
        "--summary-output",
        type=Path,
        default=default_import_summary_path(),
        help="Path detail summary import JSON.",
    )
    import_parser.add_argument(
        "--yes",
        action="store_true",
        help="Non-interactive. Wajib menyertakan --file dan --user-id.",
    )

    parser.set_defaults(command="export")
    return parser.parse_args(raw_argv)


async def async_main(argv: list[str] | None = None) -> None:
    load_dotenv()
    args = parse_args(argv)
    setup_cli_logging(args.log_file)
    started_at = datetime.now(UTC)

    if args.command == "menu":
        print_script_intro()
        action = prompt_menu_action()
        if action == "exit":
            print("Selesai.")
            return
        args = (
            build_interactive_export_args()
            if action == "export"
            else build_interactive_import_args()
        )
        started_at = datetime.now(UTC)

    if args.command == "import":
        args.interactive = not args.yes
        logger.info("Mulai import Komiku Asia account dari JSON.")
        summary = await import_account(args)
        elapsed = (datetime.now(UTC) - started_at).total_seconds()
        summary_path = args.summary_output.expanduser()
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        summary_path.write_text(
            json.dumps(summary, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        logger.info("Import selesai dalam %s.", format_elapsed_duration(elapsed))
        logger.info(
            "Summary: bookmarks=%s/%s history=%s/%s completed=%s/%s enabled=%s dry_run=%s detail=%s",
            summary["bookmarks"]["upserted"],
            summary["bookmarks"]["total"],
            summary["history"]["upserted"],
            summary["history"]["total_latest_per_comic"],
            summary["completed_chapters"]["upserted"],
            summary["completed_chapters"]["candidate_total"],
            summary["completed_chapters"]["enabled"],
            summary["dry_run"],
            summary_path,
        )
        print(f"Import {'dry-run ' if args.dry_run else ''}selesai.")
        print(
            "Bookmarks: "
            f"{summary['bookmarks']['upserted']}/{summary['bookmarks']['total']} matched"
        )
        print(
            "History: "
            f"{summary['history']['upserted']}/{summary['history']['total_latest_per_comic']} latest-per-comic matched"
        )
        if summary["completed_chapters"]["enabled"]:
            completed_label = "would upsert" if summary["dry_run"] else "upserted"
            completed_value = (
                summary["completed_chapters"]["candidate_total"]
                if summary["dry_run"]
                else summary["completed_chapters"]["upserted"]
            )
            print(
                "Completed chapters: "
                f"{completed_value}/{summary['completed_chapters']['candidate_total']} {completed_label}"
            )
        print(f"Detail summary: {summary_path}")
        return

    logger.info("Mulai export Komiku Asia account dari API resmi.")
    payload = await export_account(args)
    output_path = args.output.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    elapsed = (datetime.now(UTC) - started_at).total_seconds()

    logger.info("Export selesai dalam %s.", format_elapsed_duration(elapsed))
    logger.info("Output: %s", output_path)
    logger.info(
        "Summary: bookmarks=%s/%s history=%s/%s",
        payload["bookmarks"]["count"],
        payload["bookmarks"].get("reported_total"),
        payload["history"]["count"],
        payload["history"].get("reported_total"),
    )

    print(f"Exported Komiku Asia account data to {output_path}")
    print(f"Bookmarks: {payload['bookmarks']['count']}")
    print(f"History: {payload['history']['count']}")


def main() -> None:
    import asyncio

    try:
        asyncio.run(async_main())
    except (KomikuAsiaAccountExportError, KomikuAsiaAccountImportError) as exc:
        raise SystemExit(f"Komiku Asia account script failed: {exc}") from exc


if __name__ == "__main__":
    main()
