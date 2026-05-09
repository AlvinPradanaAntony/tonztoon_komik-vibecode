"""
Supabase Auth API routes.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from fastapi.security import HTTPAuthorizationCredentials

from app.api.deps import bearer_scheme, get_current_auth_user
from app.api.errors import raise_api_error
from app.database import get_db
from app.schemas import (
    AuthenticatedUser,
    AuthEmailVerificationRequest,
    AuthLoginRequest,
    AuthLogoutResponse,
    AuthPasswordRecoveryRequest,
    AuthPasswordRecoveryVerifyRequest,
    AuthPasswordResetResponse,
    AuthPasswordUpdateRequest,
    ProfileResponse,
    ProfileUpdateRequest,
    AuthRefreshRequest,
    AuthRegisterRequest,
    AuthSessionResponse,
)
from sqlalchemy.ext.asyncio import AsyncSession
from app.services.auth_service import (
    AuthConfigurationError,
    AuthRequestError,
    login_with_email_password,
    logout_auth_session,
    refresh_auth_session,
    register_with_email_password,
    request_password_recovery,
    update_auth_password,
    verify_email_signup,
    verify_password_recovery,
)
from app.services.profile_service import (
    build_profile_response,
    ensure_profile_for_auth_user,
    get_or_create_profile,
    update_profile,
)

router = APIRouter()


def _raise_auth_service_error(exc: AuthRequestError) -> None:
    raise_api_error(exc.status_code, exc.message, code=exc.code)


@router.post("/register", response_model=AuthSessionResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: AuthRegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """Register akun baru melalui Supabase Auth."""
    try:
        response = await register_with_email_password(payload)
        if response.user is not None:
            await ensure_profile_for_auth_user(
                db,
                response.user.id,
                user_metadata=response.user.user_metadata,
            )
        return response
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)


@router.post("/login", response_model=AuthSessionResponse)
async def login(
    payload: AuthLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Login email/password melalui Supabase Auth."""
    try:
        response = await login_with_email_password(payload)
        if response.user is not None:
            await ensure_profile_for_auth_user(
                db,
                response.user.id,
                user_metadata=response.user.user_metadata,
            )
        return response
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)


@router.post("/refresh", response_model=AuthSessionResponse)
async def refresh(
    payload: AuthRefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    """Refresh access token menggunakan refresh token Supabase."""
    try:
        response = await refresh_auth_session(payload)
        if response.user is not None:
            await ensure_profile_for_auth_user(
                db,
                response.user.id,
                user_metadata=response.user.user_metadata,
            )
        return response
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)


@router.post(
    "/password/forgot",
    response_model=AuthPasswordResetResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def forgot_password(payload: AuthPasswordRecoveryRequest):
    """Kirim email recovery password melalui Supabase Auth."""
    try:
        await request_password_recovery(payload)
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)

    return AuthPasswordResetResponse(
        message=(
            "Jika email terdaftar, instruksi reset password akan dikirim."
        ),
    )


@router.post(
    "/password/recovery/verify",
    response_model=AuthSessionResponse,
)
async def verify_recovery(
    payload: AuthPasswordRecoveryVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verifikasi token recovery dari email dan buat sesi reset password."""
    try:
        response = await verify_password_recovery(payload)
        if response.user is not None:
            await ensure_profile_for_auth_user(
                db,
                response.user.id,
                user_metadata=response.user.user_metadata,
            )
        return response
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)


@router.post(
    "/email/verify",
    response_model=AuthSessionResponse,
)
async def verify_email(
    payload: AuthEmailVerificationRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verifikasi email signup dari link Supabase dan buat sesi awal."""
    try:
        response = await verify_email_signup(payload)
        if response.user is not None:
            await ensure_profile_for_auth_user(
                db,
                response.user.id,
                user_metadata=response.user.user_metadata,
            )
        return response
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)


@router.post("/password/update", response_model=AuthPasswordResetResponse)
async def update_password(
    payload: AuthPasswordUpdateRequest,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
):
    """Update password memakai bearer token dari sesi recovery yang valid."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise_api_error(status.HTTP_401_UNAUTHORIZED, "Bearer token required.")

    try:
        await update_auth_password(credentials.credentials, payload)
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)

    return AuthPasswordResetResponse(message="Password berhasil diperbarui.")


@router.post("/logout", response_model=AuthLogoutResponse)
async def logout(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
):
    """Revoke current Supabase session refresh token chain."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise_api_error(status.HTTP_401_UNAUTHORIZED, "Bearer token required.")

    try:
        await logout_auth_session(credentials.credentials)
    except AuthConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AuthRequestError as exc:
        _raise_auth_service_error(exc)

    return AuthLogoutResponse()


@router.get("/me", response_model=AuthenticatedUser)
async def me(auth_user: AuthenticatedUser = Depends(get_current_auth_user)):
    """Return verified bearer token claims untuk user aktif."""
    return auth_user


@router.get("/profile", response_model=ProfileResponse)
async def get_profile_me(
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Ambil public profile milik user aktif."""
    profile = await get_or_create_profile(
        db,
        auth_user.user_id,
        user_metadata=auth_user.raw_claims.get("user_metadata"),
    )
    return build_profile_response(profile)


@router.patch("/profile", response_model=ProfileResponse)
async def patch_profile_me(
    payload: ProfileUpdateRequest,
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Update public profile milik user aktif."""
    try:
        profile = await update_profile(db, auth_user.user_id, payload)
    except ValueError as exc:
        raise_api_error(status.HTTP_409_CONFLICT, str(exc))
    return build_profile_response(profile)
