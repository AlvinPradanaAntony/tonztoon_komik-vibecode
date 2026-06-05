"""Pydantic contracts for helpdesk submissions."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


HelpdeskCategory = Literal["review", "report"]
HelpdeskStatus = Literal["open", "in_progress", "resolved", "closed"]


class HelpdeskSubmissionCreateRequest(BaseModel):
    category: HelpdeskCategory
    rating: int | None = Field(default=None, ge=1, le=5)
    title: str | None = Field(default=None, max_length=120)
    message: str = Field(..., min_length=10, max_length=2000)
    platform: str = Field(..., min_length=1, max_length=30)
    app_version: str | None = Field(default=None, max_length=50)
    app_build: str | None = Field(default=None, max_length=30)
    locale: str | None = Field(default=None, max_length=30)
    client_context: dict[str, Any] = Field(default_factory=dict)

    @field_validator("title", "app_version", "app_build", "locale")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split()).strip()
        return normalized or None

    @field_validator("message", "platform")
    @classmethod
    def normalize_required_text(cls, value: str) -> str:
        normalized = " ".join(value.split()).strip()
        if not normalized:
            raise ValueError("field wajib diisi.")
        return normalized

    @field_validator("client_context")
    @classmethod
    def limit_client_context(cls, value: dict[str, Any]) -> dict[str, Any]:
        if len(value) > 20:
            raise ValueError("client_context maksimal berisi 20 field.")
        for key, item in value.items():
            if len(str(key)) > 60 or len(str(item)) > 500:
                raise ValueError("client_context berisi nilai yang terlalu panjang.")
        return value

    @model_validator(mode="after")
    def validate_category_fields(self):
        if len(self.message) < 10:
            raise ValueError("message minimal 10 karakter.")
        if self.category == "review":
            if self.rating is None:
                raise ValueError("rating wajib diisi untuk review.")
            self.title = None
        else:
            if self.rating is not None:
                raise ValueError("rating hanya boleh diisi untuk review.")
            if self.title is None or len(self.title) < 5:
                raise ValueError("title minimal 5 karakter untuk report.")
        return self


class HelpdeskSubmissionResponse(BaseModel):
    id: UUID
    reference_code: str
    user_id: UUID | None = None
    category: HelpdeskCategory
    rating: int | None = None
    title: str | None = None
    message: str
    platform: str
    app_version: str | None = None
    app_build: str | None = None
    locale: str | None = None
    client_context: dict[str, Any] = Field(default_factory=dict)
    status: HelpdeskStatus
    admin_note: str | None = None
    created_at: datetime
    updated_at: datetime


class HelpdeskSubmissionListResponse(BaseModel):
    items: list[HelpdeskSubmissionResponse]
    total: int
    page: int
    per_page: int


class HelpdeskSubmissionUpdateRequest(BaseModel):
    status: HelpdeskStatus | None = None
    admin_note: str | None = Field(default=None, max_length=2000)

    @field_validator("admin_note")
    @classmethod
    def normalize_admin_note(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    @model_validator(mode="after")
    def require_update(self):
        if self.status is None and self.admin_note is None:
            raise ValueError("Minimal satu perubahan wajib diisi.")
        return self
