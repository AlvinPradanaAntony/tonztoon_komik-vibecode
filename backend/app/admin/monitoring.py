from __future__ import annotations
import asyncio
import hashlib
import json
import time
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import select, text
from app.admin.security import permissions_for, require
from app.admin.tables import events, buckets, probes, incidents
from app.admin.telemetry import LIMITS, percentile, telemetry, utcnow
from app.database import engine
from app.config import settings

router = APIRouter()


def endpoint_id(method, route):
    return hashlib.sha256(f"{method} {route}".encode()).hexdigest()[:20]


@router.get("/capabilities")
async def capabilities(user=Depends(require("monitoring:read"))):
    return dict(schema_version=1, permissions=sorted(permissions_for(user)), environment=settings.APP_ENV,
                worker_mode="single-api-worker", retention_days=7, sampling_success=.01,
                features={"runtime_logs": True, "stream": True, "history": True})


@router.get("/snapshot",dependencies=[Depends(require("monitoring:read"))])
async def snapshot(window: int = Query(15, ge=1, le=15)):
    return telemetry.snapshot(window)


@router.get("/timeseries",dependencies=[Depends(require("monitoring:read"))])
async def timeseries(window: int = Query(15, ge=1, le=10080), history: bool = False):
    start = utcnow() - timedelta(minutes=window)
    if not history and window <= 15:
        by_minute = {}
        for stamp, cells in list(telemetry.seconds.items()):
            if stamp < start.timestamp():
                continue
            minute = stamp // 60 * 60
            cell = by_minute.setdefault(minute, {"completed": 0, "errors": 0, "histogram": [0]*len(LIMITS)})
            for data in cells.values():
                cell["completed"] += data["count"]
                cell["errors"] += data["errors"]
                cell["histogram"] = [a+b for a,b in zip(cell["histogram"], data["histogram"])]
        return {"items": [{"at": stamp, **cell, "p95_ms": percentile(cell["histogram"])}
                          for stamp, cell in sorted(by_minute.items())], "interval_seconds": 60,
                "instance_id": telemetry.instance, "coverage": telemetry.snapshot(window)["coverage"]["state"],
                "observed_at": utcnow().isoformat()}
    async with engine.connect() as conn:
        rows = (await conn.execute(select(buckets).where(buckets.c.at >= start,
                  buckets.c.environment == settings.APP_ENV).order_by(buckets.c.at))).mappings().all()
    merged = {r["id"]: (int(r["at"].timestamp()), r["payload"]["routes"]) for r in rows}
    for row in telemetry.persisted_minutes():
        stamp=int(row["at"].timestamp())
        if stamp >= int(start.timestamp())//60*60:
            merged[row["id"]] = (stamp, row["payload"]["routes"])
    by_minute = {}
    for stamp, cells in merged.values():
        minute = stamp // 60 * 60
        cell = by_minute.setdefault(minute, {"completed": 0, "errors": 0, "histogram": [0]*len(LIMITS)})
        for data in cells.values():
            cell["completed"] += data["count"]
            cell["errors"] += data["errors"]
            cell["histogram"] = [a+b for a,b in zip(cell["histogram"], data["histogram"])]
    return {"items": [{"at": stamp, **cell, "p95_ms": percentile(cell["histogram"])}
                      for stamp, cell in sorted(by_minute.items())], "interval_seconds": 60,
            "coverage": "partial", "observed_at": utcnow().isoformat()}


@router.get("/endpoints",dependencies=[Depends(require("monitoring:read"))])
async def endpoints(request: Request, q: str = Query("", max_length=150), method: str = "", window: int = Query(15, ge=1, le=15)):
    result = []
    for path,operations in request.app.openapi().get("paths",{}).items():
        if not path.startswith("/api/v1/") or path.startswith(("/api/v1/monitoring", "/api/v1/admin")):
            continue
        for operation,metadata in operations.items():
            verb=operation.upper()
            if verb not in {"GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"}:
                continue
            if (method and method != verb) or q.lower() not in path.lower():
                continue
            cells = [rows[f"{verb} {path}"] for stamp, rows in telemetry.seconds.items()
                     if stamp >= time.time()-window*60 and f"{verb} {path}" in rows]
            count = sum(c["count"] for c in cells)
            errors = sum(c["errors"] for c in cells)
            histogram = [sum(c["histogram"][i] for c in cells) for i in range(len(LIMITS))]
            result.append(dict(id=endpoint_id(verb, path), method=verb, route=path, count=count,
                               server_errors=errors, p95_ms=percentile(histogram), tags=metadata.get("tags", [])))
    return {"items": sorted(result, key=lambda r: (-r["count"], r["route"], r["method"]))}


@router.get("/endpoints/{identifier}",dependencies=[Depends(require("monitoring:read"))])
async def endpoint(identifier: str, request: Request):
    values = await endpoints(request, "", "", 15)
    item = next((v for v in values["items"] if v["id"] == identifier), None)
    if not item:
        raise HTTPException(404, "Endpoint tidak ditemukan.")
    return item


async def event_list(kind, cursor, limit, q, level=None,endpoint="",method="",status_code=None,min_duration=0):
    query = select(events).where(events.c.kind == kind, events.c.environment == settings.APP_ENV)
    if cursor:
        try:
            from datetime import datetime
            stamp, identifier = cursor.split("|", 1)
            at = datetime.fromisoformat(stamp)
        except (ValueError, TypeError):
            raise HTTPException(422, "Cursor tidak valid.")
        from sqlalchemy import or_, and_
        query = query.where(or_(events.c.at < at, and_(events.c.at == at, events.c.id < identifier)))
    if q:
        query = query.where(events.c.payload["request_id"].astext == q)
    if level:
        query = query.where(events.c.payload["level"].astext == level)
    if endpoint:
        query=query.where(events.c.payload["route"].astext==endpoint)
    if method:
        query=query.where(events.c.payload["method"].astext==method)
    if status_code:
        from sqlalchemy import Integer
        query=query.where(events.c.payload["status"].astext.cast(Integer)==status_code)
    if min_duration:
        from sqlalchemy import Float
        query=query.where(events.c.payload["duration_ms"].astext.cast(Float)>=min_duration)
    async with engine.connect() as conn:
        rows = (await conn.execute(query.order_by(events.c.at.desc(), events.c.id.desc()).limit(limit+1))).mappings().all()
    items = [r["payload"] for r in rows[:limit]]
    if not cursor:
        live = telemetry.requests if kind == "request" else telemetry.logs
        live = [r for r in live if (not q or r.get("request_id") == q) and (not level or r.get("level") == level)
            and (not endpoint or r.get("route")==endpoint) and (not method or r.get("method")==method)
            and (not status_code or r.get("status")==status_code) and (not min_duration or r.get("duration_ms",0)>=min_duration)]
        items = sorted({r["id"]: r for r in [*items, *live]}.values(), key=lambda r: (r["at"],r["id"]), reverse=True)[:limit]
    last = items[-1] if items else None
    return dict(items=items, next_cursor=f'{last["at"]}|{last["id"]}' if last and (len(rows)>limit or len(items)==limit) else None,
                retention_hours=24, sampling_success=.01 if kind == "request" else None,
                observed_at=utcnow().isoformat(), storage=telemetry.storage, dropped=telemetry.dropped)


@router.get("/requests",dependencies=[Depends(require("monitoring:read"))])
async def requests(cursor: str | None = None, limit: int = Query(50, ge=1, le=100), request_id: str = Query("", max_length=100),
                   endpoint:str=Query("",max_length=250),method:str=Query("",max_length=10),status_code:int|None=Query(None,ge=100,le=599),min_duration:float=Query(0,ge=0,le=3600000)):
    return await event_list("request", cursor, limit, request_id,endpoint=endpoint,method=method,status_code=status_code,min_duration=min_duration)


@router.get("/runtime-logs")
async def runtime_logs(cursor: str | None = None, limit: int = Query(50, ge=1, le=100),
                       request_id: str = Query("", max_length=100), level: str | None = None,
                       _=Depends(require("logs:read"))):
    if level and level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
        raise HTTPException(422, "Level log tidak valid.")
    return await event_list("runtime", cursor, limit, request_id, level)


@router.get("/requests/{identifier}",dependencies=[Depends(require("monitoring:read"))])
async def request_detail(identifier: str):
    return await detail("request", identifier)


@router.get("/runtime-logs/{identifier}")
async def log_detail(identifier: str, _=Depends(require("logs:read"))):
    return await detail("runtime", identifier)


async def detail(kind, identifier):
    live = telemetry.requests if kind == "request" else telemetry.logs
    item = next((x for x in live if x["id"] == identifier), None)
    if not item:
        async with engine.connect() as conn:
            item = await conn.scalar(select(events.c.payload).where(events.c.kind==kind, events.c.id==identifier,
                                                                     events.c.environment==settings.APP_ENV))
    if item is None:
        raise HTTPException(404, "Observasi tidak tersedia; mungkin tersampel atau telah melewati retensi.")
    return item


_db_health = {"at": 0, "state": "unknown"}


@router.get("/health",dependencies=[Depends(require("monitoring:read"))])
async def health():
    if time.time()-_db_health["at"] > 10:
        try:
            async with asyncio.timeout(2):
                async with engine.connect() as conn:
                    await conn.execute(text("SELECT 1"))
            _db_health["state"] = "available"
        except Exception:
            _db_health["state"] = "unavailable"
        _db_health["at"] = time.time()
    async with engine.connect() as conn:
        values = (await conn.execute(select(probes).where(probes.c.environment==settings.APP_ENV,
                                    probes.c.at >= utcnow()-timedelta(minutes=15))
                                    .order_by(probes.c.at.desc()).limit(180))).mappings().all()
    recent = values[:2]
    fresh = bool(recent and (utcnow()-recent[0]["at"]).total_seconds() < 15)
    state = "unknown" if not fresh or len(recent)<2 else (
        "available" if all(r["success"] for r in recent) else "unavailable" if all(not r["success"] for r in recent) else "pending")
    return dict(api=state, database=_db_health["state"], telemetry=telemetry.storage,
                probe_coverage=min(1, len(values)/180), availability_percent=sum(r["success"] for r in values)*100/len(values) if values else None,
                latest_probe_at=recent[0]["at"] if recent else None,
                dependencies={"Supabase Auth": "Belum dipantau", "Storage": "Belum dipantau", "Upstream": "Belum dipantau"},
                observed_at=utcnow().isoformat())


@router.get("/alerts",dependencies=[Depends(require("monitoring:read"))])
async def alerts():
    async with engine.connect() as conn:
        rows = (await conn.execute(select(incidents).where(incidents.c.environment==settings.APP_ENV)
                                  .order_by(incidents.c.started_at.desc()).limit(100))).mappings().all()
    return {"items": [dict(r) for r in rows], "observed_at": utcnow().isoformat()}


@router.get("/stream")
async def stream(request: Request, user=Depends(require("monitoring:read"))):
    identity = str(user.user_id)
    if telemetry.streams[identity] >= 2 or sum(telemetry.streams.values()) >= 20:
        raise HTTPException(429, "Batas stream tercapai.")

    async def generate():
        telemetry.streams[identity] += 1
        previous = request.headers.get("last-event-id")
        last_auth = 0
        last_observation = None
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        try:
            # Snapshot replacement is idempotent; reset explicitly marks replay gaps.
            if previous:
                yield 'event: reset\ndata: {"reason":"snapshot_resync","schema_version":1}\n\n'
            while not await request.is_disconnected():
                if time.time()-last_auth >= 30:
                    from app.services.auth_service import validate_supabase_jwt
                    try:
                        current = await validate_supabase_jwt(token)
                        if "monitoring:read" not in permissions_for(current):
                            break
                    except Exception:
                        break
                    last_auth = time.time()
                data = telemetry.snapshot()
                yield f'id: {data["snapshot_id"]}\nevent: snapshot\ndata: {json.dumps(data)}\n\n'
                observations=list(telemetry.requests)
                if last_observation:
                    position=next((i for i,item in enumerate(observations) if item["id"]==last_observation),None)
                    observations=observations[position+1:] if position is not None else observations[-100:]
                else:
                    observations=observations[-100:]
                if observations:
                    last_observation=observations[-1]["id"]
                    yield f'event: request_batch\ndata: {json.dumps({"schema_version":1,"items":observations,"observed_at":utcnow().isoformat()})}\n\n'
                await asyncio.sleep(1)
        finally:
            telemetry.streams[identity] -= 1
    return StreamingResponse(generate(), media_type="text/event-stream", headers={"Cache-Control":"private, no-store", "X-Accel-Buffering":"no"})
