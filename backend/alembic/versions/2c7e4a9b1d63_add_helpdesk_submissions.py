"""add helpdesk submissions

Revision ID: 2c7e4a9b1d63
Revises: 9b6f1c2a4d3e
Create Date: 2026-06-05 00:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "2c7e4a9b1d63"
down_revision: Union[str, Sequence[str], None] = "9b6f1c2a4d3e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "helpdesk_submissions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reference_code", sa.String(length=16), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("category", sa.String(length=20), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=True),
        sa.Column("title", sa.String(length=120), nullable=True),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("platform", sa.String(length=30), nullable=False),
        sa.Column("app_version", sa.String(length=50), nullable=True),
        sa.Column("app_build", sa.String(length=30), nullable=True),
        sa.Column("locale", sa.String(length=30), nullable=True),
        sa.Column(
            "client_context",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="{}",
            nullable=False,
        ),
        sa.Column(
            "status",
            sa.String(length=20),
            server_default="open",
            nullable=False,
        ),
        sa.Column("admin_note", sa.Text(), nullable=True),
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
        sa.CheckConstraint(
            "category IN ('review', 'report')",
            name="ck_helpdesk_submissions_category",
        ),
        sa.CheckConstraint(
            "status IN ('open', 'in_progress', 'resolved', 'closed')",
            name="ck_helpdesk_submissions_status",
        ),
        sa.CheckConstraint(
            "(category = 'review' AND rating BETWEEN 1 AND 5) "
            "OR (category = 'report' AND rating IS NULL)",
            name="ck_helpdesk_submissions_rating",
        ),
        sa.CheckConstraint(
            "(category = 'review') OR "
            "(category = 'report' AND title IS NOT NULL AND length(title) >= 5)",
            name="ck_helpdesk_submissions_report_title",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["profiles.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("reference_code"),
    )
    op.create_index(
        "ix_helpdesk_submissions_status_created_at",
        "helpdesk_submissions",
        ["status", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_helpdesk_submissions_category_created_at",
        "helpdesk_submissions",
        ["category", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_helpdesk_submissions_user_created_at",
        "helpdesk_submissions",
        ["user_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_helpdesk_submissions_user_created_at",
        table_name="helpdesk_submissions",
    )
    op.drop_index(
        "ix_helpdesk_submissions_category_created_at",
        table_name="helpdesk_submissions",
    )
    op.drop_index(
        "ix_helpdesk_submissions_status_created_at",
        table_name="helpdesk_submissions",
    )
    op.drop_table("helpdesk_submissions")
