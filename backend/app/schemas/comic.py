"""
Tonztoon Komik — Comic & Genre Pydantic Schemas

Digunakan oleh:
- FastAPI: request/response serialization
- Scraper: validasi data hasil scraping sebelum insert ke DB
"""

from datetime import datetime

from pydantic import BaseModel, Field


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
    source_url: str = Field(...)
    source_name: str = Field(..., max_length=100, examples=["komiku"])


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
