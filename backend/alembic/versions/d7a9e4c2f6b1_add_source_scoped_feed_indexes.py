"""add source scoped feed indexes

Revision ID: d7a9e4c2f6b1
Revises: c8e3a1f6b4d2
Create Date: 2026-06-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "d7a9e4c2f6b1"
down_revision: Union[str, Sequence[str], None] = "c8e3a1f6b4d2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add B-tree indexes aligned with source-scoped feed ordering."""
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_comics_source_latest_feed_order",
            "comics",
            [
                "source_name",
                sa.text("latest_feed_batch_at DESC NULLS LAST"),
                sa.text("latest_feed_page ASC NULLS LAST"),
                sa.text("latest_feed_position ASC NULLS LAST"),
                sa.text("updated_at DESC"),
                "id",
            ],
            unique=False,
            postgresql_concurrently=True,
        )
        op.create_index(
            "ix_comics_source_popular_feed_order",
            "comics",
            [
                "source_name",
                sa.text("popular_feed_batch_at DESC NULLS LAST"),
                sa.text("popular_feed_page ASC NULLS LAST"),
                sa.text("popular_feed_position ASC NULLS LAST"),
                sa.text("rating DESC NULLS LAST"),
                sa.text("total_view DESC NULLS LAST"),
                sa.text("updated_at DESC"),
                "id",
            ],
            unique=False,
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Drop source-scoped feed indexes."""
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_comics_source_popular_feed_order",
            table_name="comics",
            postgresql_concurrently=True,
        )
        op.drop_index(
            "ix_comics_source_latest_feed_order",
            table_name="comics",
            postgresql_concurrently=True,
        )
