"""
Tonztoon Komik — Chapter Pydantic Schemas

Berisi schema item gambar untuk memvalidasi array JSONB
yang disimpan pada setiap row `chapter.images`.
"""

from pydantic import BaseModel, Field


class ChapterImageItem(BaseModel):
    """Satu item gambar di dalam array JSONB chapter.images."""
    page: int = Field(..., ge=1, examples=[1])
    url: str = Field(..., examples=["https://cdn.komiku.org/chapter1/001.jpg"])
    width: int | None = Field(default=None, gt=0, examples=[720])
    height: int | None = Field(default=None, gt=0, examples=[2500])
