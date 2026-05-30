"""history per chapter

Revision ID: 9d2f6a7b4c10
Revises: 8c4a2e9f0b17
Create Date: 2026-05-29 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "9d2f6a7b4c10"
down_revision: Union[str, Sequence[str], None] = "8c4a2e9f0b17"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.drop_constraint(
        "uq_user_history_comic",
        "user_history_entries",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_user_history_chapter",
        "user_history_entries",
        ["user_id", "chapter_id"],
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint(
        "uq_user_history_chapter",
        "user_history_entries",
        type_="unique",
    )
    op.execute(
        """
        delete from user_history_entries h
        using user_history_entries newer
        where h.user_id = newer.user_id
          and h.comic_id = newer.comic_id
          and (
            h.last_read_at < newer.last_read_at
            or (h.last_read_at = newer.last_read_at and h.id < newer.id)
          )
        """
    )
    op.create_unique_constraint(
        "uq_user_history_comic",
        "user_history_entries",
        ["user_id", "comic_id"],
    )
