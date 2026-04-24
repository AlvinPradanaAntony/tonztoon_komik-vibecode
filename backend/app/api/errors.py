"""
Utilities untuk response error JSON yang konsisten.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException


DEFAULT_ERROR_MESSAGES: dict[int, str] = {
    400: "Bad request.",
    401: "Unauthorized.",
    403: "Forbidden.",
    404: "Resource not found.",
    405: "Method not allowed.",
    409: "Conflict.",
    422: "Request validation failed.",
    429: "Too many requests.",
    500: "Internal server error.",
    502: "Bad gateway.",
    503: "Service temporarily unavailable.",
    504: "Gateway timeout.",
}


def get_fallback_error_message(status_code: int | None = None) -> str:
    """Return default error message untuk status code tertentu."""
    if status_code is None:
        status_code = 500
    return DEFAULT_ERROR_MESSAGES.get(status_code, "Request failed.")


def build_error_payload(detail: Any, *, fallback_message: str) -> dict[str, Any]:
    """Normalize berbagai bentuk error detail menjadi payload JSON ber-field message."""
    if isinstance(detail, dict):
        payload = dict(detail)
        message = payload.get("message")
        if not isinstance(message, str) or not message.strip():
            nested_detail = payload.get("detail")
            if isinstance(nested_detail, str) and nested_detail.strip():
                payload["message"] = nested_detail
            else:
                payload["message"] = fallback_message
        return payload

    if isinstance(detail, list):
        return {
            "message": fallback_message,
            "errors": detail,
        }

    if isinstance(detail, str):
        normalized = detail.strip()
        if normalized:
            return {
                "message": normalized,
                "detail": normalized,
            }

    return {"message": fallback_message}


def build_unhandled_error_payload(
    exc: Exception,
    *,
    fallback_message: str,
    include_debug_detail: bool = False,
) -> dict[str, Any]:
    """Build payload untuk unexpected server errors."""
    payload: dict[str, Any] = {"message": fallback_message}

    if include_debug_detail:
        detail = str(exc).strip()
        if detail:
            payload["detail"] = detail

    return payload


def raise_api_error(
    status_code: int,
    message: str,
    *,
    code: str | None = None,
    extra: dict[str, Any] | None = None,
) -> None:
    """Raise HTTPException dengan payload detail yang sudah frontend-friendly."""
    payload: dict[str, Any] = {"message": message}
    if code:
        payload["code"] = code
    if extra:
        payload.update(extra)

    raise HTTPException(status_code=status_code, detail=payload)
