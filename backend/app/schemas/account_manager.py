"""
Schemas untuk dashboard account manager.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator


class AccountProfileData(BaseModel):
    """Data profile aplikasi yang menempel ke Supabase Auth user."""

    username: str | None = None
    display_name: str | None = None
    avatar_url: str | None = None
    onboarding_completed: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None


class AccountRelationCounts(BaseModel):
    """Jumlah data aplikasi yang berelasi dengan satu user ID."""

    profiles: int = 0
    reader_preferences: int = 0
    user_reading_stats: int = 0
    user_bookmarks: int = 0
    user_collections: int = 0
    user_collection_comics: int = 0
    user_progress: int = 0
    user_history_entries: int = 0
    user_favorite_scenes: int = 0
    user_download_entries: int = 0

    @property
    def total(self) -> int:
        return sum(self.model_dump().values())


class AccountRelationPreviewItem(BaseModel):
    """Baris ringkas data terkait untuk ditampilkan di dashboard."""

    id: str
    title: str
    meta: str | None = None
    table: str


class AccountRelationPreview(BaseModel):
    """Preview data terkait user."""

    reader_preferences: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_reading_stats: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_bookmarks: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_collections: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_collection_comics: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_progress: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_history_entries: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_favorite_scenes: list[AccountRelationPreviewItem] = Field(default_factory=list)
    user_download_entries: list[AccountRelationPreviewItem] = Field(default_factory=list)


class AccountManagerUser(BaseModel):
    """User gabungan dari Supabase Auth, public.profiles, dan relasi app."""

    id: UUID
    email: EmailStr | None = None
    phone: str | None = None
    role: str | None = None
    account_role: str | None = None
    account_status: str = "active"
    created_at: datetime | None = None
    updated_at: datetime | None = None
    last_sign_in_at: datetime | None = None
    email_confirmed_at: datetime | None = None
    banned_until: datetime | None = None
    app_metadata: dict[str, Any] = Field(default_factory=dict)
    user_metadata: dict[str, Any] = Field(default_factory=dict)
    profile: AccountProfileData | None = None
    relation_counts: AccountRelationCounts = Field(default_factory=AccountRelationCounts)
    relation_total: int = 0


class AccountManagerListResponse(BaseModel):
    """Response daftar akun."""

    users: list[AccountManagerUser]
    total: int
    page: int
    per_page: int


class AccountManagerCreateRequest(BaseModel):
    """Payload buat akun via Supabase Admin API."""

    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    username: str | None = Field(default=None, max_length=50)
    avatar_url: str | None = Field(default=None, max_length=1000)
    onboarding_completed: bool = False
    account_role: str = Field(default="reader", max_length=50)
    account_status: str = Field(default="active", max_length=50)
    email_confirm: bool = True

    @field_validator("display_name", "username", "avatar_url")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None


class AccountManagerUpdateRequest(BaseModel):
    """Payload update akun."""

    email: EmailStr | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)
    username: str | None = Field(default=None, max_length=50)
    avatar_url: str | None = Field(default=None, max_length=1000)
    onboarding_completed: bool | None = None
    account_role: str | None = Field(default=None, max_length=50)
    account_status: str | None = Field(default=None, max_length=50)

    @field_validator("display_name", "username", "avatar_url")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None


class AccountDeletePreviewResponse(BaseModel):
    """Preview sebelum hapus akun."""

    user: AccountManagerUser
    relation_counts: AccountRelationCounts
    relation_total: int


class AccountDeleteResponse(BaseModel):
    """Response hapus akun dan data terkait."""

    success: bool = True
    deleted_user_id: UUID
    relation_counts: AccountRelationCounts
    relation_total: int
