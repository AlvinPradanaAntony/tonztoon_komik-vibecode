"""
Schemas untuk Supabase Auth endpoints dan JWT claims.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator


class AuthRegisterRequest(BaseModel):
    """Payload register email/password."""

    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    username: str | None = Field(default=None, max_length=50)
    email_redirect_to: str | None = Field(default=None, max_length=500)

    @field_validator("display_name")
    @classmethod
    def normalize_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = "_".join(value.replace("-", "_").split()).strip("_").lower()
        return normalized or None


class AuthLoginRequest(BaseModel):
    """Payload login email/username + password."""

    identifier: str | None = Field(default=None, min_length=1, max_length=254)
    email: EmailStr | None = None
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("identifier")
    @classmethod
    def normalize_identifier(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    @model_validator(mode="after")
    def require_identifier(self) -> "AuthLoginRequest":
        if self.identifier is None and self.email is None:
            raise ValueError("Email atau username wajib diisi.")
        return self

    @property
    def login_identifier(self) -> str:
        return self.identifier or str(self.email)


class AuthGoogleRequest(BaseModel):
    """Payload login Google native dari Flutter."""

    id_token: str = Field(..., min_length=1, max_length=8192)
    access_token: str | None = Field(default=None, min_length=1, max_length=8192)
    nonce: str | None = Field(default=None, min_length=1, max_length=2048)


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


class AuthEmailVerificationRequest(BaseModel):
    """Payload verifikasi email signup dari link Supabase."""

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


class AuthSecuritySessionResponse(BaseModel):
    """Session aktif berdasarkan access token saat ini."""

    session_id: UUID | None = None
    issued_at: int | None = None
    expires_at: int | None = None


class AuthSecurityOverviewResponse(BaseModel):
    """Ringkasan security account untuk halaman Privacy & Security."""

    email: EmailStr | None = None
    email_verified: bool = False
    provider: str | None = None
    has_password: bool = False
    current_session: AuthSecuritySessionResponse


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
