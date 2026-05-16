"""add user completed chapters

Revision ID: 8c4a2e9f0b17
Revises: 6b8e2f4a9d31
Create Date: 2026-05-15 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "8c4a2e9f0b17"
down_revision: Union[str, Sequence[str], None] = "6b8e2f4a9d31"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "user_completed_chapters",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comic_id", sa.Integer(), nullable=False),
        sa.Column("chapter_id", sa.Integer(), nullable=False),
        sa.Column(
            "completed_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["chapter_id"], ["chapters.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["comic_id"], ["comics.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "comic_id",
            "chapter_id",
            name="uq_user_completed_chapter",
        ),
    )
    op.create_index(
        "ix_user_completed_chapters_user_id",
        "user_completed_chapters",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_completed_chapters_comic_id",
        "user_completed_chapters",
        ["comic_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_completed_chapters_chapter_id",
        "user_completed_chapters",
        ["chapter_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_completed_chapters_user_comic",
        "user_completed_chapters",
        ["user_id", "comic_id"],
        unique=False,
    )
    op.execute(
        """
        insert into user_completed_chapters (
          user_id,
          comic_id,
          chapter_id,
          completed_at
        )
        select
          user_id,
          comic_id,
          chapter_id,
          coalesce(last_read_at, now())
        from user_progress
        where is_completed = true
        on conflict do nothing
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(
        "ix_user_completed_chapters_user_comic",
        table_name="user_completed_chapters",
    )
    op.drop_index(
        "ix_user_completed_chapters_chapter_id",
        table_name="user_completed_chapters",
    )
    op.drop_index(
        "ix_user_completed_chapters_comic_id",
        table_name="user_completed_chapters",
    )
    op.drop_index(
        "ix_user_completed_chapters_user_id",
        table_name="user_completed_chapters",
    )
    op.drop_table("user_completed_chapters")
