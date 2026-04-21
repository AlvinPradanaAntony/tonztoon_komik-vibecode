"""add_total_view_to_comics

Revision ID: c9b7d2e41f3a
Revises: 4e6a5f7b9c21
Create Date: 2026-04-18 17:20:00.000000

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "c9b7d2e41f3a"
down_revision: Union[str, Sequence[str], None] = "4e6a5f7b9c21"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("comics", sa.Column("total_view", sa.Integer(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("comics", "total_view")
