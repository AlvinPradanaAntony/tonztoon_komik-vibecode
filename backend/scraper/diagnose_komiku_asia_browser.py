"""
Diagnostic runner untuk membandingkan engine browser Komiku Asia.

Contoh lokal:
    python -m scraper.diagnose_komiku_asia_browser --engine scrapling
    python -m scraper.diagnose_komiku_asia_browser --engine cloakbrowser
    python -m scraper.diagnose_komiku_asia_browser --engine both

Contoh Linux CI/headed virtual display:
    xvfb-run -a -s "-screen 0 1366x768x24" \
      python -m scraper.diagnose_komiku_asia_browser --engine both
"""

import argparse
import asyncio
import logging
import os
import time

from scraper.sources.komiku_asia_scraper import KomikuAsiaScraper


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Uji fetch latest Komiku Asia dengan Scrapling dan/atau CloakBrowser."
    )
    parser.add_argument(
        "--engine",
        choices=("scrapling", "cloakbrowser", "both"),
        default="both",
        help="Engine browser yang diuji.",
    )
    parser.add_argument(
        "--page",
        type=int,
        default=1,
        help="Halaman latest yang diuji.",
    )
    parser.add_argument(
        "--cloak-headless",
        action="store_true",
        help="Jalankan CloakBrowser dengan headless=True untuk eksperimen terpisah.",
    )
    parser.add_argument(
        "--show",
        type=int,
        default=5,
        help="Jumlah judul pertama yang ditampilkan dari hasil fetch.",
    )
    parser.add_argument(
        "--debug-dir",
        default="",
        help="Folder untuk menyimpan screenshot/HTML CloakBrowser saat gagal.",
    )
    return parser.parse_args()


async def run_engine(engine: str, *, page: int, cloak_headless: bool, show: int) -> bool:
    os.environ["KOMIKU_ASIA_BROWSER_ENGINE"] = engine
    if engine == "cloakbrowser":
        os.environ["KOMIKU_ASIA_CLOAK_HEADLESS"] = "true" if cloak_headless else "false"
    else:
        os.environ.pop("KOMIKU_ASIA_CLOAK_HEADLESS", None)

    scraper = KomikuAsiaScraper()
    started = time.perf_counter()
    print(f"\n=== komiku_asia engine={engine} page={page} ===")
    try:
        comics = await scraper.get_latest_updates(page=page)
    except Exception as exc:
        elapsed = time.perf_counter() - started
        print(f"FAIL after {elapsed:.1f}s: {type(exc).__name__}: {exc}")
        return False
    finally:
        await scraper.close()

    elapsed = time.perf_counter() - started
    print(f"OK after {elapsed:.1f}s: {len(comics)} listing items")
    for index, comic in enumerate(comics[:show], start=1):
        title = comic.get("title") or "<no title>"
        latest = comic.get("latest_chapter") or "-"
        print(f"{index}. {title} [{latest}]")
    return bool(comics)


async def main_async() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )
    if args.debug_dir:
        os.environ["KOMIKU_ASIA_CLOAK_DEBUG_DIR"] = args.debug_dir

    engines = ["scrapling", "cloakbrowser"] if args.engine == "both" else [args.engine]
    results = [
        await run_engine(
            engine,
            page=args.page,
            cloak_headless=args.cloak_headless,
            show=args.show,
        )
        for engine in engines
    ]
    return 0 if all(results) else 1


def main() -> None:
    raise SystemExit(asyncio.run(main_async()))


if __name__ == "__main__":
    main()
