"""Add operational admin schema without changing business columns.

Revision ID: admin_console_20261025
Revises: d3f8a1c9e6b2
"""
from pathlib import Path
from alembic import op

revision="admin_console_20261025"
down_revision="d3f8a1c9e6b2"
branch_labels=None
depends_on=None


def upgrade():
    source=Path(__file__).resolve().parents[2]/"sql"/"20261025_admin_console.sql"
    for statement in source.read_text(encoding="utf-8").split(";"):
        if statement.strip():
            op.execute(statement)


def downgrade():
    for name in ("security_events","event_quotas","incidents","probes","buckets","events","outbox","operations","audit","editorial","admin_sessions"):
        op.drop_table(name,schema="monitoring")
