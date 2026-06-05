"""Helpdesk review and issue report persistence models."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class HelpdeskSubmission(Base):
    """A review or problem report submitted from the TonzToon client."""

    __tablename__ = "helpdesk_submissions"
    __table_args__ = (
        CheckConstraint(
            "category IN ('review', 'report')",
            name="ck_helpdesk_submissions_category",
        ),
        CheckConstraint(
            "status IN ('open', 'in_progress', 'resolved', 'closed')",
            name="ck_helpdesk_submissions_status",
        ),
        CheckConstraint(
            "(category = 'review' AND rating BETWEEN 1 AND 5) "
            "OR (category = 'report' AND rating IS NULL)",
            name="ck_helpdesk_submissions_rating",
        ),
        CheckConstraint(
            "(category = 'review') OR "
            "(category = 'report' AND title IS NOT NULL AND length(title) >= 5)",
            name="ck_helpdesk_submissions_report_title",
        ),
        Index(
            "ix_helpdesk_submissions_status_created_at",
            "status",
            "created_at",
        ),
        Index(
            "ix_helpdesk_submissions_category_created_at",
            "category",
            "created_at",
        ),
        Index("ix_helpdesk_submissions_user_created_at", "user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    reference_code: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        unique=True,
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("profiles.id", ondelete="SET NULL"),
        nullable=True,
    )
    category: Mapped[str] = mapped_column(String(20), nullable=False)
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(String(30), nullable=False)
    app_version: Mapped[str | None] = mapped_column(String(50), nullable=True)
    app_build: Mapped[str | None] = mapped_column(String(30), nullable=True)
    locale: Mapped[str | None] = mapped_column(String(30), nullable=True)
    client_context: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        default=dict,
        server_default="{}",
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="open",
        server_default="open",
    )
    admin_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
