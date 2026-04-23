"""add profiles table

Revision ID: a6d4c3b2e1f0
Revises: f2a1c7d9b8e4
Create Date: 2026-04-23 21:10:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "a6d4c3b2e1f0"
down_revision: Union[str, None] = "f2a1c7d9b8e4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("username", sa.String(length=50), nullable=True),
        sa.Column("normalized_username", sa.String(length=50), nullable=True),
        sa.Column("display_name", sa.String(length=120), nullable=True),
        sa.Column("avatar_url", sa.String(length=1000), nullable=True),
        sa.Column(
            "onboarding_completed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_profiles_normalized_username",
        "profiles",
        ["normalized_username"],
        unique=True,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_profiles_normalized_username", table_name="profiles")
    op.drop_table("profiles")
