"""add user bookmark links

Revision ID: a1c4e7b9d2f6
Revises: 2c7e4a9b1d63
Create Date: 2026-06-07 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "a1c4e7b9d2f6"
down_revision: Union[str, Sequence[str], None] = "2c7e4a9b1d63"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_bookmark_links",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("bookmark_id", sa.Integer(), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column(
            "confidence",
            sa.Float(),
            nullable=False,
            server_default="1",
        ),
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
        sa.ForeignKeyConstraint(
            ["bookmark_id"],
            ["user_bookmarks.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "bookmark_id",
            "comic_id",
            name="uq_user_bookmark_link_comic",
        ),
        sa.UniqueConstraint(
            "user_id",
            "comic_id",
            name="uq_user_bookmark_link_user_comic",
        ),
    )
    op.create_index(
        "ix_user_bookmark_links_bookmark_id",
        "user_bookmark_links",
        ["bookmark_id"],
    )
    op.create_index(
        "ix_user_bookmark_links_comic_id",
        "user_bookmark_links",
        ["comic_id"],
    )
    op.create_index(
        "ix_user_bookmark_links_user_id",
        "user_bookmark_links",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_bookmark_links_user_id",
        table_name="user_bookmark_links",
    )
    op.drop_index(
        "ix_user_bookmark_links_comic_id",
        table_name="user_bookmark_links",
    )
    op.drop_index(
        "ix_user_bookmark_links_bookmark_id",
        table_name="user_bookmark_links",
    )
    op.drop_table("user_bookmark_links")
