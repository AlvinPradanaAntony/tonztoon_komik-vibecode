"""Bounded ASGI telemetry. Never records bodies, headers, concrete paths or queries."""
from __future__ import annotations

import asyncio
import contextvars
import logging
import math
import re
import time
import uuid
from collections import Counter, deque
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from starlette.routing import compile_path
from app.config import settings
from app.database import engine
from app.admin.tables import buckets, events

request_id_context = contextvars.ContextVar("admin_request_id", default=None)
LIMITS = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1000, 2000, 4000, 8000, 16000, 32000, 64000, 128000, 256000, 1e9]


def utcnow():
    return datetime.now(timezone.utc)


def sanitize(message):
    value = str(message)[:4000]
    value = re.sub(r"https?://\S+", "[url]", value, flags=re.I)
    value = re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[email]", value)
    value = re.sub(r"(?i)(bearer\s+)[^\s,;]+", r"\1[redacted]", value)
    value = re.sub(r"(?i)(password|secret|token|cookie|authorization|api[_-]?key)\s*[:=]\s*[^\s,;]+", r"\1=[redacted]", value)
    value = re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[jwt]", value)
    value = re.sub(r"(?:[A-Za-z]:\\|/home/|/Users/)[^\s\"']+", "[path]", value)
    return value


class Telemetry:
    def __init__(self):
        self.instance = str(uuid.uuid4())
        self.started = time.time()
        self.seconds = {}
        self.requests = deque(maxlen=10000)
        self.logs = deque(maxlen=1000)
        self.pending = deque(maxlen=5000)
        self.in_flight = 0
        self.dropped = 0
        self.last_persisted = None
        self.storage = "unknown"
        self.storage_error = None
        self.sequence = 0
        self.streams = Counter()
        self.resource_changes=deque(maxlen=1000)

    def resource_changed(self,resource,revision=None):
        self.resource_changes.append({"id":str(uuid.uuid4()),"type":"resource_changed","schema_version":1,"resource":resource,"revision":revision,"emitted_at":utcnow().isoformat()})

    def record(self, method, route, status, elapsed, headers_ms, outcome, request_id):
        now = time.time()
        second = int(now)
        key = f"{method} {route}"
        if outcome=="completed":
            bucket = self.seconds.setdefault(second, {})
            if key not in bucket and len(bucket) >= 200:
                key = "OTHER"
            cell = bucket.setdefault(key, {"count": 0, "errors": 0, "histogram": [0] * len(LIMITS)})
            cell["count"] += 1
            cell["errors"] += int(status is not None and status >= 500)
            cell["histogram"][next(i for i, limit in enumerate(LIMITS) if elapsed <= limit)] += 1
        self.sequence += 1
        item = dict(id=f"{self.instance}:{self.sequence}", request_id=request_id,
                    at=utcnow().isoformat(), method=method, route=route, status=status,
                    duration_ms=round(elapsed, 2), headers_ms=round(headers_ms, 2) if headers_ms is not None else None,
                    outcome=outcome, environment=settings.APP_ENV, instance_id=self.instance)
        self.requests.append(item)
        # Count first, then independently sample persisted successes.
        if status is None or status >= 400 or elapsed >= 2000 or self.sequence % 100 == 0:
            self.enqueue("request", item)
        for stamp in list(self.seconds):
            if stamp < second - 900:
                del self.seconds[stamp]
        while self.requests and self.requests[0]["at"] < (utcnow() - timedelta(minutes=5)).isoformat():
            self.requests.popleft()

    def enqueue(self, kind, payload):
        if len(self.pending) == self.pending.maxlen:
            self.dropped += 1
        self.pending.append(dict(id=payload["id"], kind=kind, payload=payload,
                                 at=datetime.fromisoformat(payload["at"]), environment=settings.APP_ENV))

    def log(self, logger, level, message, exception=None, request_id=None):
        item = dict(id=str(uuid.uuid4()), at=utcnow().isoformat(), logger=logger[:120], level=level,
                    message=sanitize(message), exception=exception, request_id=request_id,
                    instance_id=self.instance, environment=settings.APP_ENV)
        self.logs.append(item)
        self.enqueue("runtime", item)

    def snapshot(self, minutes=15):
        now = time.time()
        cells = [v for stamp, rows in self.seconds.items() if stamp >= now - minutes * 60 for v in rows.values()]
        count = sum(c["count"] for c in cells)
        errors = sum(c["errors"] for c in cells)
        hist = [sum(c["histogram"][i] for c in cells) for i in range(len(LIMITS))]
        duration = min(minutes * 60, max(0.001, now - self.started))
        return dict(schema_version=1, snapshot_id=f"{self.instance}:{self.sequence}", instance_id=self.instance,
            environment=settings.APP_ENV, observed_at=utcnow().isoformat(),
            window={"from": datetime.fromtimestamp(now-minutes*60, timezone.utc).isoformat(), "to": utcnow().isoformat()},
            coverage={"state": "partial" if duration < minutes * 60 or self.dropped else "complete",
                      "duration_seconds": round(duration, 2), "telemetry_dropped": self.dropped},
            metrics={"completed": count, "server_errors": errors, "rps": count / duration,
                     "error_rate_percent": errors * 100 / count if count else None,
                     "p95_ms": percentile(hist), "in_flight": self.in_flight},
            storage=self.storage, storage_error=self.storage_error,last_persisted_at=self.last_persisted, latency_method="histogram_upper_bound")

    async def flush(self):
        batch = [self.pending.popleft() for _ in range(min(len(self.pending), 500))]
        rows = self.persisted_minutes()
        try:
            async with asyncio.timeout(8):
                async with engine.begin() as connection:
                    if batch:
                        from app.admin.storage import persist_events
                        self.dropped += await persist_events(connection,batch)
                    if rows:
                        stmt = insert(buckets).values(rows)
                        await connection.execute(stmt.on_conflict_do_update(index_elements=[buckets.c.id], set_={"payload": stmt.excluded.payload}))
            self.last_persisted = utcnow().isoformat()
            self.storage = "available"
            self.storage_error = None
        except Exception as exc:
            self.storage = "unavailable"
            self.storage_error = type(exc).__name__+":"+str(getattr(getattr(exc,"orig",None),"sqlstate",""))
            for item in reversed(batch):
                if len(self.pending) < self.pending.maxlen:
                    self.pending.appendleft(item)
                else:
                    self.dropped += 1

    def persisted_minutes(self):
        now=time.time()
        grouped={}
        for stamp in range(max(int(self.started),int(now)-899),int(now)+1):
            minute=stamp//60*60
            group=grouped.setdefault(minute,{"routes":{},"instance_id":self.instance,"coverage_seconds":0,"observed_at":utcnow().isoformat()})
            group["coverage_seconds"]+=1
            for route,cell in self.seconds.get(stamp,{}).items():
                target=group["routes"].setdefault(route,{"count":0,"errors":0,"histogram":[0]*len(LIMITS)})
                target["count"]+=cell["count"]
                target["errors"]+=cell["errors"]
                target["histogram"]=[a+b for a,b in zip(target["histogram"],cell["histogram"])]
        return [dict(id=f"{self.instance}:{stamp}",at=datetime.fromtimestamp(stamp,timezone.utc),environment=settings.APP_ENV,payload=data) for stamp,data in grouped.items()]

    async def run(self):
        while True:
            started=time.monotonic()
            await self.flush()
            cutoff=(utcnow()-timedelta(minutes=5)).isoformat()
            for buffer in (self.requests,self.logs):
                while buffer and buffer[0]["at"]<cutoff:
                    buffer.popleft()
            await asyncio.sleep(max(0,5-(time.monotonic()-started)))


def percentile(hist):
    total = sum(hist)
    if not total:
        return None
    target, count = math.ceil(total * .95), 0
    for limit, amount in zip(LIMITS, hist):
        count += amount
        if count >= target:
            return limit


telemetry = Telemetry()


class RuntimeHandler(logging.Handler):
    def emit(self, record):
        if record.name.startswith(("sqlalchemy", "httpx", "httpcore", "uvicorn.access")):
            return
        # Arguments often contain URLs, payloads or credentials. Store the template only.
        exception = record.exc_info[0].__name__ if record.exc_info and record.exc_info[0] else None
        telemetry.log(record.name, record.levelname, record.msg, exception, request_id_context.get())


class TelemetryMiddleware:
    def __init__(self, app):
        self.app = app
        self._route_templates = None

    def __getattr__(self,name):
        return getattr(self.app,name)

    def route_template(self, scope):
        route = getattr(scope.get("route"), "path", None)
        if not route:
            return "unmatched"
        if route.startswith("/api/v1/"):
            return route
        # Included routers retain their original local path in recent FastAPI.
        # Only emit registered templates; never construct labels from user paths.
        if self._route_templates is None:
            schema = self.app.openapi() if hasattr(self.app, "openapi") else {}
            self._route_templates = [
                (template, compile_path(template)[0], {method.upper() for method in operations})
                for template, operations in schema.get("paths", {}).items()
                if template.startswith("/api/v1/")
            ]
        for template, pattern, methods in self._route_templates:
            if (template.endswith(route) and scope.get("method") in methods
                    and pattern.fullmatch(scope.get("path", ""))):
                return template
        return "unmatched"

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not settings.ADMIN_CONSOLE_ENABLED:
            return await self.app(scope, receive, send)
        # Client IDs are never trusted; correlation is generated by the server.
        request_id = str(uuid.uuid4())
        token = request_id_context.set(request_id)
        started, headers_ms, status_code, completed, finished_ms = time.perf_counter(), None, None, False, None
        path = scope.get("path", "")
        business = path.startswith("/api/v1/") and not path.startswith(("/api/v1/monitoring", "/api/v1/admin-data", "/api/v1/admin-session"))
        if business:
            telemetry.in_flight += 1

        async def wrapped(message):
            nonlocal status_code, headers_ms, completed, finished_ms
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers_ms = (time.perf_counter()-started)*1000
                message["headers"] = list(message.get("headers", [])) + [(b"x-request-id", request_id.encode())]
            await send(message)
            if message["type"] == "http.response.body" and not message.get("more_body", False):
                completed = True
                finished_ms = (time.perf_counter()-started)*1000

        try:
            await self.app(scope, receive, wrapped)
        finally:
            request_id_context.reset(token)
            if business:
                telemetry.in_flight -= 1
                route = self.route_template(scope)
                telemetry.record(scope.get("method", "GET"), route, status_code,
                    finished_ms if finished_ms is not None else (time.perf_counter()-started)*1000, headers_ms,
                    "completed" if completed else "aborted", request_id)
