"""add_latest_feed_tracking_to_comics

Revision ID: 4e6a5f7b9c21
Revises: 8fdd0234a2df
Create Date: 2026-04-17 03:05:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "4e6a5f7b9c21"
down_revision: Union[str, Sequence[str], None] = "8fdd0234a2df"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "comics",
        sa.Column("latest_feed_batch_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("latest_feed_page", sa.Integer(), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("latest_feed_position", sa.Integer(), nullable=True),
    )
    op.create_index(
        "ix_comics_latest_feed_order",
        "comics",
        ["latest_feed_batch_at", "latest_feed_page", "latest_feed_position"],
        unique=False,
    )
    op.add_column(
        "comics",
        sa.Column("popular_feed_batch_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("popular_feed_page", sa.Integer(), nullable=True),
    )
    op.add_column(
        "comics",
        sa.Column("popular_feed_position", sa.Integer(), nullable=True),
    )
    op.create_index(
        "ix_comics_popular_feed_order",
        "comics",
        ["popular_feed_batch_at", "popular_feed_page", "popular_feed_position"],
        unique=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_comics_popular_feed_order", table_name="comics")
    op.drop_column("comics", "popular_feed_position")
    op.drop_column("comics", "popular_feed_page")
    op.drop_column("comics", "popular_feed_batch_at")
    op.drop_index("ix_comics_latest_feed_order", table_name="comics")
    op.drop_column("comics", "latest_feed_position")
    op.drop_column("comics", "latest_feed_page")
    op.drop_column("comics", "latest_feed_batch_at")
