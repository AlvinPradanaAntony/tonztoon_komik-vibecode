"""
Schemas untuk Supabase Auth endpoints dan JWT claims.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator


class AuthRegisterRequest(BaseModel):
    """Payload register email/password."""

    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    email_redirect_to: str | None = Field(default=None, max_length=500)

    @field_validator("display_name")
    @classmethod
    def normalize_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None


class AuthLoginRequest(BaseModel):
    """Payload login email/password."""

    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)


class AuthRefreshRequest(BaseModel):
    """Payload refresh session menggunakan refresh token."""

    refresh_token: str = Field(..., min_length=1, max_length=2048)


class AuthPasswordRecoveryRequest(BaseModel):
    """Payload untuk mengirim email recovery password."""

    email: EmailStr
    email_redirect_to: str | None = Field(default=None, max_length=500)


class AuthPasswordRecoveryVerifyRequest(BaseModel):
    """Payload verifikasi token recovery dari email Supabase."""

    email: EmailStr
    token_hash: str = Field(..., min_length=1, max_length=2048)


class AuthPasswordUpdateRequest(BaseModel):
    """Payload update password setelah sesi recovery valid."""

    password: str = Field(..., min_length=8, max_length=128)


class AuthPasswordResetResponse(BaseModel):
    """Response umum flow reset password."""

    success: bool = True
    message: str


class AuthLogoutResponse(BaseModel):
    """Response logout backend."""

    success: bool = True
    message: str = "Session revoked successfully."


class AuthTokenResponse(BaseModel):
    """Session token response dari Supabase Auth."""

    access_token: str
    refresh_token: str | None = None
    token_type: str = "bearer"
    expires_in: int | None = None
    expires_at: int | None = None


class AuthUserResponse(BaseModel):
    """User ringkas hasil auth."""

    id: UUID
    email: EmailStr | None = None
    role: str | None = None
    app_metadata: dict[str, Any] = Field(default_factory=dict)
    user_metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime | None = None
    last_sign_in_at: datetime | None = None
    email_confirmed_at: datetime | None = None
    phone: str | None = None
    is_anonymous: bool | None = None


class AuthSessionResponse(BaseModel):
    """Response register/login ter-normalisasi untuk frontend."""

    user: AuthUserResponse | None = None
    session: AuthTokenResponse | None = None
    email_confirmation_required: bool = False
    message: str | None = None


class AuthenticatedUser(BaseModel):
    """Claims hasil validasi bearer token."""

    user_id: UUID
    email: EmailStr | None = None
    role: str | None = None
    audience: str | list[str] | None = None
    issuer: str | None = None
    expires_at: int | None = None
    issued_at: int | None = None
    session_id: UUID | None = None
    is_anonymous: bool | None = None
    raw_claims: dict[str, Any] = Field(default_factory=dict)


class ProfileResponse(BaseModel):
    """Public app profile milik user aktif."""

    id: UUID
    username: str | None = None
    display_name: str | None = None
    avatar_url: str | None = None
    onboarding_completed: bool = False
    created_at: datetime
    updated_at: datetime


class ProfileUpdateRequest(BaseModel):
    """Payload update public profile."""

    username: str | None = Field(default=None, max_length=50)
    display_name: str | None = Field(default=None, max_length=120)
    avatar_url: str | None = Field(default=None, max_length=1000)
    onboarding_completed: bool | None = None

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = "_".join(value.replace("-", "_").split()).strip("_").lower()
        if not normalized:
            return None
        return normalized

    @field_validator("display_name")
    @classmethod
    def normalize_display_name_update(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None

    @field_validator("avatar_url")
    @classmethod
    def normalize_avatar_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None
