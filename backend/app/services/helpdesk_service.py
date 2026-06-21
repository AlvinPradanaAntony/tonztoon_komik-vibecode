"""Service layer for helpdesk reviews and problem reports."""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import HelpdeskSubmission
from app.schemas import (
    HelpdeskSubmissionCreateRequest,
    HelpdeskSubmissionListResponse,
    HelpdeskSubmissionResponse,
    HelpdeskSubmissionUpdateRequest,
)
from app.services.profile_service import ensure_profile_for_auth_user


def _utcnow() -> datetime:
    return datetime.now(UTC)


def build_helpdesk_response(
    submission: HelpdeskSubmission,
) -> HelpdeskSubmissionResponse:
    return HelpdeskSubmissionResponse(
        id=submission.id,
        reference_code=submission.reference_code,
        user_id=submission.user_id,
        category=submission.category,
        rating=submission.rating,
        title=submission.title,
        message=submission.message,
        platform=submission.platform,
        app_version=submission.app_version,
        app_build=submission.app_build,
        locale=submission.locale,
        client_context=submission.client_context or {},
        status=submission.status,
        admin_note=submission.admin_note,
        created_at=submission.created_at,
        updated_at=submission.updated_at,
    )


async def create_helpdesk_submission(
    db: AsyncSession,
    payload: HelpdeskSubmissionCreateRequest,
    *,
    user_id: UUID | None = None,
    user_metadata: dict | None = None,
) -> HelpdeskSubmissionResponse:
    """Persist a guest or authenticated helpdesk submission."""
    if user_id is not None:
        await ensure_profile_for_auth_user(
            db,
            user_id,
            user_metadata=user_metadata,
        )

    submission = HelpdeskSubmission(
        reference_code=await _unique_reference_code(db),
        user_id=user_id,
        category=payload.category,
        rating=payload.rating,
        title=payload.title,
        message=payload.message,
        platform=payload.platform,
        app_version=payload.app_version,
        app_build=payload.app_build,
        locale=payload.locale,
        client_context=payload.client_context,
    )
    db.add(submission)
    await db.commit()
    await db.refresh(submission)
    return build_helpdesk_response(submission)


async def list_helpdesk_submissions(
    db: AsyncSession,
    *,
    page: int,
    per_page: int,
    category: str | None = None,
    status: str | None = None,
) -> HelpdeskSubmissionListResponse:
    filters = []
    if category is not None:
        filters.append(HelpdeskSubmission.category == category)
    if status is not None:
        filters.append(HelpdeskSubmission.status == status)

    total = await db.scalar(
        select(func.count(HelpdeskSubmission.id)).where(*filters)
    )
    result = await db.execute(
        select(HelpdeskSubmission)
        .where(*filters)
        .order_by(
            HelpdeskSubmission.created_at.desc(),
            HelpdeskSubmission.id.desc(),
        )
        .offset((page - 1) * per_page)
        .limit(per_page)
    )
    return HelpdeskSubmissionListResponse(
        items=[
            build_helpdesk_response(submission)
            for submission in result.scalars().all()
        ],
        total=int(total or 0),
        page=page,
        per_page=per_page,
    )


async def update_helpdesk_submission(
    db: AsyncSession,
    submission_id: UUID,
    payload: HelpdeskSubmissionUpdateRequest,
) -> HelpdeskSubmissionResponse:
    result = await db.execute(
        select(HelpdeskSubmission).where(HelpdeskSubmission.id == submission_id)
    )
    submission = result.scalars().first()
    if submission is None:
        raise LookupError("Submission helpdesk tidak ditemukan.")

    if payload.status is not None:
        submission.status = payload.status
    if "admin_note" in payload.model_fields_set:
        submission.admin_note = payload.admin_note
    submission.updated_at = _utcnow()
    await db.commit()
    await db.refresh(submission)
    return build_helpdesk_response(submission)


async def delete_helpdesk_submission(
    db: AsyncSession,
    submission_id: UUID,
) -> None:
    result = await db.execute(
        select(HelpdeskSubmission).where(HelpdeskSubmission.id == submission_id)
    )
    submission = result.scalars().first()
    if submission is None:
        raise LookupError("Submission helpdesk tidak ditemukan.")
    await db.delete(submission)
    await db.commit()


async def _unique_reference_code(db: AsyncSession) -> str:
    for _ in range(5):
        code = f"TT-{secrets.token_hex(4).upper()}"
        exists = await db.scalar(
            select(HelpdeskSubmission.id).where(
                HelpdeskSubmission.reference_code == code
            )
        )
        if exists is None:
            return code
    raise RuntimeError("Tidak dapat membuat reference code helpdesk.")
