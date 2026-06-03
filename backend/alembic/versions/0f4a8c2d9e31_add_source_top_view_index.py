"""add source top view index

Revision ID: 0f4a8c2d9e31
Revises: f6c1d8e4b2a9
Create Date: 2026-06-03 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0f4a8c2d9e31"
down_revision: Union[str, Sequence[str], None] = "f6c1d8e4b2a9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add source-scoped ordering index for top ranking by total views."""
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_comics_source_top_view_order",
            "comics",
            [
                "source_name",
                sa.text("total_view DESC NULLS LAST"),
                sa.text("rating DESC NULLS LAST"),
                "title",
                "id",
            ],
            unique=False,
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Drop source-scoped top ranking index."""
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_comics_source_top_view_order",
            table_name="comics",
            postgresql_concurrently=True,
        )
