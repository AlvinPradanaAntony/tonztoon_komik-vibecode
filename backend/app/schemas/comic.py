"""
Tonztoon Komik — Comic & Genre Pydantic Schemas

Digunakan oleh:
- FastAPI: request/response serialization
- Scraper: validasi data hasil scraping sebelum insert ke DB
"""

from datetime import datetime
from typing import ClassVar

from pydantic import BaseModel, Field, ValidationInfo, field_validator


# ==================== Genre ====================

class GenreBase(BaseModel):
    """Schema dasar untuk genre."""
    name: str = Field(..., max_length=100, examples=["Action"])
    slug: str = Field(..., max_length=120, examples=["action"])


class GenreCreate(GenreBase):
    """Schema untuk membuat genre baru (input dari scraper)."""
    pass


class GenreResponse(GenreBase):
    """Schema response genre — termasuk id dari database."""
    id: int

    model_config = {"from_attributes": True}


# ==================== Comic ====================

class ComicBase(BaseModel):
    """Schema dasar untuk komik."""
    title: str = Field(..., max_length=500, examples=["Solo Leveling"])
    slug: str = Field(..., max_length=600, examples=["solo-leveling"])
    alternative_titles: str | None = Field(default=None, examples=["나 혼자만 레벨업"])
    cover_image_url: str | None = Field(default=None)
    author: str | None = Field(default=None, max_length=300)
    artist: str | None = Field(default=None, max_length=300)
    status: str | None = Field(default=None, max_length=50, examples=["ongoing"])
    type: str | None = Field(default=None, max_length=50, examples=["manhwa"])
    synopsis: str | None = Field(default=None)
    rating: float | None = Field(default=None, ge=0, le=10)
    total_view: int | None = Field(default=None, ge=0, examples=[238500])
    source_url: str = Field(...)
    source_name: str = Field(..., max_length=100, examples=["komiku"])

    _BOUNDED_TEXT_LIMITS: ClassVar[dict[str, int]] = {
        "title": 500,
        "slug": 600,
        "author": 300,
        "artist": 300,
        "status": 50,
        "type": 50,
        "source_name": 100,
    }
    _OPTIONAL_TEXT_FIELDS: ClassVar[set[str]] = {"author", "artist", "status", "type"}

    @field_validator(
        "title",
        "slug",
        "author",
        "artist",
        "status",
        "type",
        "source_name",
        mode="before",
    )
    @classmethod
    def _normalize_bounded_text(cls, value: str | None, info: ValidationInfo) -> str | None:
        """Rapikan whitespace dan potong aman sebelum validasi max_length dijalankan."""
        if value is None:
            return None
        if not isinstance(value, str):
            return value

        cleaned = " ".join(value.split()).strip()
        if not cleaned:
            if info.field_name in cls._OPTIONAL_TEXT_FIELDS:
                return None
            return cleaned

        limit = cls._BOUNDED_TEXT_LIMITS[info.field_name]
        if len(cleaned) <= limit:
            return cleaned
        return cleaned[:limit].rstrip(" ,;/|-")

    @field_validator("rating", mode="before")
    @classmethod
    def _normalize_rating(cls, value: float | str | None) -> float | None:
        """Normalisasi rating source ke skala 0-10 sebelum validasi ge/le."""
        if value is None:
            return None

        if isinstance(value, str):
            cleaned = " ".join(value.split()).strip()
            if not cleaned:
                return None
            try:
                numeric_value = float(cleaned)
            except ValueError:
                return None
        else:
            numeric_value = float(value)

        if numeric_value < 0:
            return None
        if numeric_value <= 10:
            return round(numeric_value, 2)
        if numeric_value <= 100:
            return round(numeric_value / 10, 2)
        return None


class ComicCreate(ComicBase):
    """Schema untuk membuat komik baru (input dari scraper)."""
    genres: list[str] = Field(default_factory=list, description="List of genre names")


class ComicResponse(ComicBase):
    """Schema response komik — lengkap dengan genres & metadata DB."""
    id: int
    genres: list[GenreResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    total_chapters: int = Field(default=0)

    model_config = {"from_attributes": True}


class ComicListResponse(BaseModel):
    """Schema response untuk list komik dengan pagination."""
    items: list[ComicResponse]
    total: int
    page: int
    page_size: int
    total_pages: int
