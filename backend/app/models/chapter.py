"""
Tonztoon Komik — Chapter Model

Chapter menyimpan daftar gambar langsung di kolom JSONB `images`
untuk menghindari jutaan baris di tabel terpisah.

Format JSONB `images`:
[
    {"page": 1, "url": "https://cdn.example.com/chap1/001.jpg"},
    {"page": 2, "url": "https://cdn.example.com/chap1/002.jpg"},
    ...
]
"""

from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Chapter(Base):
    """Tabel chapter — setiap chapter milik satu Comic."""

    __tablename__ = "chapters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    comic_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("comics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    chapter_number: Mapped[float] = mapped_column(Float, nullable=False)
    title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_url: Mapped[str] = mapped_column(String(1000), nullable=False)

    release_date: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    # JSONB — array of image objects [{"page": int, "url": str}, ...]
    images: Mapped[list | None] = mapped_column(JSONB, nullable=True, default=list)

    # Relationship
    comic = relationship("Comic", back_populates="chapters")

    def __repr__(self) -> str:
        return f"<Chapter(id={self.id}, comic_id={self.comic_id}, number={self.chapter_number})>"
