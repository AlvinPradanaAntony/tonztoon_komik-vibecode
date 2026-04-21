"""
Schemas untuk endpoint source-scoped API.
"""

from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.chapter import ChapterImageItem


class SourceInfoResponse(BaseModel):
    """Metadata dasar satu source yang aktif di backend."""

    id: str = Field(..., examples=["komiku_asia"])
    label: str = Field(..., examples=["Komiku Asia"])
    base_url: str = Field(..., examples=["https://01.komiku.asia"])
    enabled: bool = Field(default=True)


class SourceChapterListItem(BaseModel):
    """Ringkasan chapter untuk halaman daftar chapter komik."""

    chapter_number: float = Field(..., examples=[603.0])
    title: str | None = Field(default=None, max_length=500)
    detail_url: str = Field(
        ...,
        examples=["http://127.0.0.1:8000/api/v1/sources/komiku_asia/comics/lookism/chapters/603"],
    )
    release_date: datetime | None = Field(default=None)
    created_at: datetime
    total_images: int = Field(default=0, ge=0)


class SourceChapterResponse(BaseModel):
    """Payload chapter reader source-scoped."""

    source_name: str = Field(..., examples=["komiku_asia"])
    chapter_number: float = Field(..., examples=[603.0])
    images: list[ChapterImageItem] = Field(default_factory=list)
    total: int = Field(default=0, ge=0)
