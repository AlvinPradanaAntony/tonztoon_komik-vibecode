"""
Refresh source_stats yang disimpan di database.

Usage:
    python -m scraper.refresh_source_stats
    python -m scraper.refresh_source_stats --source voratoon
    python -m scraper.refresh_source_stats --source komiku,voratoon
"""

from __future__ import annotations

import asyncio
import sys
import time
from datetime import datetime

# Pastikan console Windows mendukung output UTF-8 dengan karakter emoji & garis pembatas
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass
if hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

from app.database import async_session
from app.services.source_service import refresh_source_stat
from scraper.sources.registry import (
    SOURCE_LABELS,
    get_observable_source_names,
)

SOURCE_ICONS: dict[str, str] = {
    "komiku": "📗",
    "komiku_asia": "📘",
    "shinigami": "📕",
    "voratoon": "📙",
    "kiryuu": "📓",
}


def _parse_args(argv: list[str]) -> dict[str, list[str] | None]:
    source_names: list[str] | None = None
    supported_sources = set(get_observable_source_names())
    i = 0
    while i < len(argv):
        if argv[i] == "--source" and i + 1 < len(argv):
            source_names = [item.strip() for item in argv[i + 1].split(",") if item.strip()]
            unsupported = sorted(set(source_names) - supported_sources)
            if unsupported:
                supported = ", ".join(sorted(supported_sources))
                raise ValueError(
                    f"--source tidak didukung untuk source_stats: {', '.join(unsupported)}. "
                    f"Gunakan salah satu dari: {supported}"
                )
            i += 2
            continue
        i += 1
    return {"source_names": source_names}


def _format_datetime(dt: datetime | str | None) -> str:
    if not dt:
        return "Belum pernah"
    if isinstance(dt, str):
        try:
            dt = datetime.fromisoformat(dt)
        except ValueError:
            return dt[:19]
    if isinstance(dt, datetime):
        if dt.tzinfo is not None:
            return dt.astimezone().strftime("%Y-%m-%d %H:%M:%S")
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    return str(dt)[:19]


async def main(argv: list[str]) -> None:
    args = _parse_args(argv)
    target_sources = args["source_names"] or get_observable_source_names()
    total_sources = len(target_sources)
    start_time = time.time()

    banner_width = 80
    print("\n" + "═" * banner_width, flush=True)
    print("📊 TONZTOON KOMIK — REFRESH SOURCE STATS", flush=True)
    print("═" * banner_width, flush=True)
    print(f"🎯 Target  : {', '.join(target_sources)} ({total_sources} source)", flush=True)
    print(f"⏰ Dimulai : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
    print("═" * banner_width, flush=True)

    refreshed_rows = []
    success_count = 0
    fail_count = 0

    async with async_session() as db:
        for idx, source_name in enumerate(target_sources, start=1):
            icon = SOURCE_ICONS.get(source_name, "📖")
            label = SOURCE_LABELS.get(source_name, source_name.title())

            print("─" * banner_width, flush=True)
            print(f"{icon} [{idx}/{total_sources}] Memeriksa {label} ({source_name})...", flush=True)

            t0 = time.time()
            stat = await refresh_source_stat(db, source_name)
            elapsed = time.time() - t0
            refreshed_rows.append(stat)

            if stat.last_error:
                fail_count += 1
                short_err = stat.last_error.split("\n")[0][:90]
                print(f"  ❌ {label}: Gagal refresh ({short_err}) [{elapsed:.1f}s]", flush=True)
            else:
                success_count += 1
                count_str = (
                    f"{stat.source_comic_count:,}"
                    if stat.source_comic_count is not None
                    else "0"
                )
                print(f"  ✅ {label}: {count_str} komik berhasil diperbarui [{elapsed:.1f}s]", flush=True)

    total_elapsed = time.time() - start_time
    print("═" * banner_width, flush=True)
    print("📋 RINGKASAN REFRESH SOURCE STATS", flush=True)
    print("═" * banner_width, flush=True)
    for stat in refreshed_rows:
        icon = SOURCE_ICONS.get(stat.source_name, "📖")
        label = SOURCE_LABELS.get(stat.source_name, stat.source_name.title())
        count_str = (
            f"{stat.source_comic_count:>7,}"
            if stat.source_comic_count is not None
            else "      -"
        )
        time_str = _format_datetime(stat.last_refreshed_at)
        if stat.last_error:
            err_msg = (
                stat.last_error.split(":")[0]
                if ":" in stat.last_error
                else stat.last_error[:30]
            )
            print(
                f"  {icon} {label:<14} : {count_str} komik  │  Refreshed: {time_str}  │  ⚠️  [Gagal: {err_msg}]",
                flush=True,
            )
        else:
            print(
                f"  {icon} {label:<14} : {count_str} komik  │  Refreshed: {time_str}  │  ✅  [Sukses]",
                flush=True,
            )
    print("═" * banner_width, flush=True)
    print(f"✨ Selesai dalam {total_elapsed:.1f}s ({success_count} sukses, {fail_count} gagal)", flush=True)
    print("═" * banner_width + "\n", flush=True)


if __name__ == "__main__":
    try:
        asyncio.run(main(sys.argv[1:]))
    except ValueError as exc:
        print(f"Error argumen: {exc}")
        sys.exit(1)
