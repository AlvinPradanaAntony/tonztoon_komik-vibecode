"""add bookmark status override

Revision ID: c2d7e4a9b1f5
Revises: b8e4c6a2d1f0
Create Date: 2026-08-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c2d7e4a9b1f5"
down_revision: Union[str, Sequence[str], None] = "b8e4c6a2d1f0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add a per-user bookmark status override."""
    op.add_column(
        "user_bookmarks",
        sa.Column("status_override", sa.String(length=20), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_bookmarks", "status_override")
