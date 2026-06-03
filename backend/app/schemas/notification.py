"""
Schemas for push notification device registration and events.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


PushProvider = Literal["fcm"]
PushPlatform = Literal["android"]


class PushDeviceRegisterRequest(BaseModel):
    provider: PushProvider = "fcm"
    platform: PushPlatform = "android"
    token: str = Field(..., min_length=1, max_length=8192)
    user_id: UUID

    @field_validator("token")
    @classmethod
    def normalize_token(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("token wajib diisi.")
        return normalized


class PushDeviceUnregisterRequest(BaseModel):
    provider: PushProvider = "fcm"
    platform: PushPlatform = "android"
    token: str = Field(..., min_length=1, max_length=8192)

    @field_validator("token")
    @classmethod
    def normalize_token(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("token wajib diisi.")
        return normalized


class PushDeviceResponse(BaseModel):
    id: UUID
    provider: str
    platform: str
    token_hash: str
    active: bool
    created_at: datetime
    updated_at: datetime
    last_seen_at: datetime | None = None


class ChapterUpdateEventRequest(BaseModel):
    source_name: str = Field(..., min_length=1, max_length=100)
    comic_slug: str = Field(..., min_length=1, max_length=600)
    comic_title: str = Field(..., min_length=1, max_length=500)
    latest_chapter_number: float = Field(..., ge=0)
    latest_chapter_title: str | None = Field(default=None, max_length=500)
    release_date: datetime | None = None
    event_id: str = Field(..., min_length=1, max_length=500)

    @field_validator(
        "source_name",
        "comic_slug",
        "comic_title",
        "latest_chapter_title",
        "event_id",
    )
    @classmethod
    def normalize_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None


class ChapterUpdateEventResponse(BaseModel):
    event_id: str
    matched_users: int
    target_devices: int
    queued_messages: int
    duplicate: bool = False


class AdminAnnouncementRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    message: str = Field(..., min_length=1, max_length=500)
    category: str = Field(default="Pengumuman", min_length=1, max_length=80)
    action_route: str | None = Field(default="/notifications", max_length=300)
    event_id: str | None = Field(default=None, max_length=500)

    @field_validator("title", "message", "category", "action_route", "event_id")
    @classmethod
    def normalize_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None

    @field_validator("action_route")
    @classmethod
    def validate_action_route(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not value.startswith("/"):
            raise ValueError("action_route harus diawali '/'.")
        return value


class AdminAnnouncementResponse(BaseModel):
    event_id: str
    matched_users: int
    target_devices: int
    queued_messages: int
    duplicate: bool = False
