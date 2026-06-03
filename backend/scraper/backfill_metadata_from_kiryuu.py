"""
Backfill metadata komik existing dari Kiryuu sebagai source cadangan.

Kiryuu tidak dimasukkan ke pipeline ingest utama dan tidak membuat row comic
baru di DB. Script ini melakukan live-scrape lokal, mencocokkan komik existing
berdasarkan slug/judul, lalu mengisi metadata yang masih kosong.

Usage:
    python -m scraper.backfill_metadata_from_kiryuu --overview --fields rating
    python -m scraper.backfill_metadata_from_kiryuu --compare-values --source komikcast --fields total_view --limit 20
    python -m scraper.backfill_metadata_from_kiryuu --dry-run --limit 50
    python -m scraper.backfill_metadata_from_kiryuu --source komikcast,shinigami
    python -m scraper.backfill_metadata_from_kiryuu --fields status,type,rating,author,artist
    python -m scraper.backfill_metadata_from_kiryuu --with-genres
    python -m scraper.backfill_metadata_from_kiryuu --overwrite --limit 25
    python -m scraper.backfill_metadata_from_kiryuu --reset --limit 25
"""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import asdict, dataclass, field
from difflib import SequenceMatcher
import json
import logging
import re
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any

from sqlalchemy import case, func, or_, select, update
from sqlalchemy.orm import noload, selectinload

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import async_session
from app.models import Comic

from scraper.db_ops import sync_comic_genres
from scraper.sources.registry import (
    create_backup_scraper,
    get_backup_source_names,
    get_supported_source_names,
)
from scraper.time_utils import now_wib
from scraper.utils import (
    configure_external_loggers,
    configure_logging as _configure_logging_base,
    format_elapsed_duration,
    GracefulShutdown,
    resolve_log_path,
)

DEFAULT_LOG_FILE = Path("backfill_metadata_from_kiryuu.log")
BACKUP_SOURCE_NAME = "kiryuu"
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "checkpoints"
DEFAULT_FIELDS = (
    "alternative_titles",
    "cover_image_url",
    "author",
    "artist",
    "status",
    "type",
    "synopsis",
    "rating",
    "total_view",
)
SUPPORTED_FIELDS = frozenset(DEFAULT_FIELDS)
STRING_FIELDS = frozenset(
    (
        "alternative_titles",
        "cover_image_url",
        "author",
        "artist",
        "status",
        "type",
        "synopsis",
    )
)
TITLE_STOPWORDS = frozenset({"a", "an", "the"})
PARTIAL_QUERY_MIN_TOKENS = 2
PARTIAL_QUERY_MAX_TOKENS = 4
MAX_SEARCH_QUERIES_PER_COMIC = 6
HIGH_CONFIDENCE_MATCH_SCORE = 90

logger = logging.getLogger("scraper.backfill.kiryuu")
_shutdown = GracefulShutdown()
_shutdown.install()


@dataclass
class BackfillStats:
    scanned: int = 0
    need_metadata: int = 0
    matched: int = 0
    updated: int = 0
    genre_updated: int = 0
    dry_run_updates: int = 0
    skipped_no_match: int = 0
    skipped_no_values: int = 0
    skipped_no_need: int = 0
    errors: int = 0
    updated_fields: dict[str, int] = field(default_factory=dict)

    def record_fields(self, fields: list[str]) -> None:
        for field_name in fields:
            self.updated_fields[field_name] = self.updated_fields.get(field_name, 0) + 1

    @classmethod
    def from_checkpoint(cls, payload: dict[str, Any] | None) -> "BackfillStats":
        if not payload:
            return cls()
        supported = {field.name for field in cls.__dataclass_fields__.values()}
        values = {key: value for key, value in payload.items() if key in supported}
        values["updated_fields"] = dict(values.get("updated_fields") or {})
        return cls(**values)


@dataclass
class CompareStats:
    scanned: int = 0
    matched: int = 0
    same: int = 0
    different: int = 0
    db_missing_kiryuu_available: int = 0
    kiryuu_missing: int = 0
    db_greater: int = 0
    kiryuu_greater: int = 0
    textual_difference: int = 0
    no_match: int = 0
    errors: int = 0


def configure_logging(log_file: str | None = None) -> None:
    _configure_logging_base(log_file, default_filename=str(DEFAULT_LOG_FILE))
    configure_external_loggers()


def _checkpoint_scope(
    *,
    source_names: list[str] | None,
    fields: set[str],
    dry_run: bool,
    overwrite: bool,
    with_genres: bool,
) -> str:
    sources = "-".join(sorted(source_names or ["all"]))
    field_scope = "-".join(sorted(fields))
    mode_parts = ["dry-run" if dry_run else "update"]
    if overwrite:
        mode_parts.append("overwrite")
    if with_genres:
        mode_parts.append("genres")
    raw_scope = f"{sources}_{field_scope}_{'_'.join(mode_parts)}"
    return re.sub(r"[^a-z0-9_.-]+", "-", raw_scope.lower()).strip("-") or "default"


def get_checkpoint_file(scope: str) -> Path:
    return CHECKPOINT_DIR / f"backfill_metadata_from_kiryuu_{scope}.json"


def _default_progress() -> dict[str, Any]:
    return {
        "last_processed_comic_id": 0,
        "current_comic_id": 0,
        "current_comic_position": 0,
        "current_comic_total": 0,
        "current_source_name": None,
        "current_slug": None,
        "current_title": None,
        "state": "idle",
        "note": None,
    }


def _default_checkpoint(scope: str) -> dict[str, Any]:
    return {
        "scope": scope,
        "updated_at": None,
        "stats": asdict(BackfillStats()),
        "progress": _default_progress(),
    }


def _normalize_checkpoint(data: dict[str, Any] | None, *, scope: str) -> dict[str, Any]:
    checkpoint = data or {}
    if checkpoint.get("scope") and checkpoint.get("scope") != scope:
        return _default_checkpoint(scope)

    checkpoint.setdefault("scope", scope)
    checkpoint.setdefault("updated_at", None)
    default_stats = asdict(BackfillStats())
    stats = checkpoint.setdefault("stats", default_stats.copy())
    for key, value in default_stats.items():
        stats.setdefault(key, value)
    stats["updated_fields"] = dict(stats.get("updated_fields") or {})

    default_progress = _default_progress()
    progress = checkpoint.setdefault("progress", default_progress.copy())
    for key, value in default_progress.items():
        progress.setdefault(key, value)
    return checkpoint


def load_checkpoint(scope: str) -> dict[str, Any]:
    checkpoint_file = get_checkpoint_file(scope)
    if not checkpoint_file.exists():
        return _default_checkpoint(scope)
    try:
        with open(checkpoint_file, "r", encoding="utf-8") as f:
            checkpoint = _normalize_checkpoint(json.load(f), scope=scope)
        progress = checkpoint.get("progress", {})
        logger.info("Checkpoint ditemukan: %s", checkpoint_file)
        logger.info(
            "Resume dari comic_id > %s (state=%s)",
            progress.get("last_processed_comic_id", 0),
            progress.get("state", "unknown"),
        )
        return checkpoint
    except Exception as exc:
        logger.warning("Checkpoint rusak, mulai baru: %s", exc)
        return _default_checkpoint(scope)


def save_checkpoint(scope: str, checkpoint: dict[str, Any]) -> None:
    checkpoint_file = get_checkpoint_file(scope)
    checkpoint["updated_at"] = now_wib().isoformat()
    checkpoint_file.parent.mkdir(parents=True, exist_ok=True)
    with open(checkpoint_file, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)


def reset_checkpoint(scope: str) -> None:
    checkpoint_file = get_checkpoint_file(scope)
    if checkpoint_file.exists():
        checkpoint_file.unlink()
        logger.info("Checkpoint dihapus: %s", checkpoint_file)


def update_progress(
    checkpoint: dict[str, Any],
    *,
    last_processed_comic_id: int | None = None,
    current_comic_id: int | None = None,
    current_comic_position: int | None = None,
    current_comic_total: int | None = None,
    current_source_name: str | None = None,
    current_slug: str | None = None,
    current_title: str | None = None,
    state: str | None = None,
    note: str | None = None,
) -> None:
    progress = checkpoint.setdefault("progress", _default_progress())
    updates = {
        "last_processed_comic_id": last_processed_comic_id,
        "current_comic_id": current_comic_id,
        "current_comic_position": current_comic_position,
        "current_comic_total": current_comic_total,
        "current_source_name": current_source_name,
        "current_slug": current_slug,
        "current_title": current_title,
        "state": state,
        "note": note,
    }
    for key, value in updates.items():
        if value is not None:
            progress[key] = value


def persist_backfill_checkpoint(
    scope: str,
    checkpoint: dict[str, Any],
    stats: BackfillStats,
    **progress_kwargs,
) -> None:
    update_progress(checkpoint, **progress_kwargs)
    checkpoint["stats"] = asdict(stats)
    save_checkpoint(scope, checkpoint)


def _normalize_slug(value: str | None) -> str:
    cleaned = (value or "").strip().lower()
    cleaned = re.sub(r"[^a-z0-9]+", "-", cleaned)
    return cleaned.strip("-")


def _fold_ascii_text(value: str | None) -> str:
    text = str(value or "")
    text = text.replace("’", "'").replace("‘", "'").replace("`", "'").replace("´", "'")
    text = unicodedata.normalize("NFKD", text)
    return text.encode("ascii", errors="ignore").decode("ascii").lower()


def _normalize_title(value: str | None) -> str:
    cleaned = _fold_ascii_text(value).strip()
    cleaned = re.sub(r"[^a-z0-9]+", " ", cleaned)
    return re.sub(r"\s+", " ", cleaned).strip()


def _compact_title(value: str | None) -> str:
    return re.sub(r"\s+", "", _normalize_title(value))


def _normalize_title_without_stopwords(value: str | None) -> str:
    tokens = [
        token
        for token in _normalize_title(value).split()
        if token not in TITLE_STOPWORDS
    ]
    return " ".join(tokens)


def _compact_title_without_stopwords(value: str | None) -> str:
    return re.sub(r"\s+", "", _normalize_title_without_stopwords(value))


def _slug_as_title(value: str | None) -> str:
    return _normalize_title(_normalize_slug(value).replace("-", " "))


def _compact_slug(value: str | None) -> str:
    return _compact_title(_slug_as_title(value))


def _title_tokens(value: str | None) -> set[str]:
    return {
        token
        for token in _normalize_title(value).split()
        if len(token) > 1 or token.isdigit()
    }


def _title_token_list(value: str | None) -> list[str]:
    return [
        token
        for token in _normalize_title(value).split()
        if len(token) > 1 or token.isdigit()
    ]


def _trigrams(value: str | None) -> set[str]:
    compact = _compact_title_without_stopwords(value)
    if not compact:
        return set()
    if len(compact) <= 3:
        return {compact}
    return {compact[index : index + 3] for index in range(len(compact) - 2)}


def _trigram_similarity(left: str | None, right: str | None) -> float:
    left_trigrams = _trigrams(left)
    right_trigrams = _trigrams(right)
    if not left_trigrams or not right_trigrams:
        return 0.0
    return len(left_trigrams & right_trigrams) / len(left_trigrams | right_trigrams)


def _trigram_containment(left: str | None, right: str | None) -> float:
    left_trigrams = _trigrams(left)
    right_trigrams = _trigrams(right)
    if not left_trigrams or not right_trigrams:
        return 0.0
    return len(left_trigrams & right_trigrams) / min(len(left_trigrams), len(right_trigrams))


def _split_title_candidates(comic: Comic) -> set[str]:
    titles = {_normalize_title(comic.title), _slug_as_title(comic.slug)}
    for raw in re.split(r"[,;/|]", comic.alternative_titles or ""):
        normalized = _normalize_title(raw)
        if normalized:
            titles.add(normalized)
    return {title for title in titles if title}


def _clean_query_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip())


def _query_variants(value: str | None) -> list[str]:
    raw = _clean_query_text(value)
    folded = _clean_query_text(_fold_ascii_text(raw))
    variants = [
        raw,
        folded,
        folded.replace("-", " "),
        folded.replace("-", ""),
        _normalize_title(raw),
    ]

    if folded:
        variants.append(re.sub(r"([a-z0-9]+)-([a-z0-9]+'s\b)", r"\1\2", folded))

    tokens = _normalize_title(raw).split()
    for index, token in enumerate(tokens):
        if token != "s" or index == 0:
            continue
        variants.append(" ".join([*tokens[: index - 1], f"{tokens[index - 1]}'s", *tokens[index + 1 :]]))
        if index >= 2:
            variants.append(
                " ".join(
                    [
                        *tokens[: index - 2],
                        f"{tokens[index - 2]}{tokens[index - 1]}'s",
                        *tokens[index + 1 :],
                    ]
                )
            )

    seen: set[str] = set()
    cleaned_variants: list[str] = []
    for variant in variants:
        cleaned = _clean_query_text(variant)
        dedupe_key = cleaned.lower()
        if not cleaned or dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        cleaned_variants.append(cleaned)
    return cleaned_variants


def _partial_query_variants(value: str | None) -> list[str]:
    tokens = _title_token_list(value)
    if len(tokens) < PARTIAL_QUERY_MIN_TOKENS:
        return []

    variants: list[str] = []
    max_tokens = min(len(tokens), PARTIAL_QUERY_MAX_TOKENS)
    for length in range(PARTIAL_QUERY_MIN_TOKENS, max_tokens + 1):
        variants.append(" ".join(tokens[:length]))

    content_tokens = [token for token in tokens if token not in TITLE_STOPWORDS]
    content_max = min(len(content_tokens), PARTIAL_QUERY_MAX_TOKENS)
    for length in range(PARTIAL_QUERY_MIN_TOKENS, content_max + 1):
        variants.append(" ".join(content_tokens[:length]))

    return variants


def _iter_search_queries(comic: Comic) -> list[str]:
    raw_queries = [comic.title]
    raw_queries.extend(re.split(r"[,;/|]", comic.alternative_titles or ""))

    seen: set[str] = set()
    queries: list[str] = []
    for raw in raw_queries:
        query_variants = _query_variants(raw)
        ordered_variants = [
            *query_variants[:2],
            *_partial_query_variants(raw),
            *query_variants[2:],
        ]
        for query in ordered_variants:
            dedupe_key = query.lower()
            if not query or dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            queries.append(query)
            if len(queries) >= MAX_SEARCH_QUERIES_PER_COMIC:
                return queries
    return queries


def _title_similarity(left: str | None, right: str | None) -> float:
    left_normalized = _normalize_title(left)
    right_normalized = _normalize_title(right)
    if not left_normalized or not right_normalized:
        return 0.0

    left_compact = _compact_title(left_normalized)
    right_compact = _compact_title(right_normalized)
    compact_ratio = SequenceMatcher(None, left_compact, right_compact).ratio()
    spaced_ratio = SequenceMatcher(None, left_normalized, right_normalized).ratio()
    stopword_ratio = SequenceMatcher(
        None,
        _compact_title_without_stopwords(left_normalized),
        _compact_title_without_stopwords(right_normalized),
    ).ratio()

    left_tokens = _title_tokens(left_normalized)
    right_tokens = _title_tokens(right_normalized)
    token_ratio = 0.0
    if left_tokens and right_tokens:
        token_ratio = len(left_tokens & right_tokens) / len(left_tokens | right_tokens)

    return max(
        compact_ratio,
        spaced_ratio,
        stopword_ratio,
        token_ratio,
        _trigram_similarity(left_normalized, right_normalized),
        _trigram_containment(left_normalized, right_normalized),
    )


def _is_empty(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    return False


def _safe_display(value: Any, *, max_length: int = 80) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    if len(text) > max_length:
        text = f"{text[: max_length - 3]}..."
    return text.encode("ascii", errors="backslashreplace").decode("ascii")


def _log_comic_separator(label: str, title: str | None) -> None:
    logger.info("")
    logger.info("-" * 60)
    logger.info("%s %s", label, _safe_display(title, max_length=120))


def _log_match_found(label: str, payload: dict[str, Any]) -> None:
    logger.info(
        "✅ %s cocok Kiryuu: %s | title=%s",
        label,
        payload.get("source_url"),
        _safe_display(payload.get("title"), max_length=120),
    )


def _log_match_missing(label: str) -> None:
    logger.info("❌ %s tidak ditemukan di Kiryuu", label)


def _parse_csv(value: str | None) -> list[str]:
    return [item.strip().lower() for item in (value or "").split(",") if item.strip()]


def _parse_fields(value: str | None) -> set[str]:
    fields = set(_parse_csv(value) or DEFAULT_FIELDS)

    unknown = sorted(fields - SUPPORTED_FIELDS)
    if unknown:
        raise ValueError(
            f"Field tidak didukung: {', '.join(unknown)}. "
            f"Gunakan salah satu dari: {', '.join(sorted(SUPPORTED_FIELDS))}"
        )
    return fields


def _field_needs_update(comic: Comic, field_name: str, *, overwrite: bool) -> bool:
    current_value = getattr(comic, field_name)
    return overwrite or _is_empty(current_value)


def _genres_need_sync(comic: Comic, *, overwrite: bool) -> bool:
    return overwrite or not comic.genres


def _value_can_update(field_name: str, value: Any) -> bool:
    return not _is_empty(value)


def _numeric_value(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = value.strip().replace(",", "")
        if not cleaned:
            return None
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def _compare_field_values(db_value: Any, kiryuu_value: Any) -> str:
    db_empty = _is_empty(db_value)
    kiryuu_empty = _is_empty(kiryuu_value)
    if db_empty and kiryuu_empty:
        return "both_missing"
    if kiryuu_empty:
        return "kiryuu_missing"
    if db_empty:
        return "db_missing_kiryuu_available"

    db_number = _numeric_value(db_value)
    kiryuu_number = _numeric_value(kiryuu_value)
    if db_number is not None and kiryuu_number is not None:
        if db_number == kiryuu_number:
            return "same"
        if db_number > kiryuu_number:
            return "db_greater_use_kiryuu"
        return "kiryuu_greater"

    db_text = clean_compare_text(db_value)
    kiryuu_text = clean_compare_text(kiryuu_value)
    return "same" if db_text == kiryuu_text else "textual_difference"


def clean_compare_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip().lower()


def _field_has_value_condition(field_name: str):
    column = getattr(Comic, field_name)
    if field_name in STRING_FIELDS:
        return column.is_not(None) & (func.length(func.trim(column)) > 0)
    return column.is_not(None)


def _build_candidate_filter(
    fields: set[str],
    *,
    overwrite: bool,
    with_genres: bool,
) -> Any | None:
    if overwrite:
        return None

    clauses = []
    for field_name in fields:
        column = getattr(Comic, field_name)
        clauses.append(column.is_(None))
        if field_name in STRING_FIELDS:
            clauses.append(column == "")

    if with_genres:
        clauses.append(~Comic.genres.any())

    return or_(*clauses) if clauses else None


def _candidate_match_score(comic: Comic, candidate: dict[str, Any]) -> int:
    comic_slug = _normalize_slug(comic.slug)
    comic_compact_slug = _compact_slug(comic.slug)
    candidate_slug = _normalize_slug(candidate.get("slug"))
    if candidate_slug and candidate_slug == comic_slug:
        return 100

    candidate_url_slug = ""
    source_url = candidate.get("source_url") or ""
    url_match = re.search(r"/manga/([^/?#]+)/?", source_url)
    if url_match:
        candidate_url_slug = _normalize_slug(url_match.group(1))
    if candidate_url_slug and candidate_url_slug == comic_slug:
        return 100

    candidate_compact_slug = _compact_slug(candidate_slug or candidate_url_slug)
    if comic_compact_slug and candidate_compact_slug == comic_compact_slug:
        return 96

    candidate_title = _normalize_title(candidate.get("title"))
    if candidate_title and candidate_title in _split_title_candidates(comic):
        return 88

    candidate_compact_title = _compact_title(candidate.get("title"))
    for title_candidate in _split_title_candidates(comic):
        if candidate_compact_title and candidate_compact_title == _compact_title(title_candidate):
            return 94

    best_similarity = max(
        (
            _title_similarity(title_candidate, candidate.get("title"))
            for title_candidate in _split_title_candidates(comic)
        ),
        default=0.0,
    )
    if best_similarity >= 0.92:
        return min(93, int(70 + (best_similarity * 25)))

    return 0


async def _find_kiryuu_match(scraper, comic: Comic) -> dict[str, Any] | None:
    scored: list[tuple[int, dict[str, Any], str]] = []
    seen_urls: set[str] = set()
    for query in _iter_search_queries(comic):
        search_results = await scraper.search_comics(query, page=1)
        query_scored: list[tuple[int, dict[str, Any], str]] = []
        for candidate in search_results:
            source_url = candidate.get("source_url") or ""
            if source_url and source_url in seen_urls:
                continue
            if source_url:
                seen_urls.add(source_url)
            score = _candidate_match_score(comic, candidate)
            scored.append((score, candidate, query))
            if score > 0:
                query_scored.append((score, candidate, query))

        if query_scored:
            query_scored.sort(key=lambda item: item[0], reverse=True)
            best_score, best_candidate, best_query = query_scored[0]
            if best_score >= HIGH_CONFIDENCE_MATCH_SCORE:
                logger.info(
                    "Match fuzzy Kiryuu: %s -> %s (score=%s, query=%s, title=%s)",
                    comic.slug,
                    best_candidate.get("source_url"),
                    best_score,
                    _safe_display(best_query),
                    _safe_display(best_candidate.get("title")),
                )
                return best_candidate

    matched = [(score, candidate, query) for score, candidate, query in scored if score > 0]
    if not matched:
        return None

    matched.sort(key=lambda item: item[0], reverse=True)
    best_score, best_candidate, best_query = matched[0]
    logger.info(
        "Match fuzzy Kiryuu: %s -> %s (score=%s, query=%s, title=%s)",
        comic.slug,
        best_candidate.get("source_url"),
        best_score,
        _safe_display(best_query),
        _safe_display(best_candidate.get("title")),
    )
    return best_candidate


async def _resolve_kiryuu_patch(
    scraper,
    comic: Comic,
    *,
    fields: set[str],
) -> dict[str, Any] | None:
    match = await _find_kiryuu_match(scraper, comic)
    if not match or not match.get("source_url"):
        return None

    return await scraper.get_comic_metadata_patch(match["source_url"], fields=fields)


async def _resolve_kiryuu_detail(scraper, comic: Comic) -> dict[str, Any] | None:
    match = await _find_kiryuu_match(scraper, comic)
    if not match or not match.get("source_url"):
        return None

    return await scraper.get_comic_detail(match["source_url"])


def _build_updates(
    comic: Comic,
    patch: dict[str, Any],
    fields: set[str],
    *,
    overwrite: bool,
) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    for field_name in sorted(fields):
        if field_name not in patch:
            continue
        value = patch[field_name]
        if not _value_can_update(field_name, value):
            continue
        if not _field_needs_update(comic, field_name, overwrite=overwrite):
            continue
        if getattr(comic, field_name) == value:
            continue
        updates[field_name] = value

    if updates:
        updates["updated_at"] = now_wib()
    return updates


async def _load_candidate_comics(
    session,
    *,
    fields: set[str],
    source_names: list[str] | None,
    limit: int | None,
    offset: int,
    resume_after_id: int,
    overwrite: bool,
    with_genres: bool,
) -> list[Comic]:
    loader_options = (
        (selectinload(Comic.genres), noload(Comic.chapters))
        if with_genres
        else (noload(Comic.genres), noload(Comic.chapters))
    )
    stmt = (
        select(Comic)
        .options(*loader_options)
        .where(Comic.source_name != BACKUP_SOURCE_NAME)
        .order_by(Comic.id.asc())
    )
    if source_names:
        stmt = stmt.where(Comic.source_name.in_(source_names))
    if resume_after_id > 0:
        stmt = stmt.where(Comic.id > resume_after_id)

    candidate_filter = _build_candidate_filter(
        fields,
        overwrite=overwrite,
        with_genres=with_genres,
    )
    if candidate_filter is not None:
        stmt = stmt.where(candidate_filter)
    if offset > 0:
        stmt = stmt.offset(offset)
    if limit is not None:
        stmt = stmt.limit(limit)

    result = await session.execute(stmt)
    return list(result.scalars().unique().all())


def _format_overview_table(rows: list[dict[str, Any]], headers: list[str]) -> str:
    widths = {
        header: max(
            len(header),
            *(len(str(row.get(header, ""))) for row in rows),
        )
        for header in headers
    }
    separator = " | "
    header_line = separator.join(header.ljust(widths[header]) for header in headers)
    divider = separator.join("-" * widths[header] for header in headers)
    body = [
        separator.join(str(row.get(header, "")).ljust(widths[header]) for header in headers)
        for row in rows
    ]
    return "\n".join([header_line, divider, *body])


async def run_overview(
    *,
    fields: set[str],
    source_names: list[str] | None,
    with_genres: bool,
) -> None:
    """Cetak overview kelengkapan metadata per source tanpa update DB."""
    overview_fields = sorted(fields)
    headers = ["source", "jumlah_komik_data_row"]
    for field_name in overview_fields:
        headers.extend([f"total_memiliki_{field_name}", f"total_{field_name}_null"])
    if with_genres:
        headers.extend(["total_memiliki_genres", "total_genres_null"])

    selected_sources = source_names or get_supported_source_names()
    rows: list[dict[str, Any]] = []
    async with async_session() as session:
        for source_name in selected_sources:
            total_stmt = select(func.count(Comic.id)).where(Comic.source_name == source_name)
            total = (await session.execute(total_stmt)).scalar_one()
            row: dict[str, Any] = {
                "source": source_name,
                "jumlah_komik_data_row": int(total or 0),
            }

            for field_name in overview_fields:
                has_value_condition = _field_has_value_condition(field_name)
                count_stmt = select(
                    func.sum(case((has_value_condition, 1), else_=0))
                ).where(Comic.source_name == source_name)
                has_value = (await session.execute(count_stmt)).scalar() or 0
                row[f"total_memiliki_{field_name}"] = int(has_value)
                row[f"total_{field_name}_null"] = int((total or 0) - has_value)

            if with_genres:
                genre_count_stmt = select(func.count(Comic.id)).where(
                    Comic.source_name == source_name,
                    Comic.genres.any(),
                )
                has_genres = (await session.execute(genre_count_stmt)).scalar() or 0
                row["total_memiliki_genres"] = int(has_genres)
                row["total_genres_null"] = int((total or 0) - has_genres)

            rows.append(row)

    print(_format_overview_table(rows, headers))


async def run_compare_values(
    *,
    fields: set[str],
    source_names: list[str] | None,
    limit: int | None,
    offset: int,
) -> CompareStats:
    """Bandingkan nilai metadata DB source aktif dengan Kiryuu tanpa update."""
    stats = CompareStats()
    scraper = create_backup_scraper(BACKUP_SOURCE_NAME)
    patch_fields = set(fields) | {"source_url", "title"}
    detail_rows: list[dict[str, Any]] = []

    logger.info("=" * 60)
    logger.info("Compare metadata DB vs Kiryuu dimulai")
    logger.info("Target source : %s", ", ".join(source_names or ["semua source aktif"]))
    logger.info("Fields        : %s", ", ".join(sorted(fields)))
    logger.info("Limit/offset  : %s / %s", limit if limit is not None else "tanpa limit", offset)
    logger.info("=" * 60)

    try:
        async with async_session() as session:
            comics = await _load_candidate_comics(
                session,
                fields=fields,
                source_names=source_names,
                limit=limit,
                offset=offset,
                resume_after_id=0,
                overwrite=True,
                with_genres=False,
            )
            logger.info("Kandidat compare: %s komik", len(comics))

            for index, comic in enumerate(comics, start=1):
                stats.scanned += 1
                label = f"[{index}/{len(comics)}] {comic.source_name}:{comic.slug}"
                _log_comic_separator(label, comic.title)
                logger.info("%s compare fields: %s", label, ", ".join(sorted(fields)))

                try:
                    payload = await _resolve_kiryuu_patch(
                        scraper,
                        comic,
                        fields=patch_fields,
                    )
                    if not payload or not payload.get("source_url"):
                        stats.no_match += 1
                        _log_match_missing(label)
                        continue

                    stats.matched += 1
                    _log_match_found(label, payload)
                    for field_name in sorted(fields):
                        db_value = getattr(comic, field_name)
                        kiryuu_value = payload.get(field_name)
                        status = _compare_field_values(db_value, kiryuu_value)

                        if status == "same":
                            stats.same += 1
                            continue
                        if status == "both_missing":
                            stats.kiryuu_missing += 1
                            continue
                        if status == "kiryuu_missing":
                            stats.kiryuu_missing += 1
                            stats.different += 1
                        elif status == "db_missing_kiryuu_available":
                            stats.db_missing_kiryuu_available += 1
                            stats.different += 1
                        elif status == "db_greater_use_kiryuu":
                            stats.db_greater += 1
                            stats.different += 1
                        elif status == "kiryuu_greater":
                            stats.kiryuu_greater += 1
                            stats.different += 1
                        else:
                            stats.textual_difference += 1
                            stats.different += 1

                        detail_rows.append(
                            {
                                "source": comic.source_name,
                                "slug": comic.slug,
                                "field": field_name,
                                "db_value": _safe_display(db_value),
                                "kiryuu_value": _safe_display(kiryuu_value),
                                "status": status,
                                "action": (
                                    "candidate_use_kiryuu"
                                    if status == "db_greater_use_kiryuu"
                                    else ""
                                ),
                            }
                        )
                except Exception as exc:
                    stats.errors += 1
                    logger.error("%s gagal compare: %s", label, exc)
    finally:
        try:
            await scraper.close()
        except Exception as exc:
            logger.warning("Gagal menutup scraper Kiryuu: %s", exc)

    summary_rows = [
        {"metric": "scanned", "total": stats.scanned},
        {"metric": "matched", "total": stats.matched},
        {"metric": "same", "total": stats.same},
        {"metric": "different", "total": stats.different},
        {"metric": "db_missing_kiryuu_available", "total": stats.db_missing_kiryuu_available},
        {"metric": "kiryuu_missing", "total": stats.kiryuu_missing},
        {"metric": "db_greater_use_kiryuu", "total": stats.db_greater},
        {"metric": "kiryuu_greater", "total": stats.kiryuu_greater},
        {"metric": "textual_difference", "total": stats.textual_difference},
        {"metric": "no_match", "total": stats.no_match},
        {"metric": "errors", "total": stats.errors},
    ]
    print(_format_overview_table(summary_rows, ["metric", "total"]))
    if detail_rows:
        print()
        print(_format_overview_table(
            detail_rows,
            ["source", "slug", "field", "db_value", "kiryuu_value", "status", "action"],
        ))

    return stats


async def run_backfill(
    *,
    fields: set[str],
    source_names: list[str] | None,
    limit: int | None,
    offset: int,
    dry_run: bool,
    overwrite: bool,
    with_genres: bool,
    reset: bool,
) -> BackfillStats:
    start_time = time.time()
    started_at = now_wib()
    scope = _checkpoint_scope(
        source_names=source_names,
        fields=fields,
        dry_run=dry_run,
        overwrite=overwrite,
        with_genres=with_genres,
    )
    if reset:
        reset_checkpoint(scope)
    checkpoint = load_checkpoint(scope)
    stats = BackfillStats.from_checkpoint(checkpoint.get("stats"))
    progress = checkpoint.get("progress", {})
    resume_after_id = int(progress.get("last_processed_comic_id", 0) or 0)
    scraper = create_backup_scraper(BACKUP_SOURCE_NAME)
    patch_fields = set(fields) | {"source_url", "title"}

    logger.info("=" * 60)
    logger.info("Backfill metadata dari Kiryuu dimulai")
    logger.info("Target source : %s", ", ".join(source_names or ["semua source aktif"]))
    logger.info("Fields        : %s", ", ".join(sorted(fields)))
    logger.info("Genres        : %s", "sync dari detail penuh" if with_genres else "skip")
    logger.info("Mode          : %s", "dry-run" if dry_run else "update DB")
    logger.info("Update rule   : %s", "overwrite" if overwrite else "hanya field kosong")
    logger.info("Limit/offset  : %s / %s", limit if limit is not None else "tanpa limit", offset)
    logger.info("Checkpoint    : %s", get_checkpoint_file(scope))
    logger.info("Resume        : comic_id > %s", resume_after_id)
    logger.info("Started at    : %s", started_at.isoformat())
    logger.info("=" * 60)

    end_state = "complete"
    end_note = "Backfill selesai"
    try:
        async with async_session() as session:
            comics = await _load_candidate_comics(
                session,
                fields=fields,
                source_names=source_names,
                limit=limit,
                offset=offset,
                resume_after_id=resume_after_id,
                overwrite=overwrite,
                with_genres=with_genres,
            )
            logger.info("Kandidat DB: %s komik", len(comics))
            persist_backfill_checkpoint(
                scope,
                checkpoint,
                stats,
                current_comic_total=len(comics),
                state="started",
                note=f"Kandidat DB: {len(comics)} komik",
            )

            for index, comic in enumerate(comics, start=1):
                if _shutdown.requested:
                    end_state = "stopped"
                    end_note = "Shutdown diminta user"
                    break

                stats.scanned += 1
                update_progress(
                    checkpoint,
                    current_comic_id=comic.id,
                    current_comic_position=index,
                    current_comic_total=len(comics),
                    current_source_name=comic.source_name,
                    current_slug=comic.slug,
                    current_title=comic.title,
                    state="checking",
                    note=f"Memproses komik {index}/{len(comics)}",
                )
                needed_fields = [
                    field_name
                    for field_name in sorted(fields)
                    if _field_needs_update(comic, field_name, overwrite=overwrite)
                ]
                if with_genres and _genres_need_sync(comic, overwrite=overwrite):
                    needed_fields.append("genres")
                if not needed_fields:
                    stats.skipped_no_need += 1
                    persist_backfill_checkpoint(
                        scope,
                        checkpoint,
                        stats,
                        last_processed_comic_id=comic.id,
                        state="skipped-no-need",
                        note=f"{comic.source_name}:{comic.slug} tidak perlu update",
                    )
                    continue
                stats.need_metadata += 1

                label = f"[{index}/{len(comics)}] {comic.source_name}:{comic.slug}"
                _log_comic_separator(label, comic.title)
                logger.info("%s cek metadata kosong: %s", label, ", ".join(needed_fields))

                try:
                    if with_genres:
                        payload = await _resolve_kiryuu_detail(scraper, comic)
                    else:
                        payload = await _resolve_kiryuu_patch(
                            scraper,
                            comic,
                            fields=patch_fields,
                        )
                    if not payload or not payload.get("source_url"):
                        stats.skipped_no_match += 1
                        _log_match_missing(label)
                        persist_backfill_checkpoint(
                            scope,
                            checkpoint,
                            stats,
                            last_processed_comic_id=comic.id,
                            state="skipped-no-match",
                            note=f"{comic.source_name}:{comic.slug} tidak ada match Kiryuu",
                        )
                        continue

                    stats.matched += 1
                    _log_match_found(label, payload)
                    updates = _build_updates(comic, payload, fields, overwrite=overwrite)
                    genres = payload.get("genres") or []
                    should_sync_genres = (
                        with_genres
                        and bool(genres)
                        and _genres_need_sync(comic, overwrite=overwrite)
                    )
                    if not updates and not should_sync_genres:
                        stats.skipped_no_values += 1
                        logger.info("%s match ada, tapi tidak ada nilai baru", label)
                        persist_backfill_checkpoint(
                            scope,
                            checkpoint,
                            stats,
                            last_processed_comic_id=comic.id,
                            state="skipped-no-values",
                            note=f"{comic.source_name}:{comic.slug} match tanpa nilai baru",
                        )
                        continue

                    changed_fields = sorted(updates.keys())
                    changed_fields = [name for name in changed_fields if name != "updated_at"]
                    if should_sync_genres:
                        changed_fields.append("genres")
                    logger.info(
                        "%s update fields: %s",
                        label,
                        ", ".join(changed_fields),
                    )

                    if dry_run:
                        stats.dry_run_updates += 1
                        stats.record_fields(changed_fields)
                        persist_backfill_checkpoint(
                            scope,
                            checkpoint,
                            stats,
                            last_processed_comic_id=comic.id,
                            state="dry-run-updated",
                            note=f"{comic.source_name}:{comic.slug} dry-run update",
                        )
                        continue

                    if updates:
                        await session.execute(
                            update(Comic)
                            .where(Comic.id == comic.id)
                            .values(**updates)
                        )
                    if should_sync_genres:
                        await sync_comic_genres(session, comic.id, genres)
                        stats.genre_updated += 1
                    await session.commit()
                    stats.updated += 1
                    stats.record_fields(changed_fields)
                    persist_backfill_checkpoint(
                        scope,
                        checkpoint,
                        stats,
                        last_processed_comic_id=comic.id,
                        state="updated",
                        note=f"{comic.source_name}:{comic.slug} updated",
                    )
                except Exception as exc:
                    stats.errors += 1
                    await session.rollback()
                    logger.error("%s gagal diproses: %s", label, exc)
                    persist_backfill_checkpoint(
                        scope,
                        checkpoint,
                        stats,
                        last_processed_comic_id=comic.id,
                        state="error",
                        note=f"{comic.source_name}:{comic.slug} error: {exc}",
                    )
    finally:
        try:
            await scraper.close()
        except Exception as exc:
            logger.warning("Gagal menutup scraper Kiryuu: %s", exc)
        persist_backfill_checkpoint(
            scope,
            checkpoint,
            stats,
            state=end_state,
            note=end_note,
        )

    elapsed = time.time() - start_time
    logger.info("=" * 60)
    logger.info("Backfill %s", "dihentikan" if end_state == "stopped" else "selesai")
    logger.info("Duration      : %s", format_elapsed_duration(elapsed))
    logger.info("Scanned       : %s", stats.scanned)
    logger.info("Need metadata : %s", stats.need_metadata)
    logger.info("Matched       : %s", stats.matched)
    logger.info("Updated       : %s", stats.updated)
    logger.info("Dry-run update: %s", stats.dry_run_updates)
    logger.info("No match      : %s", stats.skipped_no_match)
    logger.info("No values     : %s", stats.skipped_no_values)
    logger.info("No need       : %s", stats.skipped_no_need)
    logger.info("Genre updated : %s", stats.genre_updated)
    logger.info("Errors        : %s", stats.errors)
    if stats.updated_fields:
        logger.info(
            "Fields        : %s",
            ", ".join(
                f"{field_name}={count}"
                for field_name, count in sorted(stats.updated_fields.items())
            ),
        )
    logger.info("=" * 60)
    return stats


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Backfill metadata kosong dari Kiryuu tanpa ingest Kiryuu ke DB.",
    )
    parser.add_argument("--source", help="Source target DB, comma-separated. Default: semua source aktif.")
    parser.add_argument("--fields", help=f"Field metadata, comma-separated. Default: {','.join(DEFAULT_FIELDS)}")
    parser.add_argument("--limit", type=int, help="Batasi jumlah kandidat DB yang diproses.")
    parser.add_argument("--offset", type=int, default=0, help="Offset kandidat DB.")
    parser.add_argument("--dry-run", action="store_true", help="Tampilkan rencana update tanpa menulis DB.")
    parser.add_argument("--overview", action="store_true", help="Tampilkan jumlah field terisi/null per source tanpa backfill.")
    parser.add_argument("--compare-values", action="store_true", help="Bandingkan nilai field DB dengan Kiryuu tanpa update.")
    parser.add_argument("--overwrite", action="store_true", help="Timpa field yang sudah berisi nilai.")
    parser.add_argument("--with-genres", action="store_true", help="Fetch detail penuh Kiryuu dan sync relasi genre jika kosong.")
    parser.add_argument("--reset", action="store_true", help="Hapus checkpoint aktif sebelum backfill.")
    parser.add_argument("--log-file", default="", help="Nama/path file log. Default: backfill_metadata_from_kiryuu.log")
    args = parser.parse_args(argv)

    if args.limit is not None and args.limit <= 0:
        raise ValueError("--limit harus lebih besar dari 0")
    if args.offset < 0:
        raise ValueError("--offset harus >= 0")

    active_sources = set(get_supported_source_names())
    backup_sources = set(get_backup_source_names())
    if BACKUP_SOURCE_NAME not in backup_sources:
        raise ValueError(f"Backup source '{BACKUP_SOURCE_NAME}' tidak terdaftar.")

    source_names = _parse_csv(args.source)
    unsupported = sorted(set(source_names) - active_sources)
    if unsupported:
        raise ValueError(
            f"--source harus source aktif, bukan backup/unknown: {', '.join(unsupported)}. "
            f"Pilihan: {', '.join(sorted(active_sources))}"
        )

    args.source_names = source_names or None
    args.selected_fields = _parse_fields(args.fields)
    return args


def main(argv: list[str] | None = None) -> None:
    argv = argv if argv is not None else sys.argv[1:]
    try:
        args = parse_args(argv)
    except ValueError as exc:
        print(f"Error argumen: {exc}")
        sys.exit(1)

    log_path = resolve_log_path(args.log_file or DEFAULT_LOG_FILE)
    configure_logging(str(log_path))
    if args.overview:
        asyncio.run(
            run_overview(
                fields=args.selected_fields,
                source_names=args.source_names,
                with_genres=args.with_genres,
            )
        )
        return
    if args.compare_values:
        asyncio.run(
            run_compare_values(
                fields=args.selected_fields,
                source_names=args.source_names,
                limit=args.limit,
                offset=args.offset,
            )
        )
        return

    asyncio.run(
        run_backfill(
            fields=args.selected_fields,
            source_names=args.source_names,
            limit=args.limit,
            offset=args.offset,
            dry_run=args.dry_run,
            overwrite=args.overwrite,
            with_genres=args.with_genres,
            reset=args.reset,
        )
    )


if __name__ == "__main__":
    main()
