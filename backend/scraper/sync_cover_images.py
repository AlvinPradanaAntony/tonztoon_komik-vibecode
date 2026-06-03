"""
Tonztoon Komik — Cover Image Storage Sync

Backfill cover komik ke Supabase Storage tanpa menambah field baru.

Flow:
1. Ambil comic dari DB berdasarkan source.
2. Download cover dari URL yang tersimpan.
3. Download cover dari `comics.cover_image_url`.
   Khusus Komiku Asia, jika HTTP biasa gagal, fallback ke browser Scrapling.
4. Optimasi ke WebP dengan batas ukuran.
5. Upload ke Supabase Storage.
6. Update `comics.cover_image_url` menjadi public storage URL.

Usage:
    cd backend
    python -m scraper.sync_cover_images --source komiku_asia --limit 50
    python -m scraper.sync_cover_images --source komiku_asia --limit 10 --dry-run
    python -m scraper.sync_cover_images --source komiku_asia --force
    python -m scraper.sync_cover_images --source komiku_asia --reset --limit 50
    python -m scraper.sync_cover_images --source komiku_asia --limit 50 --no-anti-blocking

Strategi anti-blocking:
- delay acak antar cover
- cooldown berkala setelah sejumlah cover berhasil diproses
- exponential backoff saat error beruntun atau upload storage terkena 429/5xx
- graceful shutdown dan checkpoint per source untuk resume batch berikutnya
"""

from __future__ import annotations

import argparse
import asyncio
import base64
from dataclasses import dataclass
from io import BytesIO
import json
import logging
from pathlib import Path
import sys
import time
from typing import Iterable

import httpx
from sqlalchemy import select, update

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings
from app.database import async_session
from app.models import Comic
from app.services.image_service import (
    DEFAULT_USER_AGENT,
    get_proxy_headers,
    is_komiku_asia_cover_url,
)
from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper
from scraper.time_utils import now_wib
from scraper.utils import (
    GracefulShutdown,
    RealtimeConsoleHandler,
    backoff_delay,
    configure_external_loggers as _configure_external_loggers_base,
    configure_logging as _configure_logging_base,
    format_elapsed_duration,
    random_delay,
    resolve_log_path as _resolve_log_path_base,
)

try:
    from PIL import Image
except ModuleNotFoundError as exc:  # pragma: no cover - CLI guard
    raise SystemExit(
        "Pillow belum terinstall. Jalankan `pip install -r requirements.txt` dari folder backend."
    ) from exc


logger = logging.getLogger("sync-cover-images")

DEFAULT_LOG_FILE = Path("sync_cover_images.log")
CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "checkpoints"
DEFAULT_MAX_BYTES = 150 * 1024
DEFAULT_MAX_WIDTH = 600
DEFAULT_LIMIT = 0
DELAY_COVER_MIN = 2.0
DELAY_COVER_MAX = 5.0
COOLDOWN_EVERY_N_COVERS = 10
COOLDOWN_MIN = 10.0
COOLDOWN_MAX = 20.0
BACKOFF_MAX = 120.0
MAX_CONSECUTIVE_ERRORS = 5
UPLOAD_MAX_ATTEMPTS = 3

_shutdown = GracefulShutdown()
_shutdown.install()


@dataclass(slots=True)
class CoverCandidate:
    """Data minimum comic yang perlu diproses."""

    id: int
    source_name: str
    slug: str
    title: str
    cover_image_url: str
    source_url: str


@dataclass(slots=True)
class DownloadedImage:
    """Hasil download cover sebelum upload storage."""

    content: bytes
    content_type: str
    origin_url: str


@dataclass
class CoverSyncStats:
    total_scanned: int = 0
    total_uploaded: int = 0
    total_skipped: int = 0
    total_errors: int = 0
    processed_since_cooldown: int = 0


def _build_default_log_filename(*, source: str) -> Path:
    """Nama file log default yang dipisah per source."""
    return Path(f"sync_cover_images_{source}.log")


def resolve_log_path(
    log_file: str | None,
    *,
    source: str = "komiku_asia",
) -> Path:
    """Resolve path log ke folder backend/logs kecuali path absolut."""
    filename = log_file or str(_build_default_log_filename(source=source))
    return _resolve_log_path_base(filename)


def configure_logging(
    log_file: str | None = None,
    *,
    source: str = "komiku_asia",
) -> None:
    """Konfigurasi logger root konsisten dengan script sync scraper lain."""
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    filename = log_file or str(_build_default_log_filename(source=source))
    _configure_logging_base(
        filename,
        default_filename=str(DEFAULT_LOG_FILE),
        stdout_handler=RealtimeConsoleHandler(sys.stdout),
    )
    _configure_external_loggers_base()


def get_checkpoint_file(source: str) -> Path:
    return CHECKPOINT_DIR / f"sync_cover_images_{source}.json"


def _default_stats() -> dict:
    return {
        "total_scanned": 0,
        "total_uploaded": 0,
        "total_skipped": 0,
        "total_errors": 0,
        "processed_since_cooldown": 0,
    }


def _default_progress() -> dict:
    return {
        "source": None,
        "limit": 0,
        "force": False,
        "dry_run": False,
        "current_comic_id": 0,
        "current_comic_position": 0,
        "current_comic_total": 0,
        "current_slug": None,
        "current_title": None,
        "state": "idle",
        "note": None,
    }


def _default_checkpoint() -> dict:
    return {
        "last_processed_comic_id": 0,
        "updated_at": None,
        "stats": _default_stats(),
        "progress": _default_progress(),
    }


def _normalize_checkpoint(data: dict | None) -> dict:
    checkpoint = data or {}
    checkpoint.setdefault("last_processed_comic_id", 0)
    checkpoint.setdefault("updated_at", None)

    default_stats = _default_stats()
    stats = checkpoint.setdefault("stats", default_stats.copy())
    for key, value in default_stats.items():
        stats.setdefault(key, value)

    default_progress = _default_progress()
    progress = checkpoint.setdefault("progress", default_progress.copy())
    for key, value in default_progress.items():
        progress.setdefault(key, value)

    if (
        progress["current_comic_id"] == 0
        and checkpoint["last_processed_comic_id"] > 0
    ):
        progress["current_comic_id"] = checkpoint["last_processed_comic_id"]

    return checkpoint


def update_progress(
    checkpoint: dict,
    *,
    source: str | None = None,
    limit: int | None = None,
    force: bool | None = None,
    dry_run: bool | None = None,
    current_comic_id: int | None = None,
    current_comic_position: int | None = None,
    current_comic_total: int | None = None,
    current_slug: str | None = None,
    current_title: str | None = None,
    state: str | None = None,
    note: str | None = None,
) -> dict:
    progress = checkpoint.setdefault("progress", _default_progress())
    if source is not None:
        progress["source"] = source
    if limit is not None:
        progress["limit"] = limit
    if force is not None:
        progress["force"] = force
    if dry_run is not None:
        progress["dry_run"] = dry_run
    if current_comic_id is not None:
        progress["current_comic_id"] = current_comic_id
    if current_comic_position is not None:
        progress["current_comic_position"] = current_comic_position
    if current_comic_total is not None:
        progress["current_comic_total"] = current_comic_total
    if current_slug is not None:
        progress["current_slug"] = current_slug
    if current_title is not None:
        progress["current_title"] = current_title
    if state is not None:
        progress["state"] = state
    if note is not None:
        progress["note"] = note
    return progress


def load_checkpoint(source: str) -> dict:
    checkpoint_file = get_checkpoint_file(source)
    if not checkpoint_file.exists():
        return _default_checkpoint()
    try:
        with open(checkpoint_file, "r", encoding="utf-8") as f:
            checkpoint = _normalize_checkpoint(json.load(f))
        logger.info("📂 Checkpoint ditemukan: %s", checkpoint_file)
        return checkpoint
    except Exception as exc:
        logger.warning("⚠️ Checkpoint rusak, mulai baru: %s", exc)
        return _default_checkpoint()


def save_checkpoint(source: str, checkpoint: dict) -> None:
    checkpoint_file = get_checkpoint_file(source)
    checkpoint["updated_at"] = now_wib().isoformat()
    checkpoint_file.parent.mkdir(parents=True, exist_ok=True)
    with open(checkpoint_file, "w", encoding="utf-8") as f:
        json.dump(checkpoint, f, indent=2, ensure_ascii=False)


def persist_checkpoint(source: str, checkpoint: dict, *, enabled: bool) -> None:
    if enabled:
        save_checkpoint(source, checkpoint)


def reset_checkpoint(source: str) -> None:
    checkpoint_file = get_checkpoint_file(source)
    if checkpoint_file.exists():
        checkpoint_file.unlink()
        logger.info("🗑️ Checkpoint dihapus: %s", checkpoint_file)


def _strip_trailing_slash(value: str) -> str:
    return value.rstrip("/")


def _storage_public_prefix(bucket: str) -> str:
    return (
        f"{_strip_trailing_slash(settings.SUPABASE_URL)}"
        f"/storage/v1/object/public/{bucket}/"
    )


def is_storage_cover_url(url: str | None, bucket: str) -> bool:
    if not url or not settings.SUPABASE_URL:
        return False
    return url.startswith(_storage_public_prefix(bucket))


def build_storage_path(comic: CoverCandidate) -> str:
    """Path stabil agar rerun meng-overwrite cover comic yang sama."""
    source = comic.source_name.strip().lower() or "unknown"
    slug = comic.slug.strip().lower() or f"comic-{comic.id}"
    return f"covers/{source}/{slug}.webp"


def build_public_storage_url(bucket: str, object_path: str) -> str:
    return f"{_storage_public_prefix(bucket)}{object_path}"


def require_supabase_storage_config(bucket: str) -> None:
    missing = []
    if not settings.SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not settings.SUPABASE_SERVICE_ROLE_KEY:
        missing.append("SUPABASE_SERVICE_ROLE_KEY")
    if not bucket:
        missing.append("SUPABASE_COVER_BUCKET")
    if missing:
        raise RuntimeError(f"Konfigurasi Supabase Storage belum lengkap: {', '.join(missing)}")


async def fetch_comic_candidates(
    *,
    source: str,
    limit: int,
    bucket: str,
    force: bool,
    after_id: int,
) -> list[CoverCandidate]:
    async with async_session() as session:
        stmt = (
            select(
                Comic.id,
                Comic.source_name,
                Comic.slug,
                Comic.title,
                Comic.cover_image_url,
                Comic.source_url,
            )
            .where(
                Comic.source_name == source,
                Comic.cover_image_url.is_not(None),
                Comic.id > after_id,
            )
            .order_by(Comic.id.asc())
        )
        if not force:
            stmt = stmt.where(~Comic.cover_image_url.startswith(_storage_public_prefix(bucket)))
        if limit > 0:
            stmt = stmt.limit(limit)

        rows = (await session.execute(stmt)).all()

    return [
        CoverCandidate(
            id=row.id,
            source_name=row.source_name,
            slug=row.slug,
            title=row.title,
            cover_image_url=row.cover_image_url,
            source_url=row.source_url,
        )
        for row in rows
        if row.cover_image_url
    ]


async def try_download_http(
    client: httpx.AsyncClient,
    url: str,
) -> DownloadedImage | None:
    try:
        response = await client.get(url, headers=get_proxy_headers(url))
    except httpx.RequestError as exc:
        logger.debug("Download gagal %s: %s", url, exc)
        return None

    if response.status_code != 200 or not response.content:
        logger.debug("Download bukan 200 %s: status=%s", url, response.status_code)
        return None

    content_type = response.headers.get("content-type", "application/octet-stream")
    if "image" not in content_type.lower():
        logger.debug("Download bukan image %s: content-type=%s", url, content_type)
        return None

    return DownloadedImage(
        content=response.content,
        content_type=content_type,
        origin_url=str(response.url),
    )


async def try_download_komiku_asia_cover_via_browser(
    comic: CoverCandidate,
    *,
    max_width: int,
) -> DownloadedImage | None:
    """
    Fallback terakhir untuk cover Komiku Asia.

    Browser membuka halaman detail sehingga Cloudflare/cookie source valid,
    lalu canvas halaman yang sama mengekspor cover ke WebP.
    """
    if not is_komiku_asia_cover_url(comic.cover_image_url):
        return None

    session = await KomikuAsiaScraper.get_session()
    async with session._page_generator(45_000, None, False) as page_info:
        page = page_info.page
        try:
            first_response = await page.goto(
                comic.source_url,
                referer=KomikuAsiaScraper.BASE_URL + "/",
            )
            if not first_response:
                return None

            await session._wait_for_page_stability(page, True, False)
            await session._cloudflare_solver(page)
            await session._wait_for_page_stability(page, True, False)
            await page.wait_for_timeout(800)

            data_url = await page.evaluate(
                """
                async ({ imageUrl, maxWidth }) => {
                    function loadImage(url) {
                        return new Promise((resolve, reject) => {
                            const img = new Image();
                            img.decoding = "async";
                            img.loading = "eager";
                            img.onload = () => resolve(img);
                            img.onerror = () => reject(new Error("image load failed"));
                            img.src = url;
                        });
                    }

                    let image = Array.from(document.images)
                        .find((img) => img.currentSrc === imageUrl || img.src === imageUrl);
                    if (!image || !image.complete || !image.naturalWidth) {
                        image = await loadImage(imageUrl);
                    }

                    const scale = Math.min(1, maxWidth / image.naturalWidth);
                    const width = Math.max(1, Math.round(image.naturalWidth * scale));
                    const height = Math.max(1, Math.round(image.naturalHeight * scale));
                    const canvas = document.createElement("canvas");
                    canvas.width = width;
                    canvas.height = height;
                    const ctx = canvas.getContext("2d");
                    ctx.drawImage(image, 0, 0, width, height);

                    return canvas.toDataURL("image/webp", 0.82);
                }
                """,
                {"imageUrl": comic.cover_image_url, "maxWidth": max_width},
            )
        except Exception as exc:
            page_info.mark_error()
            logger.debug("Browser cover fallback gagal %s: %s", comic.slug, exc)
            return None

    if not isinstance(data_url, str) or "," not in data_url:
        return None

    header, encoded = data_url.split(",", 1)
    content_type = "image/webp" if "image/webp" in header else "image/png"
    return DownloadedImage(
        content=base64.b64decode(encoded),
        content_type=content_type,
        origin_url=comic.cover_image_url,
    )


async def download_cover(
    client: httpx.AsyncClient,
    comic: CoverCandidate,
    *,
    max_width: int,
) -> DownloadedImage | None:
    downloaded = await try_download_http(client, comic.cover_image_url)
    if downloaded:
        return downloaded

    return await try_download_komiku_asia_cover_via_browser(
        comic,
        max_width=max_width,
    )


def optimize_cover_image(
    content: bytes,
    *,
    max_bytes: int,
    max_width: int,
) -> bytes:
    """Resize + kompres cover ke WebP dengan target ukuran maksimum."""
    with Image.open(BytesIO(content)) as image:
        if getattr(image, "is_animated", False):
            image.seek(0)
        image = image.convert("RGB")

        if image.width > max_width:
            ratio = max_width / image.width
            image = image.resize(
                (max_width, max(1, int(image.height * ratio))),
                Image.Resampling.LANCZOS,
            )

        quality = 82
        working = image
        while True:
            for q in range(quality, 39, -7):
                buffer = BytesIO()
                working.save(buffer, format="WEBP", quality=q, method=6)
                data = buffer.getvalue()
                if len(data) <= max_bytes or q <= 40:
                    if len(data) <= max_bytes or working.width <= 320:
                        return data

            next_width = max(320, int(working.width * 0.85))
            if next_width == working.width:
                return data
            ratio = next_width / working.width
            working = working.resize(
                (next_width, max(1, int(working.height * ratio))),
                Image.Resampling.LANCZOS,
            )
            quality = 76


async def upload_cover(
    client: httpx.AsyncClient,
    *,
    bucket: str,
    object_path: str,
    content: bytes,
    anti_blocking_enabled: bool = True,
) -> str:
    storage_base = f"{_strip_trailing_slash(settings.SUPABASE_URL)}/storage/v1/object"
    upload_url = f"{storage_base}/{bucket}/{object_path}"
    headers = {
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
        "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "image/webp",
        "Cache-Control": "31536000",
        "x-upsert": "true",
    }

    last_error: Exception | None = None
    retryable_statuses = {429, 500, 502, 503, 504}
    for attempt in range(UPLOAD_MAX_ATTEMPTS):
        try:
            response = await client.put(
                upload_url,
                content=content,
                headers=headers,
            )
        except httpx.RequestError as exc:
            last_error = exc
            if attempt < UPLOAD_MAX_ATTEMPTS - 1:
                if anti_blocking_enabled:
                    await backoff_delay(attempt, "upload cover storage", maximum=BACKOFF_MAX)
                else:
                    logger.info(
                        "⏩ Backoff upload storage dilewati karena --no-anti-blocking"
                    )
                continue
            raise RuntimeError(f"Upload storage gagal: {exc}") from exc

        if response.status_code in {200, 201}:
            return build_public_storage_url(bucket, object_path)

        if response.status_code in retryable_statuses and attempt < UPLOAD_MAX_ATTEMPTS - 1:
            logger.warning(
                "  upload storage retryable status=%s attempt=%s/%s",
                response.status_code,
                attempt + 1,
                UPLOAD_MAX_ATTEMPTS,
            )
            if anti_blocking_enabled:
                await backoff_delay(attempt, "upload cover storage", maximum=BACKOFF_MAX)
            else:
                logger.info("⏩ Backoff upload storage dilewati karena --no-anti-blocking")
            continue

        raise RuntimeError(
            f"Upload storage gagal status={response.status_code}: {response.text[:300]}"
        )

    raise RuntimeError(f"Upload storage gagal: {last_error}")


async def update_comic_cover_url(comic_id: int, storage_url: str) -> None:
    async with async_session() as session:
        await session.execute(
            update(Comic)
            .where(Comic.id == comic_id)
            .values(cover_image_url=storage_url, updated_at=now_wib())
        )
        await session.commit()


async def delay_between_covers(args: argparse.Namespace) -> None:
    if not args.anti_blocking_enabled:
        logger.debug("⏩ Delay antar-cover dilewati karena --no-anti-blocking")
        return
    if args.delay is not None:
        if args.delay > 0:
            await asyncio.sleep(args.delay)
        return
    await random_delay(args.delay_min, args.delay_max, "antar-cover")


async def maybe_backoff_delay(
    args: argparse.Namespace,
    attempt: int,
    label: str,
    *,
    maximum: float = BACKOFF_MAX,
) -> None:
    if args.anti_blocking_enabled:
        await backoff_delay(attempt, label, maximum=maximum)
        return
    logger.info("⏩ Backoff dilewati karena --no-anti-blocking: %s", label)


async def maybe_random_delay(
    args: argparse.Namespace,
    min_sec: float,
    max_sec: float,
    label: str,
) -> None:
    if args.anti_blocking_enabled:
        await random_delay(min_sec, max_sec, label)
        return
    logger.debug("⏩ Random delay dilewati: %s", label)


async def process_comic(
    client: httpx.AsyncClient,
    comic: CoverCandidate,
    *,
    bucket: str,
    dry_run: bool,
    max_bytes: int,
    max_width: int,
    anti_blocking_enabled: bool,
) -> bool:
    object_path = build_storage_path(comic)
    storage_url = build_public_storage_url(bucket, object_path)

    logger.info("Cover %s (%s)", comic.title, comic.slug)
    downloaded = await download_cover(client, comic, max_width=max_width)
    if not downloaded:
        logger.warning("  gagal download cover: %s", comic.cover_image_url)
        return False

    optimized = optimize_cover_image(
        downloaded.content,
        max_bytes=max_bytes,
        max_width=max_width,
    )
    logger.info(
        "  optimized: %.1fKB -> %.1fKB dari %s",
        len(downloaded.content) / 1024,
        len(optimized) / 1024,
        downloaded.origin_url,
    )

    if dry_run:
        logger.info("  dry-run: skip upload/update -> %s", storage_url)
        return True

    public_url = await upload_cover(
        client,
        bucket=bucket,
        object_path=object_path,
        content=optimized,
        anti_blocking_enabled=anti_blocking_enabled,
    )
    await update_comic_cover_url(comic.id, public_url)
    logger.info("  tersimpan: %s", public_url)
    return True


async def run(args: argparse.Namespace) -> None:
    args.bucket = args.bucket or settings.SUPABASE_COVER_BUCKET
    require_supabase_storage_config(args.bucket)
    start_time = time.time()
    started_at = now_wib()
    checkpoint_file = get_checkpoint_file(args.source)
    checkpoint_enabled = not args.dry_run

    if args.reset and checkpoint_enabled:
        reset_checkpoint(args.source)
    checkpoint = load_checkpoint(args.source) if checkpoint_enabled else _default_checkpoint()
    stats = CoverSyncStats(**checkpoint.get("stats", {}))
    after_id = int(checkpoint.get("last_processed_comic_id", 0) or 0) if checkpoint_enabled else 0
    update_progress(
        checkpoint,
        source=args.source,
        limit=args.limit,
        force=args.force,
        dry_run=args.dry_run,
        state="starting",
        note="Sync cover images dimulai",
    )
    persist_checkpoint(args.source, checkpoint, enabled=checkpoint_enabled)

    candidates = await fetch_comic_candidates(
        source=args.source,
        limit=args.limit,
        bucket=args.bucket,
        force=args.force,
        after_id=after_id,
    )

    logger.info("═" * 60)
    logger.info("🚀 Sync Cover Images dimulai — %s", started_at.isoformat())
    logger.info("   Source     : %s", args.source)
    logger.info("   Bucket     : %s", args.bucket)
    logger.info("   Limit      : %s", args.limit if args.limit > 0 else "tanpa limit")
    logger.info("   Force      : %s", args.force)
    logger.info("   Dry-run    : %s", args.dry_run)
    logger.info("   Max bytes  : %.1fKB", args.max_bytes / 1024)
    logger.info("   Max width  : %spx", args.max_width)
    logger.info(
        "   Anti-blocking: %s",
        "aktif" if args.anti_blocking_enabled else "nonaktif (--no-anti-blocking)",
    )
    if args.anti_blocking_enabled:
        logger.info(
            "   Delay      : %s",
            f"{args.delay:.1f}s" if args.delay is not None else f"{args.delay_min:.1f}-{args.delay_max:.1f}s",
        )
    else:
        logger.info("   Delay/cooldown/backoff: dilewati")
    logger.info("   Reset      : %s", args.reset)
    logger.info("   Resume >ID : %s", after_id)
    logger.info("   Checkpoint : %s", checkpoint_file if checkpoint_enabled else "disabled (dry-run)")
    logger.info("   Log file   : %s", resolve_log_path(args.log_file, source=args.source))
    logger.info("═" * 60)

    logger.info(
        "Mulai sync cover: source=%s candidates=%s bucket=%s dry_run=%s",
        args.source,
        len(candidates),
        args.bucket,
        args.dry_run,
    )

    ok = 0
    failed = 0
    consecutive_errors = 0
    try:
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=args.timeout,
            headers={"User-Agent": DEFAULT_USER_AGENT},
        ) as client:
            for index, comic in enumerate(candidates, start=1):
                if _shutdown.requested:
                    logger.warning("🛑 Shutdown diminta, berhenti setelah checkpoint terakhir.")
                    break

                logger.info("[%s/%s]", index, len(candidates))
                stats.total_scanned += 1
                update_progress(
                    checkpoint,
                    current_comic_id=comic.id,
                    current_comic_position=index,
                    current_comic_total=len(candidates),
                    current_slug=comic.slug,
                    current_title=comic.title,
                    state="processing-cover",
                    note=f"Memproses cover [{index}/{len(candidates)}]",
                )
                persist_checkpoint(args.source, checkpoint, enabled=checkpoint_enabled)

                try:
                    if await process_comic(
                        client,
                        comic,
                        bucket=args.bucket,
                        dry_run=args.dry_run,
                        max_bytes=args.max_bytes,
                        max_width=args.max_width,
                        anti_blocking_enabled=args.anti_blocking_enabled,
                    ):
                        ok += 1
                        stats.total_uploaded += 1
                        stats.processed_since_cooldown += 1
                        consecutive_errors = 0
                        update_progress(
                            checkpoint,
                            state="cover-complete",
                            note=f"Cover {comic.id} berhasil diproses",
                        )
                    else:
                        failed += 1
                        stats.total_skipped += 1
                        consecutive_errors += 1
                        update_progress(
                            checkpoint,
                            state="cover-download-failed",
                            note=f"Cover {comic.id} gagal diunduh",
                        )
                except Exception as exc:
                    failed += 1
                    stats.total_errors += 1
                    consecutive_errors += 1
                    logger.exception("  error cover %s: %s", comic.slug, exc)
                    update_progress(
                        checkpoint,
                        state="cover-error",
                        note=f"Error cover {comic.id}: {exc}",
                    )

                checkpoint["last_processed_comic_id"] = comic.id
                persist_checkpoint(
                    args.source,
                    {
                        **checkpoint,
                        "stats": {
                            "total_scanned": stats.total_scanned,
                            "total_uploaded": stats.total_uploaded,
                            "total_skipped": stats.total_skipped,
                            "total_errors": stats.total_errors,
                            "processed_since_cooldown": stats.processed_since_cooldown,
                        },
                    },
                    enabled=checkpoint_enabled,
                )

                if consecutive_errors:
                    await maybe_backoff_delay(
                        args,
                        min(consecutive_errors - 1, MAX_CONSECUTIVE_ERRORS - 1),
                        f"cover {args.source}",
                        maximum=BACKOFF_MAX,
                    )
                    if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                        logger.warning(
                            "  ⛔ %s error berturut-turut. Cooldown lebih lama sebelum lanjut.",
                            MAX_CONSECUTIVE_ERRORS,
                        )
                        await maybe_random_delay(
                            args,
                            COOLDOWN_MIN,
                            COOLDOWN_MAX,
                            "cooldown error cover",
                        )
                        consecutive_errors = 0

                if (
                    args.anti_blocking_enabled
                    and stats.processed_since_cooldown >= COOLDOWN_EVERY_N_COVERS
                ):
                    stats.processed_since_cooldown = 0
                    logger.info("  🧊 Cooldown berkala cover...")
                    await maybe_random_delay(args, COOLDOWN_MIN, COOLDOWN_MAX, "cooldown cover")

                await delay_between_covers(args)
    finally:
        await KomikuAsiaScraper.close_shared_session()

    if _shutdown.requested:
        update_progress(checkpoint, state="interrupted", note="Dihentikan manual")
    else:
        update_progress(checkpoint, state="complete", note="Sync cover images selesai")
    persist_checkpoint(
        args.source,
        {
            **checkpoint,
            "stats": {
                "total_scanned": stats.total_scanned,
                "total_uploaded": stats.total_uploaded,
                "total_skipped": stats.total_skipped,
                "total_errors": stats.total_errors,
                "processed_since_cooldown": stats.processed_since_cooldown,
            },
        },
        enabled=checkpoint_enabled,
    )

    elapsed = time.time() - start_time
    finished_at = now_wib()
    logger.info("═" * 60)
    logger.info("🏁 Sync Cover Images selesai!")
    logger.info("   Mulai    : %s", started_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Selesai  : %s", finished_at.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("   Waktu    : %s", format_elapsed_duration(elapsed))
    logger.info("   Source   : %s", args.source)
    logger.info("   Total    : %s", len(candidates))
    logger.info("   OK       : %s", ok)
    logger.info("   Failed   : %s", failed)
    logger.info("   Checkpoint: %s", checkpoint_file if checkpoint_enabled else "disabled (dry-run)")
    logger.info("═" * 60)


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync comic covers to Supabase Storage")
    parser.add_argument("--source", default="komiku_asia")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="0 berarti tanpa limit")
    parser.add_argument(
        "--bucket",
        default=None,
        help="Nama bucket Supabase Storage. Default dari SUPABASE_COVER_BUCKET di .env.",
    )
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    parser.add_argument("--max-width", type=int, default=DEFAULT_MAX_WIDTH)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument(
        "--delay",
        type=float,
        default=None,
        help="Delay tetap antar cover. Jika tidak diisi, pakai delay acak.",
    )
    parser.add_argument("--delay-min", type=float, default=DELAY_COVER_MIN)
    parser.add_argument("--delay-max", type=float, default=DELAY_COVER_MAX)
    parser.add_argument(
        "--log-file",
        default=None,
        help="Path file log. Jika relatif, disimpan di backend/logs/.",
    )
    parser.add_argument("--force", action="store_true", help="Proses ulang cover yang sudah di storage")
    parser.add_argument("--reset", action="store_true", help="Hapus checkpoint source aktif sebelum mulai")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--no-anti-blocking",
        dest="anti_blocking_enabled",
        action="store_false",
        help="Matikan random delay, cooldown berkala, dan backoff error.",
    )
    parser.set_defaults(anti_blocking_enabled=True)
    args = parser.parse_args(argv)
    if args.delay_min > args.delay_max:
        parser.error("--delay-min tidak boleh lebih besar dari --delay-max")
    return args


def main() -> None:
    args = parse_args()
    configure_logging(args.log_file, source=args.source)
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
