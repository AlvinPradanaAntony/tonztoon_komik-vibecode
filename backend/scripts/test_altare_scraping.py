"""
Script uji coba konektivitas mandiri (Standalone Diagnostic) untuk Altare.
Menguji apakah IP server Altare terkena HTTP 403 saat mengakses Shinigami dan Voratoon
tanpa memodifikasi atau menulis data ke database.

Penggunaan di terminal server Altare:
    python backend/scripts/test_altare_scraping.py
atau jika menggunakan xvfb:
    xvfb-run -a -s "-screen 0 1366x768x24" python backend/scripts/test_altare_scraping.py
"""

import asyncio
import os
import sys
from pathlib import Path

# Tambahkan backend ke PYTHONPATH
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

import httpx


async def check_public_ip():
    print("\n[1/3] 🌐 Memeriksa IP Publik Server Altare...")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get("https://api.ipify.org?format=json")
            if resp.status_code == 200:
                ip = resp.json().get("ip")
                print(f"  ✅ IP Publik Altare: {ip}")
                return ip
    except Exception as exc:
        print(f"  ⚠️ Gagal mendapatkan IP publik: {exc}")
    return "Unknown"


async def check_voratoon():
    print("\n[2/3] 🔍 Menguji Scraping Voratoon...")
    try:
        from scraper.sources.voratoon_api import (
            build_voratoon_series_index_url,
            fetch_voratoon_api_json,
            get_voratoon_base_url,
        )

        base_url = get_voratoon_base_url()
        api_url = build_voratoon_series_index_url(take=5, sort="latest")
        print(f"  Target: {base_url} (via Server Action API)")

        data = await fetch_voratoon_api_json(api_url, referer_url=base_url, timeout=20.0)
        items = data.get("items") or data.get("data") or []
        count = len(items) if isinstance(items, list) else 0

        print(f"  🎉 [SUKSES - BEBAS 403] Voratoon berhasil diakses!")
        print(f"  📦 Berhasil mengambil {count} listing komik.")
        return True
    except httpx.HTTPStatusError as exc:
        print(f"  ❌ [GAGAL - HTTP {exc.response.status_code}] Voratoon diblokir!")
        print(f"  Detail: {exc}")
        return False
    except Exception as exc:
        print(f"  ❌ [ERROR] Kendala saat mengakses Voratoon: {exc}")
        return False


async def check_shinigami():
    print("\n[3/3] 🔍 Menguji Scraping Shinigami...")
    try:
        from scrapling.fetchers import Fetcher
        from scraper.sources.shinigami_api import (
            SHINIGAMI_API_BASE_URL,
            SHINIGAMI_BASE_URL,
            build_shinigami_api_headers,
            build_shinigami_manga_list_url,
        )

        url = build_shinigami_manga_list_url(page=1, page_size=5, sort="latest")
        headers = build_shinigami_api_headers(SHINIGAMI_BASE_URL)
        print(f"  Target: {url}")

        res = Fetcher.get(url, headers=headers, stealthy_headers=True, timeout=20.0)
        status = getattr(res, "status", 0)

        if status == 200:
            print(f"  🎉 [SUKSES - BEBAS 403] Shinigami direct API berhasil (HTTP 200)!")
            return True
        elif status == 403:
            print(f"  ⚠️ Shinigami direct API menghasilkan HTTP 403. Mencoba Stealth Solver...")
            from scraper.sources.shinigami_scraper import ShinigamiScraper
            session = await ShinigamiScraper.get_session()
            stealth_res = await session.fetch(url, headers=headers, timeout=30.0)
            stealth_status = getattr(stealth_res, "status", 0)
            if stealth_status == 200:
                print(f"  🎉 [SUKSES - BEBAS 403] Shinigami via Stealth Session berhasil (HTTP 200)!")
                return True
            else:
                print(f"  ❌ [GAGAL] Shinigami Stealth Session mengembalikan HTTP {stealth_status}")
                return False
        else:
            print(f"  ⚠️ Status HTTP Shinigami: {status}")
            return False
    except Exception as exc:
        print(f"  ❌ [ERROR] Kendala saat mengakses Shinigami: {exc}")
        return False


async def main():
    print("=" * 60)
    print("🚀 TONZTOON — ALTARE STANDALONE SCRAPING CONNECTIVITY TEST")
    print("=" * 60)

    ip = await check_public_ip()
    v_ok = await check_voratoon()
    s_ok = await check_shinigami()

    print("\n" + "=" * 60)
    print("📋 RINGKASAN HASIL:")
    print(f"  - IP Server Altare: {ip}")
    print(f"  - Voratoon        : {'✅ LOLOS (Bebas 403)' if v_ok else '❌ GAGAL (Terkena 403 / Error)'}")
    print(f"  - Shinigami       : {'✅ LOLOS (Bebas 403)' if s_ok else '❌ GAGAL (Terkena 403 / Error)'}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
