"""Helpdesk submission and administration endpoints."""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_optional_auth_user
from app.api.errors import raise_api_error
from app.api.v1.account_manager import require_account_manager_admin
from app.database import get_db
from app.schemas import (
    AuthenticatedUser,
    HelpdeskSubmissionCreateRequest,
    HelpdeskSubmissionListResponse,
    HelpdeskSubmissionResponse,
    HelpdeskSubmissionUpdateRequest,
)
from app.services.helpdesk_service import (
    create_helpdesk_submission,
    list_helpdesk_submissions,
    update_helpdesk_submission,
)

router = APIRouter()


@router.post(
    "/submissions",
    response_model=HelpdeskSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def post_helpdesk_submission(
    payload: HelpdeskSubmissionCreateRequest,
    auth_user: AuthenticatedUser | None = Depends(get_optional_auth_user),
    db: AsyncSession = Depends(get_db),
):
    """Store a review or report from either a guest or logged-in user."""
    claims = auth_user.raw_claims if auth_user is not None else {}
    user_metadata = claims.get("user_metadata") if claims else None
    return await create_helpdesk_submission(
        db,
        payload,
        user_id=auth_user.user_id if auth_user is not None else None,
        user_metadata=user_metadata,
    )


@router.get(
    "/submissions",
    response_model=HelpdeskSubmissionListResponse,
)
async def get_helpdesk_submissions(
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=50, ge=1, le=200),
    category: Literal["review", "report"] | None = None,
    submission_status: Literal[
        "open",
        "in_progress",
        "resolved",
        "closed",
    ]
    | None = Query(default=None, alias="status"),
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """List helpdesk submissions for administrators."""
    return await list_helpdesk_submissions(
        db,
        page=page,
        per_page=per_page,
        category=category,
        status=submission_status,
    )


@router.patch(
    "/submissions/{submission_id}",
    response_model=HelpdeskSubmissionResponse,
)
async def patch_helpdesk_submission(
    submission_id: UUID,
    payload: HelpdeskSubmissionUpdateRequest,
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Update helpdesk workflow status or an internal admin note."""
    try:
        return await update_helpdesk_submission(db, submission_id, payload)
    except LookupError as exc:
        raise_api_error(
            status.HTTP_404_NOT_FOUND,
            str(exc),
            code="helpdesk_submission_not_found",
        )
