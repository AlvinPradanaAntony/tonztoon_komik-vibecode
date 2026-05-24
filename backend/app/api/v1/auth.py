"""
Supabase Auth API routes.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, UploadFile, status
from fastapi.security import HTTPAuthorizationCredentials

from app.api.deps import bearer_scheme, get_current_auth_user
from app.api.errors import raise_api_error
from app.database import get_db
from app.schemas import (
    AuthenticatedUser,
    AuthEmailVerificationRequest,
    AuthGoogleRequest,
    AuthLoginRequest,
    AuthLogoutResponse,
    AuthPasswordRecoveryRequest,
    AuthPasswordRecoveryVerifyRequest,
    AuthPasswordResetResponse,
    AuthPasswordUpdateRequest,
    AuthSecurityOverviewResponse,
    AuthSecuritySessionResponse,
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
    get_auth_user_by_id,
    login_with_google_id_token,
    login_with_email_password,
    logout_auth_session,
    refresh_auth_session,
    register_with_email_password,
    request_password_recovery,
    mark_auth_user_has_password,
    update_auth_password,
    verify_email_signup,
    verify_password_recovery,
)
from app.services.avatar_storage_service import AvatarStorageError, upload_avatar
from app.services.profile_service import (
    build_profile_response,
    ensure_profile_for_auth_user,
    get_or_create_profile,
    update_profile,
)

router = APIRouter()


def _raise_auth_service_error(exc: AuthRequestError) -> None:
    raise_api_error(exc.status_code, exc.message, code=exc.code)


def _claim_bool(claims: dict[str, object], key: str) -> bool | None:
    value = claims.get(key)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes"}:
            return True
        if normalized in {"false", "0", "no"}:
            return False
    return None


def _append_provider(providers: list[str], value: object) -> None:
    if not isinstance(value, str):
        return
    provider = value.strip().lower()
    if provider and provider not in providers:
        providers.append(provider)


def _auth_provider_names(
    app_metadata: dict[str, object],
    admin_user: dict[str, object] | None = None,
) -> list[str]:
    providers: list[str] = []
    _append_provider(providers, app_metadata.get("provider"))
    metadata_providers = app_metadata.get("providers")
    if isinstance(metadata_providers, list):
        for provider in metadata_providers:
            _append_provider(providers, provider)

    if admin_user:
        admin_metadata = admin_user.get("app_metadata")
        if isinstance(admin_metadata, dict):
            _append_provider(providers, admin_metadata.get("provider"))
            admin_providers = admin_metadata.get("providers")
            if isinstance(admin_providers, list):
                for provider in admin_providers:
                    _append_provider(providers, provider)

        identities = admin_user.get("identities")
        if isinstance(identities, list):
            for identity in identities:
                if isinstance(identity, dict):
                    _append_provider(providers, identity.get("provider"))

    return providers


def _metadata_has_password(
    app_metadata: dict[str, object],
    admin_user: dict[str, object] | None = None,
) -> bool:
    if app_metadata.get("has_password") is True:
        return True
    if not admin_user:
        return False
    admin_metadata = admin_user.get("app_metadata")
    return (
        isinstance(admin_metadata, dict)
        and admin_metadata.get("has_password") is True
    )


async def _mark_auth_user_has_password_safely(user_id: object) -> None:
    try:
        await mark_auth_user_has_password(str(user_id))
    except (AuthConfigurationError, AuthRequestError):
        pass


@router.post("/register", response_model=AuthSessionResponse, status_code=status.HTTP_201_CREATED)
async def register(
    payload: AuthRegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """Register akun baru melalui Supabase Auth."""
    try:
        response = await register_with_email_password(payload)
        if response.user is not None:
            await _mark_auth_user_has_password_safely(response.user.id)
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
            await _mark_auth_user_has_password_safely(response.user.id)
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


@router.post("/google", response_model=AuthSessionResponse)
async def login_google(
    payload: AuthGoogleRequest,
    db: AsyncSession = Depends(get_db),
):
    """Login Google native melalui backend lalu buat/isi public profile."""
    try:
        response = await login_with_google_id_token(payload)
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
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
):
    """Update password memakai bearer token dari sesi recovery yang valid."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise_api_error(status.HTTP_401_UNAUTHORIZED, "Bearer token required.")

    try:
        await update_auth_password(credentials.credentials, payload)
        await _mark_auth_user_has_password_safely(auth_user.user_id)
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


@router.get("/security", response_model=AuthSecurityOverviewResponse)
async def security_overview(
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
):
    """Ringkasan security account berdasarkan access token aktif."""
    claims = auth_user.raw_claims
    app_metadata = claims.get("app_metadata")
    user_metadata = claims.get("user_metadata")
    if not isinstance(app_metadata, dict):
        app_metadata = {}
    if not isinstance(user_metadata, dict):
        user_metadata = {}

    admin_user: dict[str, object] | None = None
    try:
        admin_user = await get_auth_user_by_id(str(auth_user.user_id))
    except (AuthConfigurationError, AuthRequestError):
        admin_user = None

    providers = _auth_provider_names(app_metadata, admin_user)
    provider = providers[0] if providers else None
    has_password = "email" in providers or _metadata_has_password(
        app_metadata,
        admin_user,
    )

    email_verified_claim = _claim_bool(claims, "email_verified")
    if email_verified_claim is None:
        email_verified_claim = _claim_bool(user_metadata, "email_verified")
    email_verified = (
        email_verified_claim
        if email_verified_claim is not None
        else bool(auth_user.email and not auth_user.is_anonymous)
    )

    return AuthSecurityOverviewResponse(
        email=auth_user.email,
        email_verified=email_verified,
        provider=provider,
        has_password=has_password,
        current_session=AuthSecuritySessionResponse(
            session_id=auth_user.session_id,
            issued_at=auth_user.issued_at,
            expires_at=auth_user.expires_at,
        ),
    )


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


@router.post("/profile/avatar", response_model=ProfileResponse)
async def upload_profile_avatar(
    file: UploadFile = File(...),
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload, optimize, and attach avatar image for current user profile."""
    content_type = (file.content_type or "").lower()
    if content_type and not content_type.startswith("image/"):
        raise_api_error(
            status.HTTP_400_BAD_REQUEST,
            "File avatar harus berupa gambar.",
        )

    content = await file.read()
    try:
        avatar_url = await upload_avatar(user_id=auth_user.user_id, content=content)
        profile = await update_profile(
            db,
            auth_user.user_id,
            ProfileUpdateRequest(avatar_url=avatar_url),
        )
    except AvatarStorageError as exc:
        raise_api_error(exc.status_code, exc.message)
    except ValueError as exc:
        raise_api_error(status.HTTP_409_CONFLICT, str(exc))

    return build_profile_response(profile)
