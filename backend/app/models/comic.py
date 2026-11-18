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
    text,
    select, exists, true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship, foreign

from app.database import Base
from app.config import settings
from app.admin.tables import editorial


# ---- Many-to-Many association table: Comic <-> Genre ----
comic_genre = Table(
    "comic_genre",
    Base.metadata,
    Column("comic_id", Integer, ForeignKey("comics.id", ondelete="CASCADE"), primary_key=True),
    Column("genre_id", Integer, ForeignKey("genres.id", ondelete="CASCADE"), primary_key=True),
    Index("ix_comic_genre_genre_id", "genre_id"),
)

effective_comic_genre=comic_genre
if settings.ADMIN_CONSOLE_ENABLED:
    selected_genres=func.jsonb_array_elements_text(editorial.c.overrides["genre_ids"]).table_valued("value").lateral("selected_genres")
    manual=select(editorial.c.resource_id.label("comic_id"),selected_genres.c.value.cast(Integer).label("genre_id")).select_from(
        editorial.join(selected_genres,true())).where(editorial.c.kind=="comics",editorial.c.overrides.has_key("genre_ids"))
    original=select(comic_genre.c.comic_id,comic_genre.c.genre_id).where(~exists(select(1).where(
        editorial.c.kind=="comics",editorial.c.resource_id==comic_genre.c.comic_id,editorial.c.overrides.has_key("genre_ids"))))
    effective_comic_genre=original.union_all(manual).subquery("effective_comic_genre")


class Genre(Base):
    """Tabel genre komik (Action, Romance, Fantasy, dsb.)."""

    __tablename__ = "genres"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    slug: Mapped[str] = mapped_column(String(120), unique=True, nullable=False, index=True)

    # Relationship
    comics: Mapped[list["Comic"]] = relationship(
        "Comic",
        secondary=effective_comic_genre,
        primaryjoin=lambda:Genre.id==foreign(effective_comic_genre.c.genre_id),
        secondaryjoin=lambda:Comic.id==foreign(effective_comic_genre.c.comic_id),
        viewonly=settings.ADMIN_CONSOLE_ENABLED,
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
        Index(
            "ix_comics_source_latest_feed_order",
            "source_name",
            text("latest_feed_batch_at DESC NULLS LAST"),
            text("latest_feed_page ASC NULLS LAST"),
            text("latest_feed_position ASC NULLS LAST"),
            text("updated_at DESC"),
            "id",
        ),
        Index(
            "ix_comics_source_popular_feed_order",
            "source_name",
            text("popular_feed_batch_at DESC NULLS LAST"),
            text("popular_feed_page ASC NULLS LAST"),
            text("popular_feed_position ASC NULLS LAST"),
            text("rating DESC NULLS LAST"),
            text("total_view DESC NULLS LAST"),
            text("updated_at DESC"),
            "id",
        ),
        Index(
            "ix_comics_source_top_view_order",
            "source_name",
            text("total_view DESC NULLS LAST"),
            text("rating DESC NULLS LAST"),
            "title",
            "id",
        ),
        Index(
            "ix_comics_source_name_source_url",
            "source_name",
            "source_url",
        ),
        Index(
            "ix_comics_title_trgm",
            "title",
            postgresql_using="gin",
            postgresql_ops={"title": "gin_trgm_ops"},
        ),
        Index(
            "ix_comics_alternative_titles_trgm",
            "alternative_titles",
            postgresql_using="gin",
            postgresql_ops={"alternative_titles": "gin_trgm_ops"},
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    _source_title: Mapped[str] = mapped_column("title", String(500), nullable=False, index=True)
    slug: Mapped[str] = mapped_column(String(600), nullable=False, index=True)
    _source_alternative_titles: Mapped[str | None] = mapped_column("alternative_titles", Text, nullable=True)
    _source_cover_image_url: Mapped[str | None] = mapped_column("cover_image_url", String(1000), nullable=True)
    _source_author: Mapped[str | None] = mapped_column("author", String(300), nullable=True)
    _source_artist: Mapped[str | None] = mapped_column("artist", String(300), nullable=True)
    _source_status: Mapped[str | None] = mapped_column("status", String(50), nullable=True)
    _source_type: Mapped[str | None] = mapped_column("type", String(50), nullable=True)
    _source_synopsis: Mapped[str | None] = mapped_column("synopsis", Text, nullable=True)
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    total_view: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_url: Mapped[str] = mapped_column(String(1000), nullable=False)
    source_name: Mapped[str] = mapped_column(String(100), nullable=False)  # komiku / voratoon / shinigami / komiku_asia

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
        secondary=effective_comic_genre,
        primaryjoin=lambda:Comic.id==foreign(effective_comic_genre.c.comic_id),
        secondaryjoin=lambda:Genre.id==foreign(effective_comic_genre.c.genre_id),
        viewonly=settings.ADMIN_CONSOLE_ENABLED,
        back_populates="comics",
        lazy="selectin",
    )
    chapters: Mapped[list["Chapter"]] = relationship(
        "Chapter",
        back_populates="comic",
        cascade="all, delete-orphan",
        order_by="Chapter.chapter_number.desc()",
        lazy="raise",
    )

    def __repr__(self) -> str:
        return f"<Comic(id={self.id}, title='{self.title}', source='{self.source_name}')>"


from app.admin.editorial import install_fields
install_fields(Comic, "comics", ("title", "alternative_titles", "cover_image_url", "author", "artist", "status", "type", "synopsis"))
