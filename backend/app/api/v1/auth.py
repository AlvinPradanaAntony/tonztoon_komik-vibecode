"""
Supabase Auth API routes.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.api.deps import bearer_scheme, get_current_auth_user
from app.database import get_db
from app.schemas import (
    AuthenticatedUser,
    AuthLoginRequest,
    AuthLogoutResponse,
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
)
from app.services.profile_service import (
    build_profile_response,
    ensure_profile_for_auth_user,
    get_or_create_profile,
    update_profile,
)

router = APIRouter()


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
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except AuthRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


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
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except AuthRequestError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


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
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except AuthRequestError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


@router.post("/logout", response_model=AuthLogoutResponse)
async def logout(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
):
    """Revoke current Supabase session refresh token chain."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Bearer token required.",
        )

    try:
        await logout_auth_session(credentials.credentials)
    except AuthConfigurationError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except AuthRequestError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc

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
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return build_profile_response(profile)
