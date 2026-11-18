import uuid
import hmac
from fastapi import HTTPException
from sqlalchemy import insert, update
from app.admin.data import idempotency, fingerprint, require_match
from app.admin.tables import operations, audit
from app.admin.telemetry import request_id_context
from app.admin.security import permissions_for
from app.config import settings


def account_etag(user):
    return fingerprint(user.model_dump(mode="json", exclude={"etag","app_metadata","user_metadata","relation_counts","relation_total"}))


def guard_account(raw):
    metadata=raw.get("app_metadata") or {}
    configured={v.strip() for v in settings.ADMIN_USER_IDS.split(",") if v.strip()}
    if str(raw["id"]) in configured or metadata.get("admin_permissions") or any(
        str(metadata.get(k,"")).lower() in {"admin","owner","superadmin"} for k in ("role","account_role","admin_role")):
        raise HTTPException(403,"Akun berizin khusus dikelola melalui provisioning tepercaya.")


async def mutate(db,request,actor,payload,service,target=None):
    from app.services.account_manager_service import get_auth_user, build_account_user
    signature_payload=payload.model_dump(mode="json")
    if signature_payload.get("password"):
        if not settings.SUPABASE_SERVICE_ROLE_KEY:
            raise HTTPException(503,"Layanan akun belum dikonfigurasi.")
        signature_payload["password"]=hmac.digest(settings.SUPABASE_SERVICE_ROLE_KEY.encode(),
            ("admin-idempotency:"+signature_payload["password"]).encode(),"sha256").hex()
    operation,previous=await idempotency(db,request,actor,signature_payload)
    if previous is not None:
        return previous
    if target:
        raw=await get_auth_user(target)
        guard_account(raw)
        user=await build_account_user(db,raw)
        require_match(request,{"etag":account_etag(user)})
    # Auth is external. Persist the operation before calling it so uncertainty is visible.
    await db.commit()
    try:
        user=await service()
    except Exception:
        await db.rollback()
        await db.execute(update(operations).where(operations.c.key==operation).values(status="reconciliation_needed"))
        await db.commit()
        raise
    result=user.model_dump(mode="json",exclude={"app_metadata","user_metadata","phone"})
    result["etag"]=account_etag(user)
    await db.execute(update(operations).where(operations.c.key==operation).values(response=result,status="succeeded"))
    await db.execute(insert(audit).values(id=str(uuid.uuid4()),actor=str(actor.user_id),permission="users:manage",
        resource=f"accounts/{user.id}",action="update" if target else "create",fields={k:{"changed":True} for k in payload.model_fields_set if k!="password"},
        request_id=request_id_context.get(),operation_id=operation))
    await db.commit()
    return result
