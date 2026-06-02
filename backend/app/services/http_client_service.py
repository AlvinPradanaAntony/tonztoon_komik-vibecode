"""
Shared HTTPX clients for outbound backend requests.

HTTPX AsyncClient is intentionally long-lived here so requests can reuse
connection pools instead of recreating sockets on every API call.
"""

from __future__ import annotations

import httpx


_DEFAULT_LIMITS = httpx.Limits(
    max_connections=100,
    max_keepalive_connections=20,
    keepalive_expiry=30.0,
)
_IMAGE_LIMITS = httpx.Limits(
    max_connections=80,
    max_keepalive_connections=20,
    keepalive_expiry=30.0,
)

_shared_http_client: httpx.AsyncClient | None = None
_auth_http_client: httpx.AsyncClient | None = None
_image_proxy_http_client: httpx.AsyncClient | None = None


def _new_client(
    *,
    timeout: httpx.Timeout,
    limits: httpx.Limits = _DEFAULT_LIMITS,
) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        timeout=timeout,
        limits=limits,
        follow_redirects=False,
    )


def get_shared_http_client() -> httpx.AsyncClient:
    """Return the general outbound HTTP client."""
    global _shared_http_client
    if _shared_http_client is None or _shared_http_client.is_closed:
        _shared_http_client = _new_client(
            timeout=httpx.Timeout(connect=10.0, read=30.0, write=30.0, pool=10.0),
        )
    return _shared_http_client


def get_auth_http_client() -> httpx.AsyncClient:
    """Return the shared Supabase/Auth/Admin HTTP client."""
    global _auth_http_client
    if _auth_http_client is None or _auth_http_client.is_closed:
        _auth_http_client = _new_client(
            timeout=httpx.Timeout(connect=10.0, read=60.0, write=30.0, pool=10.0),
        )
    return _auth_http_client


def get_image_proxy_http_client() -> httpx.AsyncClient:
    """Return the shared image proxy/probe HTTP client."""
    global _image_proxy_http_client
    if _image_proxy_http_client is None or _image_proxy_http_client.is_closed:
        _image_proxy_http_client = _new_client(
            timeout=httpx.Timeout(connect=10.0, read=30.0, write=10.0, pool=10.0),
            limits=_IMAGE_LIMITS,
        )
    return _image_proxy_http_client


async def startup_http_clients() -> None:
    """Eagerly create clients during app startup."""
    get_shared_http_client()
    get_auth_http_client()
    get_image_proxy_http_client()


async def shutdown_http_clients() -> None:
    """Close all shared outbound clients during app shutdown."""
    global _shared_http_client, _auth_http_client, _image_proxy_http_client

    clients = (
        _shared_http_client,
        _auth_http_client,
        _image_proxy_http_client,
    )
    for client in clients:
        if client is not None and not client.is_closed:
            await client.aclose()

    _shared_http_client = None
    _auth_http_client = None
    _image_proxy_http_client = None
