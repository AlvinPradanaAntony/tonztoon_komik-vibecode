"""add comics source url lookup index

Revision ID: c8e3a1f6b4d2
Revises: b4f7c2d9e6a1
Create Date: 2026-06-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "c8e3a1f6b4d2"
down_revision: Union[str, Sequence[str], None] = "b4f7c2d9e6a1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_comics_source_name_source_url",
            "comics",
            ["source_name", "source_url"],
            unique=False,
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_comics_source_name_source_url",
            table_name="comics",
            postgresql_concurrently=True,
        )
