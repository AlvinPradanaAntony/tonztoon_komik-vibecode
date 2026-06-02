"""add search and genre indexes

Revision ID: e3b8c5d7a9f2
Revises: d7a9e4c2f6b1
Create Date: 2026-06-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "e3b8c5d7a9f2"
down_revision: Union[str, Sequence[str], None] = "d7a9e4c2f6b1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add trigram search indexes and genre association lookup index."""
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_comics_title_trgm",
            "comics",
            [sa.text("title gin_trgm_ops")],
            unique=False,
            postgresql_using="gin",
            postgresql_concurrently=True,
        )
        op.create_index(
            "ix_comics_alternative_titles_trgm",
            "comics",
            [sa.text("alternative_titles gin_trgm_ops")],
            unique=False,
            postgresql_using="gin",
            postgresql_concurrently=True,
        )
        op.create_index(
            "ix_comic_genre_genre_id",
            "comic_genre",
            ["genre_id"],
            unique=False,
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Drop search and genre indexes.

    The pg_trgm extension is intentionally kept because other database objects
    may depend on it after rollout.
    """
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_comic_genre_genre_id",
            table_name="comic_genre",
            postgresql_concurrently=True,
        )
        op.drop_index(
            "ix_comics_alternative_titles_trgm",
            table_name="comics",
            postgresql_concurrently=True,
        )
        op.drop_index(
            "ix_comics_title_trgm",
            table_name="comics",
            postgresql_concurrently=True,
        )
