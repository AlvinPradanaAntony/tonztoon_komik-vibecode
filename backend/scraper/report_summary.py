"""
Tonztoon Komik — GitHub Actions Step Summary Generator.

Membuat ringkasan eksekusi Markdown yang rapi untuk $GITHUB_STEP_SUMMARY
dari log eksekusi scraper, popular sync, atau refresh source stats.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

# Pastikan output selalu UTF-8 di environment mana pun tanpa crash charmap
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

CLEAN_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def clean_ansi(text: str) -> str:
    """Bersihkan kode escape ANSI dari output log terminal."""
    return CLEAN_ANSI_RE.sub("", text)


def detect_log_has_errors(lines: list[str]) -> bool:
    """Deteksi apakah log mencatat error yang perlu dilaporkan."""
    for line in lines:
        lowered = line.lower()
        if (
            " error " in f" {lowered} "
            or re.search(r"\b[1-9][0-9]* errors\b", lowered) is not None
            or "failed:" in lowered
            or "gagal" in lowered
            or "✗" in line
        ):
            return True
    return False


def build_latest_summary(
    lines: list[str],
    *,
    trigger_source: str,
    source: str,
    max_pages: str,
    early_stop: str,
    exit_status: str,
    completed_at: str,
) -> str:
    """Generate Markdown summary untuk workflow Latest Sync."""
    source_re = re.compile(r"Scraper:\s+([a-z_]+)\s+\(")
    done_re = re.compile(
        r"Selesai scraper ([a-z_]+): "
        r"(\d+) pages, (\d+) listing items, (\d+) candidates, "
        r"(\d+) unchanged, (\d+) comics, (\d+) chapter metadata, "
        r"(\d+) chapter images pre-warmed, (\d+) push events, "
        r"(\d+) push messages, (\d+) skipped, (\d+) errors"
    )
    last_error_re = re.compile(r"(?:Last error ([a-z_]+)|Scraper ([a-z_]+) failed):\s*(.+)")
    update_re = re.compile(r"Done:\s+(.+?)\s+[—-]\s+(\d+) chapters metadata,\s+(\d+) images pre-warmed")

    summaries = []
    updates = []
    errors = []
    source_last_errors: dict[str, str] = {}
    current_source = "unknown"

    for raw_line in lines:
        line = clean_ansi(raw_line)
        source_match = source_re.search(line)
        if source_match:
            current_source = source_match.group(1)

        done_match = done_re.search(line)
        if done_match:
            summaries.append(done_match.groups())

        last_err_match = last_error_re.search(line)
        if last_err_match:
            src = last_err_match.group(1) or last_err_match.group(2)
            source_last_errors[src] = last_err_match.group(3).strip()

        update_match = update_re.search(line)
        if update_match and len(updates) < 5:
            title, chapters, images = update_match.groups()
            updates.append((current_source, title.strip(), chapters, images))

        lowered = line.lower()
        if (
            " error " in f" {lowered} "
            or re.search(r"\b[1-9][0-9]* errors\b", lowered) is not None
            or "failed:" in lowered
            or "gagal" in lowered
            or "✗" in line
        ):
            errors.append(line)

    has_errors = bool(errors or source_last_errors)
    if exit_status == "0" and not has_errors:
        conclusion = "success"
    elif exit_status == "0":
        conclusion = "completed_with_errors"
    else:
        conclusion = "failed"

    out = [
        "## 🕷️ Scraper summary",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Trigger source | {trigger_source} |",
        f"| Source | {source} |",
        f"| Latest pages | {max_pages} |",
        f"| Early stop | {early_stop} |",
        f"| Exit status | {exit_status} ({conclusion}) |",
        f"| Completed at | {completed_at} |",
        "",
    ]

    if summaries:
        out.extend([
            "### Per-source latest results",
            "",
            "| Source | Pages | Listing | Candidates | Unchanged | Comics updated | Chapter metadata | Images pre-warmed | Push events | Push queued | Skipped | Errors |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ])
        for row in summaries:
            src, p, l, c, u, cm, m, img, pe, pm, sk, er = row
            out.append(f"| {src} | {p} | {l} | {c} | {u} | {cm} | {m} | {img} | {pe} | {pm} | {sk} | {er} |")
        out.append("")

        totals = {
            "Pages": 0, "Listing": 0, "Candidates": 0, "Unchanged": 0,
            "Comics": 0, "Chapter meta": 0, "Pre-warmed": 0, "Push events": 0,
            "Push queued": 0, "Skipped": 0, "Errors": 0,
        }
        for row in summaries:
            _, p, l, c, u, cm, m, img, pe, pm, sk, er = row
            totals["Pages"] += int(p)
            totals["Listing"] += int(l)
            totals["Candidates"] += int(c)
            totals["Unchanged"] += int(u)
            totals["Comics"] += int(cm)
            totals["Chapter meta"] += int(m)
            totals["Pre-warmed"] += int(img)
            totals["Push events"] += int(pe)
            totals["Push queued"] += int(pm)
            totals["Skipped"] += int(sk)
            totals["Errors"] += int(er)

        out.extend([
            "### Aggregate totals",
            "",
            "| Metric | Value |",
            "|---|---:|",
        ])
        for key in ("Pages", "Listing", "Candidates", "Unchanged", "Comics", "Chapter meta", "Pre-warmed", "Push events", "Push queued", "Skipped", "Errors"):
            out.append(f"| {key} | {totals[key]} |")
        out.append("")

    if source_last_errors:
        out.extend([
            "### ⚠️ Source Last Errors",
            "",
            "| Source | Last Error |",
            "|---|---|",
        ])
        for src, err in sorted(source_last_errors.items()):
            clean_err = err.replace("|", "\\|")
            out.append(f"| {src} | `{clean_err}` |")
        out.append("")

    out.extend([
        "### Sample updated comics",
        "",
    ])
    if updates:
        out.extend([
            "| Source | Comic | Chapter metadata | Images pre-warmed |",
            "|---|---|---:|---:|",
        ])
        for src, title, ch, img in updates:
            clean_title = title.replace("|", "\\|")
            out.append(f"| {src} | {clean_title} | {ch} | {img} |")
    else:
        out.append("No updated comics were logged in this run.")
    out.append("")

    if errors:
        out.extend([
            "### Error lines",
            "",
            "```text",
        ])
        for line in errors[-40:]:
            out.append(line)
        out.extend([
            "```",
            "",
        ])

    return "\n".join(out)


def build_popular_summary(
    lines: list[str],
    *,
    trigger_source: str,
    source: str,
    popular_pages: str,
    popular_no_early_stop: str,
    early_stop: str,
    exit_status: str,
    completed_at: str,
) -> str:
    """Generate Markdown summary untuk workflow Popular Feed Sync."""
    source_re = re.compile(r"Scraper:\s+([a-z_]+)\s+\(")
    done_re = re.compile(
        r"Selesai scraper ([a-z_]+): "
        r"(\d+) pages, (\d+) listing items, (\d+) candidates, "
        r"(\d+) unchanged, (\d+) comics, (\d+) chapter metadata, "
        r"(\d+) chapter images pre-warmed, (\d+) push events, "
        r"(\d+) push messages, (\d+) skipped, (\d+) errors"
    )
    popular_page_re = re.compile(r"Ringkasan popular page (\d+): (\d+) kandidat baru, (\d+) existing ditandai")
    new_re = re.compile(r"Kandidat popular baru:\s+(.+?)\s+\(")
    existing_re = re.compile(r"Mark popular:\s+(.+?)\s+\(")
    done_comic_re = re.compile(r"Done:\s+(.+?)\s+[—-]\s+(\d+) chapters metadata,\s+(\d+) images pre-warmed")
    last_error_re = re.compile(r"(?:Last error ([a-z_]+)|Scraper ([a-z_]+) failed):\s*(.+)")

    summaries = []
    page_rows = []
    samples = []
    errors = []
    source_last_errors: dict[str, str] = {}
    current_source = "unknown"

    for raw_line in lines:
        line = clean_ansi(raw_line)
        source_match = source_re.search(line)
        if source_match:
            current_source = source_match.group(1)

        done_match = done_re.search(line)
        if done_match:
            summaries.append(done_match.groups())

        page_match = popular_page_re.search(line)
        if page_match:
            page, candidates, existing = page_match.groups()
            page_rows.append((current_source, page, candidates, existing))

        if len(samples) < 5:
            new_match = new_re.search(line)
            if new_match:
                samples.append((current_source, "new", new_match.group(1).strip(), "-", "-"))
                continue
            existing_match = existing_re.search(line)
            if existing_match:
                samples.append((current_source, "existing", existing_match.group(1).strip(), "-", "-"))
                continue
            done_match = done_comic_re.search(line)
            if done_match:
                title, chapters, images = done_match.groups()
                samples.append((current_source, "processed", title.strip(), chapters, images))

        last_err_match = last_error_re.search(line)
        if last_err_match:
            src = last_err_match.group(1) or last_err_match.group(2)
            source_last_errors[src] = last_err_match.group(3).strip()

        lowered = line.lower()
        if (
            " error " in f" {lowered} "
            or re.search(r"\b[1-9][0-9]* errors\b", lowered) is not None
            or "failed:" in lowered
            or "gagal" in lowered
            or "✗" in line
        ):
            errors.append(line)

    has_errors = bool(errors or source_last_errors)
    if exit_status == "0" and not has_errors:
        conclusion = "success"
    elif exit_status == "0":
        conclusion = "completed_with_errors"
    else:
        conclusion = "failed"

    out = [
        "## 🔥 Popular sync summary",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Trigger source | {trigger_source} |",
        f"| Source | {source} |",
        f"| Popular pages | {popular_pages} |",
        f"| Popular no early-stop | {popular_no_early_stop} |",
        f"| Early stop | {early_stop} |",
        f"| Exit status | {exit_status} ({conclusion}) |",
        f"| Completed at | {completed_at} |",
        "",
    ]

    if summaries:
        out.extend([
            "### Per-source popular results",
            "",
            "| Source | Pages | Listing | New candidates | Existing/unchanged | Comics updated | Chapter metadata | Images pre-warmed | Push events | Push queued | Skipped | Errors |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ])
        for row in summaries:
            src, p, l, c, u, cm, m, img, pe, pm, sk, er = row
            out.append(f"| {src} | {p} | {l} | {c} | {u} | {cm} | {m} | {img} | {pe} | {pm} | {sk} | {er} |")
        out.append("")

        totals = {
            "Pages": 0, "Listing": 0, "New candidates": 0, "Existing/unchanged": 0,
            "Comics updated": 0, "Chapter meta": 0, "Pre-warmed": 0, "Push events": 0,
            "Push queued": 0, "Skipped": 0, "Errors": 0,
        }
        for row in summaries:
            _, p, l, c, u, cm, m, img, pe, pm, sk, er = row
            totals["Pages"] += int(p)
            totals["Listing"] += int(l)
            totals["New candidates"] += int(c)
            totals["Existing/unchanged"] += int(u)
            totals["Comics updated"] += int(cm)
            totals["Chapter meta"] += int(m)
            totals["Pre-warmed"] += int(img)
            totals["Push events"] += int(pe)
            totals["Push queued"] += int(pm)
            totals["Skipped"] += int(sk)
            totals["Errors"] += int(er)

        out.extend([
            "### Aggregate totals",
            "",
            "| Metric | Value |",
            "|---|---:|",
        ])
        for key in ("Pages", "Listing", "New candidates", "Existing/unchanged", "Comics updated", "Chapter meta", "Pre-warmed", "Push events", "Push queued", "Skipped", "Errors"):
            out.append(f"| {key} | {totals[key]} |")
        out.append("")

    if source_last_errors:
        out.extend([
            "### ⚠️ Source Last Errors",
            "",
            "| Source | Last Error |",
            "|---|---|",
        ])
        for src, err in sorted(source_last_errors.items()):
            clean_err = err.replace("|", "\\|")
            out.append(f"| {src} | `{clean_err}` |")
        out.append("")

    if page_rows:
        out.extend([
            "### Popular page summary",
            "",
            "| Source | Page | New candidates | Existing marked |",
            "|---|---:|---:|---:|",
        ])
        for src, page, cands, existing in page_rows:
            out.append(f"| {src} | {page} | {cands} | {existing} |")
        out.append("")

    out.extend([
        "### Sample processed comics",
        "",
    ])
    if samples:
        out.extend([
            "| Source | Kind | Comic | Chapter metadata | Images pre-warmed |",
            "|---|---|---|---:|---:|",
        ])
        for src, kind, title, ch, img in samples:
            clean_title = title.replace("|", "\\|")
            out.append(f"| {src} | {kind} | {clean_title} | {ch} | {img} |")
    else:
        out.append("No processed comics were logged in this run.")
    out.append("")

    if errors:
        out.extend([
            "### Error lines",
            "",
            "```text",
        ])
        for line in errors[-40:]:
            out.append(line)
        out.extend([
            "```",
            "",
        ])

    return "\n".join(out)


LABEL_TO_SOURCE: dict[str, str] = {
    "komiku": "komiku",
    "komiku asia": "komiku_asia",
    "komiku_asia": "komiku_asia",
    "shinigami": "shinigami",
    "voratoon": "voratoon",
    "kiryuu": "kiryuu",
}


def build_stats_summary(
    lines: list[str],
    *,
    trigger_source: str,
    source_filter: str,
    exit_status: str,
    completed_at: str,
) -> str:
    """Generate Markdown summary untuk workflow Source Stats Refresh."""
    table_row_re = re.compile(
        r"^\s*.*?\b(Komiku Asia|Komiku|Shinigami|Voratoon|Kiryuu)\s*:\s*([\d,]+|-)\s*komik\s*[│|]\s*"
        r"Refreshed:\s*([^│|]+?)\s*[│|]\s*"
        r"(.*)$",
        re.IGNORECASE,
    )
    fallback_row_re = re.compile(
        r"\[SOURCE_STAT_ROW\]\s+([a-z_]+):\s+count=(\d+|None|-)\s+last_refreshed_at=([^\s]+)\s+last_error=(.+)"
    )

    rows: list[tuple[str, str, str, str | None]] = []
    errors: list[str] = []
    seen_sources: set[str] = set()

    for raw_line in lines:
        line = clean_ansi(raw_line)

        tm = table_row_re.search(line)
        if tm:
            label, count_str, refreshed, status_str = tm.groups()
            src = LABEL_TO_SOURCE.get(label.strip().lower(), label.strip().lower())
            if src in seen_sources:
                continue
            seen_sources.add(src)

            count = count_str.replace(",", "").strip()
            count_val = "-" if count in ("-", "None") else count
            refreshed_val = refreshed.strip()

            is_err = any(k in status_str.lower() for k in ("gagal", "error", "❌", "⚠️"))
            if is_err:
                err_msg = status_str.strip()
                m_err = re.search(r"\[?(?:Gagal|Error):\s*([^\]]+)\]?", status_str, re.IGNORECASE)
                if m_err:
                    err_msg = m_err.group(1).strip()
                errors.append(f"{src}: {err_msg}")
                rows.append((src, count_val, refreshed_val, err_msg))
            else:
                rows.append((src, count_val, refreshed_val, None))
            continue

        fm = fallback_row_re.search(line)
        if fm:
            src, count, refreshed, last_err = fm.groups()
            if src in seen_sources:
                continue
            seen_sources.add(src)
            last_err = last_err.strip()
            err_val = None if last_err in ("None", "") else last_err
            rows.append((src, count, refreshed, err_val))
            if err_val:
                errors.append(f"{src}: {err_val}")

    has_errors = bool(errors)

    if exit_status == "0" and not has_errors:
        conclusion = "success"
    elif exit_status == "0":
        conclusion = "completed_with_errors"
    else:
        conclusion = "failed"

    out = [
        "## 📊 Source stats refresh summary",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Trigger source | {trigger_source} |",
        f"| Source filter | {source_filter or '<all sources>'} |",
        f"| Exit status | {exit_status} ({conclusion}) |",
        f"| Completed at | {completed_at} |",
        "",
    ]

    if rows:
        out.extend([
            "### Result rows",
            "",
            "| Source | Comic Count | Last Refreshed (UTC) | Status |",
            "|---|---:|---|---|",
        ])
        for src, count, refreshed, err in rows:
            count_str = f"{int(count):,}" if count.isdigit() else "-"
            status_str = "✅ Sukses" if not err else f"⚠️ Gagal (`{err[:60]}`)"
            out.append(f"| {src} | {count_str} | {refreshed} | {status_str} |")
        out.append("")

    if errors:
        out.extend([
            "### ⚠️ Source errors",
            "",
            "```text",
        ])
        for err in errors:
            out.append(err)
        out.extend([
            "```",
            "",
        ])

    return "\n".join(out)


def resolve_path(path_str: str | None) -> Path | None:
    """Cari path file di CWD, parent dir (..), subfolder (backend/), atau filename saja."""
    if not path_str:
        return None
    p = Path(path_str)
    candidates = [
        p,
        Path("..") / p,
        Path("..") / p.name,
        Path("backend") / p,
        Path("backend") / p.name,
        Path(p.name),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate GitHub Actions step summary from log.")
    parser.add_argument("--log-file", required=True, help="Path to input log file")
    parser.add_argument("--mode", choices=["latest", "popular", "stats"], default="latest")
    parser.add_argument("--status-file", help="Path to file containing process exit status")
    parser.add_argument("--trigger-source", default="manual")
    parser.add_argument("--source", default="all")
    parser.add_argument("--max-pages", default="default")
    parser.add_argument("--popular-pages", default="10")
    parser.add_argument("--popular-no-early-stop", default="false")
    parser.add_argument("--early-stop", default="default")
    args = parser.parse_args()

    completed_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    exit_status = "0"
    if args.status_file:
        status_path = resolve_path(args.status_file)
        if status_path and status_path.exists():
            exit_status = status_path.read_text(encoding="utf-8").strip() or "0"

    log_path = resolve_path(args.log_file)
    if not log_path or not log_path.exists():
        mode_title = {
            "latest": "🕷️ Scraper summary",
            "popular": "🔥 Popular sync summary",
            "stats": "📊 Source stats refresh summary",
        }.get(args.mode, "Scraper summary")
        print(f"## {mode_title}")
        print()
        print("| Metric | Value |")
        print("|---|---|")
        print(f"| Trigger source | {args.trigger_source} |")
        print(f"| Source | {args.source} |")
        print(f"| Exit status | {exit_status} (failed/log missing) |")
        print(f"| Completed at | {completed_at} |")
        print()
        print(
            f"> [!WARNING]\n> Log file `{args.log_file}` was not produced. "
            "The scraper step may have failed or been skipped before writing logs."
        )
        return


    text = log_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()

    if args.mode == "latest":
        summary = build_latest_summary(
            lines,
            trigger_source=args.trigger_source,
            source=args.source,
            max_pages=args.max_pages,
            early_stop=args.early_stop,
            exit_status=exit_status,
            completed_at=completed_at,
        )
    elif args.mode == "popular":
        summary = build_popular_summary(
            lines,
            trigger_source=args.trigger_source,
            source=args.source,
            popular_pages=args.popular_pages,
            popular_no_early_stop=args.popular_no_early_stop,
            early_stop=args.early_stop,
            exit_status=exit_status,
            completed_at=completed_at,
        )
    else:
        summary = build_stats_summary(
            lines,
            trigger_source=args.trigger_source,
            source_filter=args.source,
            exit_status=exit_status,
            completed_at=completed_at,
        )

    print(summary)

    # Append recent raw log snippet
    print("### Recent scraper log")
    print()
    print("```text")
    for line in lines[-120:]:
        print(clean_ansi(line))
    print("```")


if __name__ == "__main__":
    main()
