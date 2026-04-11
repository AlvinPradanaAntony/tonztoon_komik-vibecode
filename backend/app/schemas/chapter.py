"""
Tonztoon Komik — Chapter Pydantic Schemas

Includes the ChapterImageItem schema for validating the JSONB
image array stored inside each Chapter row.
"""

from datetime import datetime

from pydantic import BaseModel, Field


class ChapterImageItem(BaseModel):
    """Satu item gambar di dalam array JSONB chapter.images."""
    page: int = Field(..., ge=1, examples=[1])
    url: str = Field(..., examples=["https://cdn.komiku.org/chapter1/001.jpg"])


class ChapterBase(BaseModel):
    """Schema dasar untuk chapter."""
    chapter_number: float = Field(..., examples=[1.0])
    title: str | None = Field(default=None, max_length=500, examples=["Chapter 1"])
    source_url: str = Field(...)
    release_date: datetime | None = Field(default=None)
    images: list[ChapterImageItem] = Field(default_factory=list)


class ChapterCreate(ChapterBase):
    """Schema untuk membuat chapter baru (input dari scraper)."""
    comic_id: int = Field(...)


class ChapterResponse(ChapterBase):
    """Schema response chapter — termasuk id dari database."""
    id: int
    comic_id: int
    created_at: datetime

    model_config = {"from_attributes": True}
