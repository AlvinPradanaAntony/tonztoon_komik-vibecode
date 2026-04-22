"""
Schemas untuk endpoint source-scoped API.
"""

from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, Field, field_serializer

from app.schemas.chapter import ChapterImageItem

WIB = timezone(timedelta(hours=7))


class SourceInfoResponse(BaseModel):
    """Metadata dasar satu source yang aktif di backend."""

    id: str = Field(..., examples=["komiku_asia"])
    label: str = Field(..., examples=["Komiku Asia"])
    base_url: str = Field(..., examples=["https://01.komiku.asia"])
    enabled: bool = Field(default=True)
    source_comic_count: int | None = Field(
        default=None,
        ge=0,
        examples=[None],
        description="Total komik pada source asli dari refresh terakhir yang tersimpan di source_stats.",
    )
    source_comic_count_last_refreshed_at: datetime | None = Field(
        default=None,
        description="Waktu terakhir source_comic_count berhasil direfresh dari source asli.",
    )
    db_comic_count: int = Field(
        default=0,
        ge=0,
        examples=[1243],
        description="Total komik source ini yang sudah tersimpan di database lokal.",
    )

    @field_serializer("source_comic_count_last_refreshed_at", when_used="json")
    def serialize_source_comic_count_last_refreshed_at(
        self,
        value: datetime | None,
    ) -> str | None:
        """Serialisasikan timestamp freshness ke zona waktu WIB (UTC+07:00)."""
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(WIB).isoformat()


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
