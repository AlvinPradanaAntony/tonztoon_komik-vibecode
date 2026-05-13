"""
Admin account manager API.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_auth_user
from app.api.errors import raise_api_error
from app.config import settings
from app.database import get_db
from app.models import Profile
from app.schemas import (
    AccountDeletePreviewResponse,
    AccountDeleteResponse,
    AccountManagerCreateRequest,
    AccountManagerListResponse,
    AccountManagerUpdateRequest,
    AccountManagerUser,
    AccountRelationPreview,
    AuthenticatedUser,
)
from app.services.account_manager_service import (
    AccountManagerConfigurationError,
    AccountManagerRequestError,
    build_account_user,
    create_account,
    delete_account_clean,
    get_auth_user,
    get_relation_counts,
    get_relation_preview,
    list_accounts,
    update_account,
)

router = APIRouter()


def _csv_settings(value: str) -> set[str]:
    return {item.strip() for item in value.split(",") if item.strip()}


def _metadata_has_admin_role(metadata: dict | None) -> bool:
    metadata = metadata or {}
    role_values = {
        metadata.get("role"),
        metadata.get("account_role"),
        metadata.get("admin_role"),
    }
    return any(str(value).lower() in {"admin", "owner", "superadmin"} for value in role_values if value)


def require_account_manager_admin(
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
) -> AuthenticatedUser:
    """Allow only configured/admin Supabase users to use account manager."""
    allowed_user_ids = _csv_settings(settings.ADMIN_USER_IDS)
    if str(auth_user.user_id) in allowed_user_ids:
        return auth_user

    claims = auth_user.raw_claims or {}
    if _metadata_has_admin_role(claims.get("app_metadata")):
        return auth_user
    if _metadata_has_admin_role(claims.get("user_metadata")):
        return auth_user

    raise_api_error(
        status.HTTP_403_FORBIDDEN,
        "Akun ini tidak memiliki akses account manager.",
        code="account_manager_forbidden",
    )


def _raise_service_error(exc: AccountManagerRequestError) -> None:
    raise_api_error(exc.status_code, exc.message, code="supabase_admin_request_failed")


@router.get("/accounts", response_model=AccountManagerListResponse)
async def get_accounts(
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=100, ge=1, le=200),
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """List Supabase Auth users enriched dengan profile dan jumlah relasi app."""
    try:
        return await list_accounts(db, page=page, per_page=per_page)
    except AccountManagerConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AccountManagerRequestError as exc:
        _raise_service_error(exc)


@router.post(
    "/accounts",
    response_model=AccountManagerUser,
    status_code=status.HTTP_201_CREATED,
)
async def post_account(
    payload: AccountManagerCreateRequest,
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Create Supabase Auth user dan profile aplikasi default."""
    try:
        return await create_account(db, payload)
    except ValueError as exc:
        raise_api_error(status.HTTP_409_CONFLICT, str(exc))
    except AccountManagerConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AccountManagerRequestError as exc:
        _raise_service_error(exc)


@router.patch("/accounts/{user_id}", response_model=AccountManagerUser)
async def patch_account(
    user_id: UUID,
    payload: AccountManagerUpdateRequest,
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Update email/password/metadata Supabase Auth dan profile aplikasi."""
    try:
        return await update_account(db, user_id, payload)
    except ValueError as exc:
        raise_api_error(status.HTTP_409_CONFLICT, str(exc))
    except AccountManagerConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AccountManagerRequestError as exc:
        _raise_service_error(exc)


@router.get("/accounts/{user_id}/relations", response_model=AccountRelationPreview)
async def get_account_relations(
    user_id: UUID,
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Preview data aplikasi yang berelasi dengan user ID."""
    return await get_relation_preview(db, user_id)


@router.get("/accounts/{user_id}/delete-preview", response_model=AccountDeletePreviewResponse)
async def get_account_delete_preview(
    user_id: UUID,
    _: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Preview ringkasan relasi sebelum akun dihapus bersih."""
    try:
        raw_user = await get_auth_user(user_id)
    except AccountManagerConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AccountManagerRequestError as exc:
        _raise_service_error(exc)

    profile_result = await db.execute(select(Profile).where(Profile.id == user_id))
    counts = await get_relation_counts(db, user_id)
    user = await build_account_user(
        db,
        raw_user,
        profile=profile_result.scalars().first(),
        relation_counts=counts,
    )
    return AccountDeletePreviewResponse(
        user=user,
        relation_counts=counts,
        relation_total=counts.total,
    )


@router.delete("/accounts/{user_id}", response_model=AccountDeleteResponse)
async def delete_account(
    user_id: UUID,
    auth_user: AuthenticatedUser = Depends(require_account_manager_admin),
    db: AsyncSession = Depends(get_db),
):
    """Delete Supabase Auth user dan bersihkan semua data public.* terkait."""
    if user_id == auth_user.user_id:
        raise_api_error(
            status.HTTP_400_BAD_REQUEST,
            "Tidak bisa menghapus akun admin yang sedang dipakai untuk login.",
            code="account_manager_self_delete_blocked",
        )

    try:
        return await delete_account_clean(db, user_id)
    except AccountManagerConfigurationError as exc:
        raise_api_error(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
    except AccountManagerRequestError as exc:
        _raise_service_error(exc)
    except Exception as exc:
        raise_api_error(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Gagal menghapus akun. Cek log backend untuk detail.",
            code="account_manager_delete_failed",
            extra={"detail": str(exc)} if settings.APP_DEBUG else None,
        )
