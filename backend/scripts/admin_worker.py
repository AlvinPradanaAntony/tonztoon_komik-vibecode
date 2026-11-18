"""Independent probe/evaluator/retention worker. One worker per environment.

Run separately from uvicorn: python -m scripts.admin_worker.
It deliberately stays alive when the API process stops.
"""
import asyncio
import os
import time
import uuid
from datetime import timedelta
import httpx
from sqlalchemy import select, delete, update, func, text
from sqlalchemy.dialects.postgresql import insert
from app.admin.tables import probes, incidents, events, buckets, audit, operations, outbox, sessions, quotas,security_events
from app.admin.telemetry import utcnow, LIMITS, percentile
from app.database import engine
from app.config import settings


async def evaluate(connection, rule, firing, value, now, immediate=False):
    current = (await connection.execute(select(incidents).where(
        incidents.c.rule==rule, incidents.c.environment==settings.APP_ENV,
        incidents.c.state!="resolved").order_by(incidents.c.started_at.desc()).limit(1))).mappings().first()
    if firing is None:
        if current:
            await connection.execute(update(incidents).where(incidents.c.id==current["id"]).values(healthy_since=None,condition_since=None))
        return
    if firing and not current:
        await connection.execute(insert(incidents).values(id=str(uuid.uuid4()), rule=rule,
            environment=settings.APP_ENV, state="firing" if immediate else "pending", started_at=now,
            updated_at=now, value=value,condition_since=now))
    elif current:
        if firing:
            since=current["condition_since"] or now
            state = "firing" if current["state"]=="firing" or immediate or (now-since).total_seconds()>=60 else "pending"
            await connection.execute(update(incidents).where(incidents.c.id==current["id"]).values(state=state,value=value,healthy_since=None,condition_since=since,updated_at=now))
        elif immediate or current["state"]=="pending" or (current["healthy_since"] and (now-current["healthy_since"]).total_seconds()>=60):
            await connection.execute(update(incidents).where(incidents.c.id==current["id"]).values(state="resolved", resolved_at=now, updated_at=now))
        elif not current["healthy_since"]:
            await connection.execute(update(incidents).where(incidents.c.id==current["id"]).values(healthy_since=now,condition_since=None,updated_at=now))


async def tick(client,cleanup=False):
    started, success = time.perf_counter(), False
    try:
        response = await client.get(os.environ.get("ADMIN_PROBE_URL", "http://127.0.0.1:8000/"))
        success = response.status_code==200 and response.json().get("status")=="running"
    except Exception:
        pass
    now = utcnow()
    async with engine.begin() as conn:
        await conn.execute(insert(probes).values(at=now, environment=settings.APP_ENV, success=success,
                                               duration_ms=(time.perf_counter()-started)*1000))
        previous = (await conn.execute(select(probes).where(probes.c.environment==settings.APP_ENV)
                    .order_by(probes.c.at.desc()).limit(2))).mappings().all()
        down = all(not p["success"] for p in previous) if len(previous)==2 else None
        if len(previous)==2 and all(p["success"] for p in previous):
            down = False
        elif not down:
            down = None
        await evaluate(conn, "liveness", down, int(success), now, True)
        data = (await conn.execute(select(buckets).where(buckets.c.environment==settings.APP_ENV,
                       buckets.c.at>=now-timedelta(minutes=5)))).mappings().all()
        from datetime import datetime
        fresh = bool(data and (now-max(datetime.fromisoformat(x["payload"].get("observed_at",x["at"].isoformat())) for x in data)).total_seconds()<30)
        count = sum(c["count"] for r in data for c in r["payload"]["routes"].values())
        errors = sum(c["errors"] for r in data for c in r["payload"]["routes"].values())
        histogram = [sum(c["histogram"][i] for r in data for c in r["payload"]["routes"].values()) for i in range(len(LIMITS))]
        rate = errors*100/count if count else None
        p95 = percentile(histogram)
        await evaluate(conn, "server_errors", rate>5 if fresh and count>=100 else None, rate, now)
        await evaluate(conn, "latency", p95>2000 if fresh and count>=100 else None, p95, now)
        for table, column, days in (((events,events.c.at,1),(buckets,buckets.c.at,7),(probes,probes.c.at,7),
                                   (incidents,incidents.c.started_at,30),(audit,audit.c.at,90),
                                   (operations,operations.c.created_at,1),(outbox,outbox.c.at,7),(security_events,security_events.c.at,90)) if cleanup else ()):
            await conn.execute(delete(table).where(column<now-timedelta(days=days)))
        if cleanup:
            await conn.execute(delete(sessions).where(sessions.c.expires_at<now))
            await conn.execute(delete(quotas).where(quotas.c.day<(now-timedelta(days=2)).date()))


async def main():
    async with engine.connect() as lock:
        acquired = await lock.scalar(text("SELECT pg_try_advisory_xact_lock(hashtextextended(:key,0))"),{"key":"tonztoon-monitoring-worker:"+settings.APP_ENV})
        if not acquired:
            raise RuntimeError("Monitoring worker already running.")
        async with httpx.AsyncClient(timeout=2) as client:
            last_cleanup=0
            while True:
                started=time.monotonic()
                # Keep the owning transaction alive on transaction-pooling hosts;
                # a lost lock connection stops this worker instead of duplicating it.
                await lock.execute(text("SELECT 1"))
                try:
                    cleanup=started-last_cleanup>=60
                    await tick(client,cleanup=cleanup)
                    if cleanup:last_cleanup=started
                except Exception as exc:
                    print("Monitoring worker failed:", type(exc).__name__,getattr(getattr(exc,"orig",None),"sqlstate",None), flush=True)
                await asyncio.sleep(max(0,5-(time.monotonic()-started)))


if __name__ == "__main__":
    asyncio.run(main())
