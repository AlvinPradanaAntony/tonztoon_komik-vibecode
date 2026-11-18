from fastapi import Depends, HTTPException
from app.api.deps import bearer_scheme
from fastapi.security import HTTPAuthorizationCredentials
from app.config import settings
from app.schemas import AuthenticatedUser

PERMISSIONS = frozenset({
    "monitoring:read", "logs:read", "preview:read", "preview:inspect-urls",
    "data:read", "catalog:write", "helpdesk:manage", "users:manage",
    "users:inspect-library", "audit:read",
})


def permissions_for(user: AuthenticatedUser) -> set[str]:
    if not user.raw_claims:
        return set()
    configured = {v.strip() for v in settings.ADMIN_USER_IDS.split(",") if v.strip()}
    if str(user.user_id) in configured:
        return set(PERMISSIONS)
    metadata = (user.raw_claims or {}).get("app_metadata") or {}
    if any(str(metadata.get(k, "")).lower() in {"admin", "owner", "superadmin"}
           for k in ("role", "account_role", "admin_role")):
        return set(PERMISSIONS)
    values = metadata.get("admin_permissions", [])
    return set(v for v in values if isinstance(v, str) and v in PERMISSIONS) if isinstance(values, list) else set()


async def get_admin_auth_user(credentials:HTTPAuthorizationCredentials|None=Depends(bearer_scheme)):
    if credentials is None or credentials.scheme.lower()!="bearer":
        raise HTTPException(401,"Bearer token required.")
    from app.services.auth_service import validate_supabase_jwt,AuthValidationError
    try:
        return await validate_supabase_jwt(credentials.credentials)
    except AuthValidationError:
        raise HTTPException(401,"Sesi tidak valid.")


def require(permission: str):
    def check(user: AuthenticatedUser = Depends(get_admin_auth_user)):
        if permission not in permissions_for(user):
            raise HTTPException(403, "Izin untuk tindakan ini tidak tersedia.")
        return user
    return check
