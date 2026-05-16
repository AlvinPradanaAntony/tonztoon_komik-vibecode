"""default mark read on complete false

Revision ID: 6b8e2f4a9d31
Revises: 3d9f1a7c2b60
Create Date: 2026-05-15 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "6b8e2f4a9d31"
down_revision: Union[str, Sequence[str], None] = "3d9f1a7c2b60"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("update reader_preferences set mark_read_on_complete = false")
    op.alter_column(
        "reader_preferences",
        "mark_read_on_complete",
        existing_type=sa.Boolean(),
        server_default=sa.text("false"),
        existing_nullable=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column(
        "reader_preferences",
        "mark_read_on_complete",
        existing_type=sa.Boolean(),
        server_default=sa.text("true"),
        existing_nullable=False,
    )
