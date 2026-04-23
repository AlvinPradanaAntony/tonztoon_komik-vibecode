"""add user library tables

Revision ID: f2a1c7d9b8e4
Revises: e1b3a9c2f4d1
Create Date: 2026-04-23 18:40:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "f2a1c7d9b8e4"
down_revision: Union[str, None] = "e1b3a9c2f4d1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "reader_preferences",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "default_reading_mode",
            sa.String(length=20),
            nullable=False,
            server_default="vertical",
        ),
        sa.Column(
            "reading_direction",
            sa.String(length=10),
            nullable=False,
            server_default="ltr",
        ),
        sa.Column(
            "auto_next",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "mark_read_on_complete",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "default_binge_mode",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("user_id"),
    )

    op.create_table(
        "user_bookmarks",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "comic_id", name="uq_user_bookmark_comic"),
    )
    op.create_index("ix_user_bookmarks_user_id", "user_bookmarks", ["user_id"], unique=False)
    op.create_index("ix_user_bookmarks_comic_id", "user_bookmarks", ["comic_id"], unique=False)
    op.create_index(
        "ix_user_bookmarks_user_created_at",
        "user_bookmarks",
        ["user_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "user_collections",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("normalized_name", sa.String(length=120), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "normalized_name", name="uq_user_collection_name"),
    )
    op.create_index(
        "ix_user_collections_user_id",
        "user_collections",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_collections_user_updated_at",
        "user_collections",
        ["user_id", "updated_at"],
        unique=False,
    )

    op.create_table(
        "user_collection_comics",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("collection_id", sa.Integer(), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column(
            "added_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["collection_id"], ["user_collections.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("collection_id", "comic_id", name="uq_collection_comic"),
    )
    op.create_index(
        "ix_user_collection_comics_collection_id",
        "user_collection_comics",
        ["collection_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_collection_comics_comic_id",
        "user_collection_comics",
        ["comic_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_collection_comics_collection_added_at",
        "user_collection_comics",
        ["collection_id", "added_at"],
        unique=False,
    )

    op.create_table(
        "user_progress",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column("chapter_id", sa.Integer(), nullable=False),
        sa.Column(
            "reading_mode",
            sa.String(length=20),
            nullable=False,
            server_default="vertical",
        ),
        sa.Column("scroll_offset", sa.Float(), nullable=True),
        sa.Column("page_index", sa.Integer(), nullable=True),
        sa.Column("last_read_page_item_index", sa.Integer(), nullable=True),
        sa.Column("total_page_items", sa.Integer(), nullable=True),
        sa.Column(
            "is_completed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "last_read_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["chapter_id"], ["chapters.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "comic_id", name="uq_user_progress_comic"),
    )
    op.create_index("ix_user_progress_user_id", "user_progress", ["user_id"], unique=False)
    op.create_index("ix_user_progress_comic_id", "user_progress", ["comic_id"], unique=False)
    op.create_index("ix_user_progress_chapter_id", "user_progress", ["chapter_id"], unique=False)
    op.create_index(
        "ix_user_progress_user_last_read_at",
        "user_progress",
        ["user_id", "last_read_at"],
        unique=False,
    )

    op.create_table(
        "user_history_entries",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column("chapter_id", sa.Integer(), nullable=False),
        sa.Column(
            "reading_mode",
            sa.String(length=20),
            nullable=False,
            server_default="vertical",
        ),
        sa.Column("scroll_offset", sa.Float(), nullable=True),
        sa.Column("page_index", sa.Integer(), nullable=True),
        sa.Column("last_read_page_item_index", sa.Integer(), nullable=True),
        sa.Column("total_page_items", sa.Integer(), nullable=True),
        sa.Column(
            "last_read_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["chapter_id"], ["chapters.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "comic_id", name="uq_user_history_comic"),
    )
    op.create_index(
        "ix_user_history_entries_user_id",
        "user_history_entries",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_history_entries_comic_id",
        "user_history_entries",
        ["comic_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_history_entries_chapter_id",
        "user_history_entries",
        ["chapter_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_history_entries_user_last_read_at",
        "user_history_entries",
        ["user_id", "last_read_at"],
        unique=False,
    )

    op.create_table(
        "user_favorite_scenes",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column("chapter_id", sa.Integer(), nullable=False),
        sa.Column("page_item_index", sa.Integer(), nullable=False),
        sa.Column("image_url", sa.String(length=1000), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["chapter_id"], ["chapters.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "chapter_id",
            "page_item_index",
            name="uq_user_favorite_scene_page",
        ),
    )
    op.create_index(
        "ix_user_favorite_scenes_user_id",
        "user_favorite_scenes",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_favorite_scenes_comic_id",
        "user_favorite_scenes",
        ["comic_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_favorite_scenes_chapter_id",
        "user_favorite_scenes",
        ["chapter_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_favorite_scenes_user_created_at",
        "user_favorite_scenes",
        ["user_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "user_download_entries",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column("chapter_id", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("source_device_id", sa.String(length=120), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("downloaded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["chapter_id"], ["chapters.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "chapter_id", name="uq_user_download_chapter"),
    )
    op.create_index(
        "ix_user_download_entries_user_id",
        "user_download_entries",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_download_entries_comic_id",
        "user_download_entries",
        ["comic_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_download_entries_chapter_id",
        "user_download_entries",
        ["chapter_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_download_entries_user_updated_at",
        "user_download_entries",
        ["user_id", "updated_at"],
        unique=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_user_download_entries_user_updated_at", table_name="user_download_entries")
    op.drop_index("ix_user_download_entries_chapter_id", table_name="user_download_entries")
    op.drop_index("ix_user_download_entries_comic_id", table_name="user_download_entries")
    op.drop_index("ix_user_download_entries_user_id", table_name="user_download_entries")
    op.drop_table("user_download_entries")

    op.drop_index("ix_user_favorite_scenes_user_created_at", table_name="user_favorite_scenes")
    op.drop_index("ix_user_favorite_scenes_chapter_id", table_name="user_favorite_scenes")
    op.drop_index("ix_user_favorite_scenes_comic_id", table_name="user_favorite_scenes")
    op.drop_index("ix_user_favorite_scenes_user_id", table_name="user_favorite_scenes")
    op.drop_table("user_favorite_scenes")

    op.drop_index("ix_user_history_entries_user_last_read_at", table_name="user_history_entries")
    op.drop_index("ix_user_history_entries_chapter_id", table_name="user_history_entries")
    op.drop_index("ix_user_history_entries_comic_id", table_name="user_history_entries")
    op.drop_index("ix_user_history_entries_user_id", table_name="user_history_entries")
    op.drop_table("user_history_entries")

    op.drop_index("ix_user_progress_user_last_read_at", table_name="user_progress")
    op.drop_index("ix_user_progress_chapter_id", table_name="user_progress")
    op.drop_index("ix_user_progress_comic_id", table_name="user_progress")
    op.drop_index("ix_user_progress_user_id", table_name="user_progress")
    op.drop_table("user_progress")

    op.drop_index(
        "ix_user_collection_comics_collection_added_at",
        table_name="user_collection_comics",
    )
    op.drop_index("ix_user_collection_comics_comic_id", table_name="user_collection_comics")
    op.drop_index(
        "ix_user_collection_comics_collection_id",
        table_name="user_collection_comics",
    )
    op.drop_table("user_collection_comics")

    op.drop_index("ix_user_collections_user_updated_at", table_name="user_collections")
    op.drop_index("ix_user_collections_user_id", table_name="user_collections")
    op.drop_table("user_collections")

    op.drop_index("ix_user_bookmarks_user_created_at", table_name="user_bookmarks")
    op.drop_index("ix_user_bookmarks_comic_id", table_name="user_bookmarks")
    op.drop_index("ix_user_bookmarks_user_id", table_name="user_bookmarks")
    op.drop_table("user_bookmarks")

    op.drop_table("reader_preferences")
