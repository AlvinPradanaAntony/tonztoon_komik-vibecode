"""drop duplicate chapter image job index

Revision ID: f6c1d8e4b2a9
Revises: e3b8c5d7a9f2
Create Date: 2026-06-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "f6c1d8e4b2a9"
down_revision: Union[str, Sequence[str], None] = "e3b8c5d7a9f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Drop explicit unique index duplicated by the chapter_id constraint."""
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_chapter_image_jobs_chapter_id",
            table_name="chapter_image_jobs",
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Recreate the explicit index if this migration is reverted."""
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_chapter_image_jobs_chapter_id",
            "chapter_image_jobs",
            ["chapter_id"],
            unique=True,
            postgresql_concurrently=True,
        )
