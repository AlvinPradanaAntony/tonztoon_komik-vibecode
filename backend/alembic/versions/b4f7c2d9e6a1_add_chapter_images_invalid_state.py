"""add chapter images invalid state

Revision ID: b4f7c2d9e6a1
Revises: d6f9b2e5a8c3
Create Date: 2026-06-02 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

CHAPTER_IMAGES_ARE_INVALID_SQL = """
CASE
    WHEN images IS NULL THEN true
    WHEN jsonb_typeof(images) <> 'array' THEN true
    ELSE
        jsonb_array_length(images) = 0
        OR jsonb_path_exists(
            images,
            '$[*] ? (!exists(@.page) || !exists(@.url) || @.url == "")'::jsonpath
        )
END
"""


# revision identifiers, used by Alembic.
revision: str = "b4f7c2d9e6a1"
down_revision: Union[str, Sequence[str], None] = "d6f9b2e5a8c3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "chapters",
        sa.Column(
            "images_are_invalid",
            sa.Boolean(),
            sa.Computed(CHAPTER_IMAGES_ARE_INVALID_SQL, persisted=True),
            nullable=False,
        ),
    )
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_chapters_images_are_invalid_pending",
            "chapters",
            ["id"],
            unique=False,
            postgresql_where=sa.text("images_are_invalid IS TRUE"),
            postgresql_concurrently=True,
        )


def downgrade() -> None:
    """Downgrade schema."""
    with op.get_context().autocommit_block():
        op.drop_index(
            "ix_chapters_images_are_invalid_pending",
            table_name="chapters",
            postgresql_concurrently=True,
        )
    op.drop_column("chapters", "images_are_invalid")
