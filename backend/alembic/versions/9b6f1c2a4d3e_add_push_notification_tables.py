"""add push notification tables

Revision ID: 9b6f1c2a4d3e
Revises: 0f4a8c2d9e31
Create Date: 2026-06-03 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "9b6f1c2a4d3e"
down_revision: Union[str, Sequence[str], None] = "0f4a8c2d9e31"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create push notification device and event tables."""
    op.create_table(
        "user_push_devices",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider", sa.String(length=20), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["profiles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "provider",
            "token_hash",
            name="uq_user_push_devices_provider_token_hash",
        ),
    )
    op.create_index(
        "ix_user_push_devices_user_active",
        "user_push_devices",
        ["user_id", "active"],
        unique=False,
    )

    op.create_table(
        "push_notification_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("event_id", sa.Text(), nullable=False),
        sa.Column("kind", sa.String(length=80), nullable=False),
        sa.Column("source_name", sa.String(length=100), nullable=True),
        sa.Column("comic_slug", sa.String(length=600), nullable=True),
        sa.Column("chapter_number", sa.Numeric(), nullable=True),
        sa.Column(
            "payload",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="{}",
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("event_id", name="uq_push_notification_events_event_id"),
    )


def downgrade() -> None:
    """Drop push notification tables."""
    op.drop_table("push_notification_events")
    op.drop_index("ix_user_push_devices_user_active", table_name="user_push_devices")
    op.drop_table("user_push_devices")
