"""
Shared helper untuk endpoint API & Web mirror Voratoon yang dipakai lintas scraper.
Mendukung Cloudflare DNS-over-HTTPS (DoH) & direct host resolution untuk domain voratoon.co,
serta Next.js proxy-session handshake untuk arsitektur API-first.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import logging
import re
import time
from typing import Any
from urllib.parse import parse_qs, quote, urlencode, urlparse

import httpx

from scraper.utils import clean_text

logger = logging.getLogger("scraper.voratoon")

DEFAULT_VORATOON_BASE_URL = "https://voratoon.co"
VORATOON_BASE_URL = DEFAULT_VORATOON_BASE_URL
VORATOON_API_BASE_URL = f"{VORATOON_BASE_URL}/api/proxy"
DEFAULT_SERIES_INDEX_TAKE = 30
DEFAULT_POPULAR_TAKE = 20
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36"
)

CLOUDFLARE_DOH_URL = "https://cloudflare-dns.com/dns-query"
VORATOON_CO_FALLBACK_IPS: tuple[str, ...] = ("104.21.70.3", "172.67.217.41")

_CURRENT_VORATOON_BASE_URL: str = DEFAULT_VORATOON_BASE_URL
_LAST_DISCOVERED_TIME: float = 0.0
_DNS_RESOLVER_CONFIGURED: bool = False
_RESOLVED_VORATOON_IPS: list[str] = list(VORATOON_CO_FALLBACK_IPS)

_VORATOON_COOKIES: dict[str, str] = {}
_LAST_SESSION_TIME: float = 0.0


def ensure_voratoon_dns_configured() -> None:
    """
    Konfigurasi Cloudflare DNS-over-HTTPS (DoH) & direct host resolution untuk domain voratoon.co.
    Menghindarkan pemblokiran DNS ISP lokal (Internet Positif / DNS poisoning) tanpa perlu VPN OS.
    """
    global _DNS_RESOLVER_CONFIGURED, _RESOLVED_VORATOON_IPS
    if _DNS_RESOLVER_CONFIGURED:
        return

    import socket

    # 1. Patch socket.getaddrinfo untuk standard Python network calls (httpx, requests, urllib)
    _orig_getaddrinfo = socket.getaddrinfo

    def _patched_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
        if host == "voratoon.co" and _RESOLVED_VORATOON_IPS:
            return _orig_getaddrinfo(_RESOLVED_VORATOON_IPS[0], port, family, type, proto, flags)
        return _orig_getaddrinfo(host, port, family, type, proto, flags)

    socket.getaddrinfo = _patched_getaddrinfo

    # 2. Patch curl_cffi Session untuk Scrapling Fetcher
    try:
        import curl_cffi.requests.session as cs
        from curl_cffi.curl import CurlOpt

        _orig_session_init = cs.Session.__init__

        def _patched_session_init(self, *args, **kwargs):
            curl_opts = kwargs.get("curl_options") or {}
            if CurlOpt.DOH_URL not in curl_opts:
                curl_opts[CurlOpt.DOH_URL] = CLOUDFLARE_DOH_URL
            if CurlOpt.RESOLVE not in curl_opts and _RESOLVED_VORATOON_IPS:
                curl_opts[CurlOpt.RESOLVE] = [
                    f"voratoon.co:443:{ip}" for ip in _RESOLVED_VORATOON_IPS
                ] + [f"voratoon.co:80:{ip}" for ip in _RESOLVED_VORATOON_IPS]
            kwargs["curl_options"] = curl_opts
            _orig_session_init(self, *args, **kwargs)

        cs.Session.__init__ = _patched_session_init
    except Exception as exc:
        logger.debug("Gagal menyuntikkan DoH ke curl_cffi: %s", exc)

    _DNS_RESOLVER_CONFIGURED = True


# Inisialisasi DNS resolver Cloudflare pada saat module dimuat
ensure_voratoon_dns_configured()


def get_voratoon_base_url() -> str:
    """Ambil base URL aktif saat ini untuk Voratoon."""
    return _CURRENT_VORATOON_BASE_URL


def get_voratoon_api_base_url() -> str:
    """Ambil base URL endpoint API proxy aktif saat ini untuk Voratoon."""
    return f"{get_voratoon_base_url()}/api/proxy"


def set_voratoon_base_url(url: str) -> None:
    """Set base URL Voratoon aktif."""
    global _CURRENT_VORATOON_BASE_URL, VORATOON_BASE_URL, VORATOON_API_BASE_URL
    clean = url.strip().rstrip("/")
    _CURRENT_VORATOON_BASE_URL = clean
    VORATOON_BASE_URL = clean
    VORATOON_API_BASE_URL = f"{clean}/api/proxy"


def discover_voratoon_base_url(timeout: float = 6.0, force: bool = False) -> str:
    """
    Auto-discover mirror web Voratoon aktif dari landing page canonical (https://voratoon.id).
    Jika voratoon.co mengalami kendala jaringan tak terduga, fungsi ini dapat mendeteksi mirror numerik aktif.
    """
    global _CURRENT_VORATOON_BASE_URL, VORATOON_BASE_URL, _LAST_DISCOVERED_TIME
    if not force and _LAST_DISCOVERED_TIME > 0 and (time.time() - _LAST_DISCOVERED_TIME) < 3600:
        return _CURRENT_VORATOON_BASE_URL

    try:
        from scrapling.fetchers import Fetcher

        page = Fetcher.get("https://voratoon.id", stealthy_headers=True, timeout=timeout)
        hrefs = page.css("a::attr(href)").getall()
        for href in hrefs:
            match = re.match(r"^https?://(v?\d+\.voratoon\.com)", href.strip())
            if match:
                discovered = f"https://{match.group(1)}"
                set_voratoon_base_url(discovered)
                _LAST_DISCOVERED_TIME = time.time()
                return discovered
    except Exception as exc:
        logger.warning(
            "Gagal auto-discover Voratoon base URL dari voratoon.id: %s", exc
        )
    return _CURRENT_VORATOON_BASE_URL


def normalize_voratoon_web_url(url: str | None) -> str:
    """Normalisasi URL web/referer Voratoon ke canonical base URL (misal https://voratoon.co)."""
    base_url = get_voratoon_base_url()
    if not url:
        return f"{base_url}/"
    cleaned = clean_text(url)
    if not cleaned:
        return f"{base_url}/"
    normalized = re.sub(
        r"^https?://(?:v?\d+|cvr|cdn)?\.?voratoon\.(?:com|id|co)",
        base_url,
        cleaned,
        flags=re.IGNORECASE,
    )
    if not normalized.startswith("http"):
        normalized = f"{base_url}/{normalized.lstrip('/')}"
    return normalized


def extract_cover_from_src(src: str | None) -> str | None:
    """Ekstrak direct cover URL dari image src, meng-unquote parameter jika lewat /api/cover?src=..."""
    if not src:
        return None
    raw = clean_text(src)
    if not raw:
        return None
    if "/api/cover?" in raw:
        parsed = urlparse(raw)
        qs = parse_qs(parsed.query)
        if "src" in qs and qs["src"]:
            return qs["src"][0].strip()
    return raw


def build_voratoon_api_headers(referer_url: str | None = None) -> dict[str, str]:
    base_url = get_voratoon_base_url()
    referer = normalize_voratoon_web_url(referer_url)
    return {
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7",
        "Referer": referer,
        "Origin": base_url,
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
    }


def get_voratoon_cookies() -> dict[str, str]:
    return dict(_VORATOON_COOKIES)


def set_voratoon_cookies(cookies: dict[str, str]) -> None:
    global _VORATOON_COOKIES, _LAST_SESSION_TIME
    _VORATOON_COOKIES = dict(cookies)
    _LAST_SESSION_TIME = time.time()


def ensure_voratoon_session(timeout: float = 20.0, force: bool = False) -> dict[str, str]:
    """
    Inisialisasi atau refresh session token 'vt_proxy' pada Voratoon Next.js reverse-proxy.
    Handshake 2 tahap:
    1. GET / -> Ambil cookie awal 'vt_proxy'
    2. POST /api/proxy-session -> Validasi token sesi (HTTP 204)
    """
    global _VORATOON_COOKIES, _LAST_SESSION_TIME
    now = time.time()
    if not force and _VORATOON_COOKIES and (now - _LAST_SESSION_TIME) < 1800:
        return dict(_VORATOON_COOKIES)

    ensure_voratoon_dns_configured()
    base_url = get_voratoon_base_url()
    from scrapling.fetchers import Fetcher

    cookies: dict[str, str] = {}
    try:
        # 1. Mengambil cookie awal vt_proxy dari homepage
        home_page = Fetcher.get(f"{base_url}/", stealthy_headers=True, timeout=timeout)
        cookies = dict(home_page.cookies or {})

        # 2. Handshake session token ke endpoint proxy-session
        session_headers = {
            "Referer": f"{base_url}/",
            "Origin": base_url,
            "Accept": "application/json",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
        }
        session_res = Fetcher.post(
            f"{base_url}/api/proxy-session",
            headers=session_headers,
            cookies=cookies,
            stealthy_headers=True,
            timeout=timeout,
        )
        if session_res.cookies:
            cookies.update(session_res.cookies)
    except Exception as exc:
        logger.warning("Gagal melakukan handshake proxy session Voratoon: %s", exc)

    _VORATOON_COOKIES = cookies
    _LAST_SESSION_TIME = time.time()
    return dict(_VORATOON_COOKIES)


async def fetch_voratoon_api_json(
    api_url: str,
    *,
    referer_url: str | None = None,
    timeout: float = 30.0,
) -> dict[str, Any]:
    from scrapling.fetchers import Fetcher

    ensure_voratoon_dns_configured()
    cookies = await asyncio.to_thread(ensure_voratoon_session, timeout=timeout)
    headers = build_voratoon_api_headers(referer_url)

    def do_request(req_cookies: dict[str, str]):
        return Fetcher.get(
            api_url,
            headers=headers,
            cookies=req_cookies,
            stealthy_headers=True,
            timeout=timeout,
        )

    res = await asyncio.to_thread(do_request, cookies)
    status = getattr(res, "status", 0)

    # Jika session expired atau 403 proxy_session_required, refresh session dan retry 1 kali
    if status == 403:
        logger.info("Respon 403 diterima dari %s, mencoba refresh proxy session...", api_url)
        new_cookies = await asyncio.to_thread(ensure_voratoon_session, timeout=timeout, force=True)
        res = await asyncio.to_thread(do_request, new_cookies)
        status = getattr(res, "status", 0)

    if status != 200:
        req = httpx.Request("GET", api_url, headers=headers)
        resp = httpx.Response(status, request=req, content=getattr(res, "body", b""))
        raise httpx.HTTPStatusError(
            f"API Voratoon HTTP {status} untuk {api_url}",
            request=req,
            response=resp,
        )

    try:
        data = res.json()
    except Exception as exc:
        raise RuntimeError(f"Gagal parse JSON dari API Voratoon: {api_url}") from exc

    if data.get("status") not in (200, None):
        raise RuntimeError(f"Gagal mengambil data API Voratoon: {api_url}")
    return data


def extract_voratoon_series_slug(url: str) -> str:
    match = re.search(r"/series/([^/?#]+)", url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak slug series Voratoon dari URL: {url}")
    return match.group(1)


def extract_voratoon_chapter_identity(chapter_url: str) -> tuple[str, str]:
    match = re.search(r"/series/([^/?#]+)/chapter/([^/?#]+)", chapter_url)
    if not match:
        raise ValueError(f"Tidak dapat mengekstrak chapter identity dari URL: {chapter_url}")
    slug = match.group(1).strip()
    chapter_num = match.group(2).strip().rstrip("/")
    if chapter_num.endswith(".0"):
        chapter_num = chapter_num[:-2]
    return slug, chapter_num


def parse_voratoon_iso_datetime(value: str | None) -> datetime | None:
    cleaned = clean_text(value)
    if not cleaned:
        return None

    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


MAX_INT32 = 2_147_483_647


def coalesce_voratoon_total_view(
    *,
    item_data: dict[str, Any],
    item_metadata: dict[str, Any],
    item_data_metadata: dict[str, Any],
) -> int | None:
    candidates = (
        item_data.get("totalViews"),
        (item_metadata.get("views") or {}).get("total"),
        item_data_metadata.get("historyViews"),
        item_data_metadata.get("analyticsViews"),
        item_data_metadata.get("monthlyViews"),
        item_data_metadata.get("totalViewsComputed"),
    )

    for value in candidates:
        if value is None:
            continue
        try:
            val = int(value)
            return min(val, MAX_INT32) if val > 0 else 0
        except (TypeError, ValueError):
            continue
    return None


def build_voratoon_series_index_params(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "includeMeta": str(include_meta).lower(),
        "sort": sort,
        "sortOrder": sort_order,
        "take": take,
        "page": max(page, 1),
    }

    cleaned_query = clean_text(query)
    if cleaned_query:
        params["filter"] = f'title=like="{cleaned_query}",nativeTitle=like="{cleaned_query}"'

    return params


def build_voratoon_series_index_url(
    *,
    page: int = 1,
    query: str | None = None,
    take: int = DEFAULT_SERIES_INDEX_TAKE,
    sort: str = "latest",
    sort_order: str = "desc",
    include_meta: bool = True,
) -> str:
    params = build_voratoon_series_index_params(
        page=page,
        query=query,
        take=take,
        sort=sort,
        sort_order=sort_order,
        include_meta=include_meta,
    )
    return f"{get_voratoon_api_base_url()}/series?{urlencode(params, doseq=True)}"


def build_voratoon_popular_url(
    *,
    page: int = 1,
    take: int = DEFAULT_POPULAR_TAKE,
) -> str:
    params = {
        "take": take,
        "page": max(page, 1),
    }
    return f"{get_voratoon_api_base_url()}/series/most-read?{urlencode(params)}"


def build_voratoon_series_detail_url(
    series_slug: str,
    *,
    include_meta: bool = True,
) -> str:
    params = {"includeMeta": str(include_meta).lower()}
    return f"{get_voratoon_api_base_url()}/series/{series_slug}?{urlencode(params)}"


def build_voratoon_series_chapters_url(series_slug: str) -> str:
    return f"{get_voratoon_api_base_url()}/series/{series_slug}/chapters"


def build_voratoon_chapter_detail_url(series_slug: str, chapter_number: str | float | int) -> str:
    ch_str = str(chapter_number).strip().rstrip("/")
    if ch_str.endswith(".0"):
        ch_str = ch_str[:-2]
    return f"{get_voratoon_api_base_url()}/series/{series_slug}/chapters/{ch_str}"
