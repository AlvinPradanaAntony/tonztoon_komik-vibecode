"""
Tonztoon Komik — Comic & Genre Models

Defines the Comic, Genre, and the many-to-many association table comic_genre.
"""

from datetime import datetime

from sqlalchemy import (
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Table,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


# ---- Many-to-Many association table: Comic <-> Genre ----
comic_genre = Table(
    "comic_genre",
    Base.metadata,
    Column("comic_id", Integer, ForeignKey("comics.id", ondelete="CASCADE"), primary_key=True),
    Column("genre_id", Integer, ForeignKey("genres.id", ondelete="CASCADE"), primary_key=True),
)


class Genre(Base):
    """Tabel genre komik (Action, Romance, Fantasy, dsb.)."""

    __tablename__ = "genres"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    slug: Mapped[str] = mapped_column(String(120), unique=True, nullable=False, index=True)

    # Relationship
    comics: Mapped[list["Comic"]] = relationship(
        "Comic",
        secondary=comic_genre,
        back_populates="genres",
    )

    def __repr__(self) -> str:
        return f"<Genre(id={self.id}, name='{self.name}')>"


class Comic(Base):
    """
    Tabel utama komik — menyimpan metadata dari hasil scraping.

    Catatan semantics timestamp:
    - `updated_at` dipakai sebagai jejak teknis kapan row comic terakhir
      diubah oleh sistem.
    - `latest_feed_*` dipakai sebagai sinyal domain untuk urutan endpoint
      `/latest`, karena lebih akurat merepresentasikan comic yang sedang
      muncul di feed update terbaru dari source.
    - `popular_feed_*` dipakai sebagai sinyal domain untuk urutan endpoint
      `/popular`, sehingga endpoint tidak bergantung pada `rating` internal
      yang belum tentu selaras dengan ranking canonical source.
    """

    __tablename__ = "comics"

    __table_args__ = (
        UniqueConstraint("source_name", "slug", name="uq_source_slug"),
        Index(
            "ix_comics_latest_feed_order",
            "latest_feed_batch_at",
            "latest_feed_page",
            "latest_feed_position",
        ),
        Index(
            "ix_comics_popular_feed_order",
            "popular_feed_batch_at",
            "popular_feed_page",
            "popular_feed_position",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False, index=True)
    slug: Mapped[str] = mapped_column(String(600), nullable=False, index=True)
    alternative_titles: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_image_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    author: Mapped[str | None] = mapped_column(String(300), nullable=True)
    artist: Mapped[str | None] = mapped_column(String(300), nullable=True)
    status: Mapped[str | None] = mapped_column(String(50), nullable=True)  # ongoing / completed / hiatus
    type: Mapped[str | None] = mapped_column(String(50), nullable=True)    # manga / manhwa / manhua
    synopsis: Mapped[str | None] = mapped_column(Text, nullable=True)
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    total_view: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_url: Mapped[str] = mapped_column(String(1000), nullable=False)
    source_name: Mapped[str] = mapped_column(String(100), nullable=False)  # komiku / komikcast / shinigami

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    # Marker posisi comic saat terlihat di canonical latest feed.
    # Kombinasi ini dipakai untuk mengurutkan endpoint `/latest` dan sengaja
    # dipisahkan dari `updated_at` agar seeding/full refresh tidak mengacaukan
    # semantik "komik terbaru".
    latest_feed_batch_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    latest_feed_page: Mapped[int | None] = mapped_column(Integer, nullable=True)
    latest_feed_position: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Marker posisi comic saat terlihat di canonical popular feed.
    # Dipisahkan dari `rating` karena ranking popular source bisa berubah walau
    # metadata/rating di DB tidak berubah.
    popular_feed_batch_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    popular_feed_page: Mapped[int | None] = mapped_column(Integer, nullable=True)
    popular_feed_position: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Relationships
    genres: Mapped[list["Genre"]] = relationship(
        "Genre",
        secondary=comic_genre,
        back_populates="comics",
        lazy="selectin",
    )
    chapters: Mapped[list["Chapter"]] = relationship(
        "Chapter",
        back_populates="comic",
        cascade="all, delete-orphan",
        order_by="Chapter.chapter_number.desc()",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<Comic(id={self.id}, title='{self.title}', source='{self.source_name}')>"
