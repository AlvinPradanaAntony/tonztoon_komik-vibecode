"""
Dependency helpers untuk endpoint user-scoped.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import Header, HTTPException, status, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings
from app.schemas import AuthenticatedUser
from app.services.auth_service import AuthValidationError, validate_supabase_jwt

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_auth_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    x_user_id: UUID | None = Header(default=None, alias="X-User-Id"),
) -> AuthenticatedUser:
    """
    Resolve authenticated user dari Supabase bearer token.

    Fallback `X-User-Id` tetap didukung saat development agar local testing
    backend lama tidak patah mendadak.
    """
    if credentials and credentials.scheme.lower() == "bearer":
        try:
            return await validate_supabase_jwt(credentials.credentials)
        except AuthValidationError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=str(exc),
            ) from exc

    if settings.ALLOW_DEV_USER_HEADER and x_user_id is not None:
        return AuthenticatedUser(user_id=x_user_id)

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Bearer token required.",
    )


async def get_current_user_id(
    auth_user: AuthenticatedUser = Depends(get_current_auth_user),
) -> UUID:
    """
    Shortcut dependency untuk endpoint yang hanya butuh user_id.
    """
    return auth_user.user_id
