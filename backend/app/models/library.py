"""
Tonztoon Komik — User Library & Reading Sync Models

Lapisan domain user untuk kebutuhan frontend:
- progress / continue reading
- bookmarks
- collections
- favorite scenes
- history
- download intents (offline wishlist per chapter)
- reader preferences

Auth provider belum diikat langsung ke backend. Untuk sementara semua data
di-scope menggunakan `user_id` (UUID) agar mudah dipetakan ke Supabase Auth
di fase berikutnya tanpa mengubah model domain inti.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class ReaderPreference(Base):
    """Preferensi reader yang disinkronkan per user."""

    __tablename__ = "reader_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
    )
    default_reading_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="vertical",
        server_default="vertical",
    )
    reading_direction: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
        default="ltr",
        server_default="ltr",
    )
    auto_next: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )
    mark_read_on_complete: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )
    default_binge_mode: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class UserBookmark(Base):
    """Bookmark komik milik user."""

    __tablename__ = "user_bookmarks"
    __table_args__ = (
        UniqueConstraint("user_id", "comic_id", name="uq_user_bookmark_comic"),
        Index("ix_user_bookmarks_user_created_at", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    comic = relationship("Comic", lazy="joined")


class UserCollection(Base):
    """Folder/koleksi komik milik user."""

    __tablename__ = "user_collections"
    __table_args__ = (
        UniqueConstraint("user_id", "normalized_name", name="uq_user_collection_name"),
        Index("ix_user_collections_user_updated_at", "user_id", "updated_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    items: Mapped[list["UserCollectionComic"]] = relationship(
        "UserCollectionComic",
        back_populates="collection",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class UserCollectionComic(Base):
    """Asosiasi komik ke dalam satu koleksi."""

    __tablename__ = "user_collection_comics"
    __table_args__ = (
        UniqueConstraint("collection_id", "comic_id", name="uq_collection_comic"),
        Index("ix_user_collection_comics_collection_added_at", "collection_id", "added_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    collection_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("user_collections.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    collection: Mapped["UserCollection"] = relationship(
        "UserCollection",
        back_populates="items",
    )
    comic = relationship("Comic", lazy="joined")


class UserProgress(Base):
    """Posisi baca terakhir per komik untuk continue reading dan sync progress."""

    __tablename__ = "user_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "comic_id", name="uq_user_progress_comic"),
        Index("ix_user_progress_user_last_read_at", "user_id", "last_read_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    chapter_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapters.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    reading_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="vertical",
        server_default="vertical",
    )
    scroll_offset: Mapped[float | None] = mapped_column(Float, nullable=True)
    page_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_read_page_item_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_page_items: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_completed: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    last_read_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    comic = relationship("Comic", lazy="joined")
    chapter = relationship("Chapter", lazy="joined")


class UserHistoryEntry(Base):
    """Riwayat baca ringkas per komik, diurutkan berdasarkan interaksi terakhir."""

    __tablename__ = "user_history_entries"
    __table_args__ = (
        UniqueConstraint("user_id", "comic_id", name="uq_user_history_comic"),
        Index("ix_user_history_entries_user_last_read_at", "user_id", "last_read_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    chapter_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapters.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    reading_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="vertical",
        server_default="vertical",
    )
    scroll_offset: Mapped[float | None] = mapped_column(Float, nullable=True)
    page_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_read_page_item_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_page_items: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_read_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    comic = relationship("Comic", lazy="joined")
    chapter = relationship("Chapter", lazy="joined")


class UserFavoriteScene(Base):
    """Scene favorit user dari page item tertentu dalam satu chapter."""

    __tablename__ = "user_favorite_scenes"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "chapter_id",
            "page_item_index",
            name="uq_user_favorite_scene_page",
        ),
        Index("ix_user_favorite_scenes_user_created_at", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    chapter_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapters.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    page_item_index: Mapped[int] = mapped_column(Integer, nullable=False)
    image_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    comic = relationship("Comic", lazy="joined")
    chapter = relationship("Chapter", lazy="joined")


class UserDownloadEntry(Base):
    """
    Intent unduhan offline per chapter.

    File offline tetap lokal di device. Tabel ini hanya menyimpan intent/status
    sinkronisasi agar frontend bisa merender wishlist dan status antrian cloud.
    """

    __tablename__ = "user_download_entries"
    __table_args__ = (
        UniqueConstraint("user_id", "chapter_id", name="uq_user_download_chapter"),
        Index("ix_user_download_entries_user_updated_at", "user_id", "updated_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    comic_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("comics.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    chapter_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("chapters.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        server_default="pending",
    )
    source_device_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    requested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    downloaded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    comic = relationship("Comic", lazy="joined")
    chapter = relationship("Chapter", lazy="joined")
