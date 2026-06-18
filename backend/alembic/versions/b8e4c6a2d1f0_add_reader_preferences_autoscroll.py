"""add reader preferences autoscroll

Revision ID: b8e4c6a2d1f0
Revises: a1c4e7b9d2f6
Create Date: 2026-06-17 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b8e4c6a2d1f0"
down_revision: Union[str, Sequence[str], None] = "a1c4e7b9d2f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "reader_preferences",
        sa.Column(
            "auto_scroll_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "reader_preferences",
        sa.Column(
            "auto_scroll_speed",
            sa.Float(),
            nullable=False,
            server_default="1.0",
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("reader_preferences", "auto_scroll_speed")
    op.drop_column("reader_preferences", "auto_scroll_enabled")
