"""
Tonztoon Komik — Source Stats Model

Menyimpan statistik ringkas per source yang direfresh oleh job terpisah,
agar endpoint publik tidak perlu melakukan live scrape.
"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SourceStat(Base):
    """Snapshot statistik satu source pada waktu refresh terakhir."""

    __tablename__ = "source_stats"

    source_name: Mapped[str] = mapped_column(String(100), primary_key=True)
    source_comic_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_refreshed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_attempted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    def __repr__(self) -> str:
        return (
            f"<SourceStat(source_name='{self.source_name}', "
            f"source_comic_count={self.source_comic_count})>"
        )
