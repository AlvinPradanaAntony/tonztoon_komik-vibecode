"""Read-only operational summary; excludes log payloads, identities and config."""
import asyncio
import time
from sqlalchemy import text
from app.database import engine


async def main():
    async with engine.connect() as conn:
        start=time.perf_counter()
        await conn.execute(text("SELECT 1"))
        print("database_select_1_ms:",round((time.perf_counter()-start)*1000))
        for name in ("events","buckets","probes","incidents","event_quotas"):
            value=await conn.scalar(text(f"SELECT count(*) FROM monitoring.{name}"))
            print(name,"rows:",value)
        for name in ("events","buckets","probes"):
            value=await conn.scalar(text(f"SELECT max(at) FROM monitoring.{name}"))
            print(name,"last_at:",value)
    await engine.dispose()


async def check_storage():
    from app.admin.storage import persist_events
    from app.admin.telemetry import utcnow
    from app.config import settings
    import uuid
    try:
        async with engine.connect() as conn:
            transaction=await conn.begin()
            now=utcnow();identifier=str(uuid.uuid4())
            await persist_events(conn,[{"id":identifier,"kind":"runtime","at":now,"environment":settings.APP_ENV,
                "payload":{"id":identifier,"at":now.isoformat(),"level":"INFO","message":"Rollback-isolated storage check"}}])
            await transaction.rollback()
        print("storage_transaction: passed (rolled back)")
    except Exception as exc:
        original=getattr(exc,"orig",None)
        print("storage_transaction_error:",type(exc).__name__,getattr(original,"sqlstate",None),str(original).splitlines()[0] if original else "")
    await engine.dispose()


if __name__=="__main__":
    asyncio.run(main())
    asyncio.run(check_storage())
