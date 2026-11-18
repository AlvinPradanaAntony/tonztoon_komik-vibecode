from fastapi import APIRouter, Depends, HTTPException
from app.api.deps import get_current_auth_user
from app.config import settings
from app.admin.security import permissions_for,get_admin_auth_user
from app.admin.monitoring import router as monitoring_router


def enabled():
    if not settings.ADMIN_CONSOLE_ENABLED:
        raise HTTPException(404, "Admin console belum diaktifkan.")


router = APIRouter(dependencies=[Depends(enabled)])
router.include_router(monitoring_router, prefix="/monitoring", tags=["Monitoring"])
from app.admin.data import router as data_router
router.include_router(data_router, prefix="/admin-data", tags=["Admin Data"])


@router.get("/admin-session", tags=["Admin Session"])
async def session(user=Depends(get_admin_auth_user)):
    permissions = permissions_for(user)
    if not permissions:
        raise HTTPException(403, "Akun ini tidak memiliki akses admin.")
    return {"user_id": str(user.user_id), "permissions": sorted(permissions), "environment": settings.APP_ENV}
