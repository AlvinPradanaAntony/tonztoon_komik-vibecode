"""
Service layer untuk Supabase Auth dan verifikasi JWT.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import httpx
import jwt
from jwt import PyJWKClient

from app.config import (
    get_supabase_auth_base_url,
    get_supabase_jwks_url,
    get_supabase_jwt_issuer,
    settings,
)
from app.schemas import (
    AuthenticatedUser,
    AuthLoginRequest,
    AuthRefreshRequest,
    AuthRegisterRequest,
    AuthSessionResponse,
    AuthTokenResponse,
    AuthUserResponse,
)


class AuthConfigurationError(RuntimeError):
    """Raised when Supabase Auth configuration is missing or invalid."""


class AuthValidationError(RuntimeError):
    """Raised when access token validation fails."""


class AuthRequestError(RuntimeError):
    """Raised when Supabase Auth API call fails."""


@dataclass(slots=True)
class RemoteAuthUser:
    """Fallback remote verification response."""

    id: str
    email: str | None
    role: str | None
    app_metadata: dict[str, Any]
    user_metadata: dict[str, Any]
    phone: str | None
    is_anonymous: bool | None


def _require_supabase_public_config() -> None:
    if not settings.SUPABASE_URL or not settings.SUPABASE_PUBLISHABLE_KEY:
        raise AuthConfigurationError(
            "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be configured.",
        )


def _build_public_headers() -> dict[str, str]:
    _require_supabase_public_config()
    return {
        "apikey": settings.SUPABASE_PUBLISHABLE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_PUBLISHABLE_KEY}",
        "Content-Type": "application/json",
    }


@lru_cache(maxsize=1)
def _get_jwks_client() -> PyJWKClient | None:
    jwks_url = get_supabase_jwks_url()
    if not jwks_url:
        return None
    return PyJWKClient(jwks_url, cache_jwk_set=True, lifespan=300)


def _normalize_auth_user(raw_user: dict[str, Any] | None) -> AuthUserResponse | None:
    if not raw_user:
        return None

    identities = raw_user.get("identities") or []
    app_metadata = raw_user.get("app_metadata") or {}
    user_metadata = raw_user.get("user_metadata") or {}
    is_anonymous = app_metadata.get("provider") == "anonymous"
    if identities:
        is_anonymous = identities[0].get("provider") == "anonymous"

    return AuthUserResponse(
        id=raw_user["id"],
        email=raw_user.get("email"),
        role=raw_user.get("role"),
        app_metadata=app_metadata,
        user_metadata=user_metadata,
        created_at=raw_user.get("created_at"),
        last_sign_in_at=raw_user.get("last_sign_in_at"),
        email_confirmed_at=raw_user.get("email_confirmed_at"),
        phone=raw_user.get("phone"),
        is_anonymous=is_anonymous,
    )


def _normalize_session(raw_data: dict[str, Any]) -> AuthSessionResponse:
    if "session" in raw_data:
        raw_session = raw_data.get("session")
        raw_user = raw_data.get("user")
    else:
        raw_session = raw_data if raw_data.get("access_token") else None
        raw_user = raw_data.get("user")

    session = None
    if raw_session:
        session = AuthTokenResponse(
            access_token=raw_session.get("access_token"),
            refresh_token=raw_session.get("refresh_token"),
            token_type=raw_session.get("token_type") or "bearer",
            expires_in=raw_session.get("expires_in"),
            expires_at=raw_session.get("expires_at"),
        )

    email_confirmation_required = session is None
    message = (
        "Email confirmation required before sign in."
        if email_confirmation_required
        else "Authentication successful."
    )

    return AuthSessionResponse(
        user=_normalize_auth_user(raw_user),
        session=session,
        email_confirmation_required=email_confirmation_required,
        message=message,
    )


async def register_with_email_password(
    payload: AuthRegisterRequest,
) -> AuthSessionResponse:
    """Register user via Supabase Auth."""
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        raise AuthConfigurationError("SUPABASE_URL must be configured.")

    body: dict[str, Any] = {
        "email": str(payload.email),
        "password": payload.password,
    }
    data_options: dict[str, Any] = {}
    if payload.display_name:
        data_options["display_name"] = payload.display_name
    if data_options:
        body["data"] = data_options

    redirect_to = payload.email_redirect_to or settings.SUPABASE_AUTH_REDIRECT_URL
    if redirect_to:
        body["email_redirect_to"] = redirect_to

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{auth_base}/signup",
            headers=_build_public_headers(),
            json=body,
        )

    if response.status_code >= 400:
        raise AuthRequestError(_extract_auth_error_message(response))

    return _normalize_session(response.json())


async def login_with_email_password(
    payload: AuthLoginRequest,
) -> AuthSessionResponse:
    """Login user via Supabase Auth."""
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        raise AuthConfigurationError("SUPABASE_URL must be configured.")

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{auth_base}/token",
            params={"grant_type": "password"},
            headers=_build_public_headers(),
            json={
                "email": str(payload.email),
                "password": payload.password,
            },
        )

    if response.status_code >= 400:
        raise AuthRequestError(_extract_auth_error_message(response))

    return _normalize_session(response.json())


async def refresh_auth_session(
    payload: AuthRefreshRequest,
) -> AuthSessionResponse:
    """Refresh session via Supabase Auth menggunakan refresh token."""
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        raise AuthConfigurationError("SUPABASE_URL must be configured.")

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{auth_base}/token",
            params={"grant_type": "refresh_token"},
            headers=_build_public_headers(),
            json={
                "refresh_token": payload.refresh_token,
            },
        )

    if response.status_code >= 400:
        raise AuthRequestError(_extract_auth_error_message(response))

    return _normalize_session(response.json())


async def logout_auth_session(access_token: str) -> None:
    """Revoke current session refresh token chain via Supabase Auth logout."""
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        raise AuthConfigurationError("SUPABASE_URL must be configured.")

    _require_supabase_public_config()

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"{auth_base}/logout",
            headers={
                "apikey": settings.SUPABASE_PUBLISHABLE_KEY,
                "Authorization": f"Bearer {access_token}",
            },
        )

    if response.status_code not in {200, 204}:
        raise AuthRequestError(_extract_auth_error_message(response))


def _extract_auth_error_message(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        payload = {}

    return (
        payload.get("msg")
        or payload.get("error_description")
        or payload.get("error")
        or payload.get("message")
        or f"Supabase Auth request failed with status {response.status_code}."
    )


def _decode_unverified_claims(token: str) -> dict[str, Any]:
    return jwt.decode(
        token,
        options={
            "verify_signature": False,
            "verify_exp": False,
            "verify_aud": False,
        },
        algorithms=["HS256", "RS256", "ES256", "EdDSA"],
    )


def _decode_with_jwks(token: str) -> dict[str, Any]:
    jwks_client = _get_jwks_client()
    if jwks_client is None:
        raise AuthValidationError("JWKS URL is not configured.")

    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256", "ES256", "EdDSA"],
            audience=settings.SUPABASE_JWT_AUDIENCE,
            issuer=get_supabase_jwt_issuer(),
            options={"require": ["exp", "iss", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise AuthValidationError(f"JWT validation failed: {exc}") from exc
    except Exception as exc:
        raise AuthValidationError(f"JWKS validation failed: {exc}") from exc


def _decode_with_legacy_secret(token: str) -> dict[str, Any]:
    if not settings.SUPABASE_JWT_SECRET:
        raise AuthValidationError("SUPABASE_JWT_SECRET is not configured.")

    try:
        return jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience=settings.SUPABASE_JWT_AUDIENCE,
            issuer=get_supabase_jwt_issuer(),
            options={"require": ["exp", "iss", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise AuthValidationError(f"JWT validation failed: {exc}") from exc


async def _verify_token_remotely(token: str) -> RemoteAuthUser:
    """
    Fallback verification via Supabase Auth server.

    Dipakai bila project masih menggunakan signing mode lama dan backend belum
    diberi JWT secret untuk verifikasi lokal.
    """
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        raise AuthConfigurationError("SUPABASE_URL must be configured.")

    headers = {
        "apikey": settings.SUPABASE_PUBLISHABLE_KEY,
        "Authorization": f"Bearer {token}",
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.get(
            f"{auth_base}/user",
            headers=headers,
        )

    if response.status_code >= 400:
        raise AuthValidationError(_extract_auth_error_message(response))

    user_payload = response.json()
    app_metadata = user_payload.get("app_metadata") or {}
    identities = user_payload.get("identities") or []
    is_anonymous = app_metadata.get("provider") == "anonymous"
    if identities:
        is_anonymous = identities[0].get("provider") == "anonymous"

    return RemoteAuthUser(
        id=user_payload["id"],
        email=user_payload.get("email"),
        role=user_payload.get("role"),
        app_metadata=app_metadata,
        user_metadata=user_payload.get("user_metadata") or {},
        phone=user_payload.get("phone"),
        is_anonymous=is_anonymous,
    )


async def validate_supabase_jwt(token: str) -> AuthenticatedUser:
    """
    Validasi access token Supabase.

    Prioritas:
    1. JWT secret untuk token legacy HS256
    2. JWKS untuk signing key asimetris
    3. GET /auth/v1/user sebagai fallback server-side verification
    """
    if not token:
        raise AuthValidationError("Missing bearer token.")

    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise AuthValidationError(f"Malformed JWT: {exc}") from exc

    algorithm = (header.get("alg") or "").upper()

    decoded_claims: dict[str, Any] | None = None

    if algorithm == "HS256" and settings.SUPABASE_JWT_SECRET:
        decoded_claims = _decode_with_legacy_secret(token)
    elif algorithm != "HS256" and get_supabase_jwks_url():
        decoded_claims = _decode_with_jwks(token)
    elif settings.SUPABASE_JWT_SECRET:
        decoded_claims = _decode_with_legacy_secret(token)

    if decoded_claims is None:
        remote_user = await _verify_token_remotely(token)
        unverified_claims = _decode_unverified_claims(token)
        if unverified_claims.get("sub") != remote_user.id:
            raise AuthValidationError("Token subject mismatch.")
        decoded_claims = unverified_claims
        decoded_claims["email"] = decoded_claims.get("email") or remote_user.email
        decoded_claims["role"] = decoded_claims.get("role") or remote_user.role
        decoded_claims["is_anonymous"] = remote_user.is_anonymous

    try:
        return AuthenticatedUser(
            user_id=decoded_claims["sub"],
            email=decoded_claims.get("email"),
            role=decoded_claims.get("role"),
            audience=decoded_claims.get("aud"),
            issuer=decoded_claims.get("iss"),
            expires_at=decoded_claims.get("exp"),
            issued_at=decoded_claims.get("iat"),
            session_id=decoded_claims.get("session_id"),
            is_anonymous=decoded_claims.get("is_anonymous"),
            raw_claims=decoded_claims,
        )
    except Exception as exc:
        raise AuthValidationError(f"Invalid token claims: {exc}") from exc
