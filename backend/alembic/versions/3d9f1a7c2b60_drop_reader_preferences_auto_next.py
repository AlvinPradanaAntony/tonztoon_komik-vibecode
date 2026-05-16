"""drop reader preferences auto next

Revision ID: 3d9f1a7c2b60
Revises: 71c2d9e4f8a0
Create Date: 2026-05-15 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "3d9f1a7c2b60"
down_revision: Union[str, Sequence[str], None] = "71c2d9e4f8a0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.drop_column("reader_preferences", "auto_next")


def downgrade() -> None:
    """Downgrade schema."""
    op.add_column(
        "reader_preferences",
        sa.Column(
            "auto_next",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )
