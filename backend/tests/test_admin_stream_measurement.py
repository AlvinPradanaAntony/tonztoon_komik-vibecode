import asyncio
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from fastapi import FastAPI,Depends,APIRouter
import httpx
from app.admin.telemetry import Telemetry,TelemetryMiddleware
from app.admin.security import require
from app.config import settings


class AdminAsgiTests(unittest.IsolatedAsyncioTestCase):
    async def test_current_chart_uses_same_instance_and_window_as_snapshot(self):
        from app.admin.monitoring import timeseries
        store=Telemetry()
        store.record("GET","/api/v1/images/proxy",200,5,1,"completed","one")
        store.record("GET","/api/v1/images/proxy",500,10,1,"completed","two")
        with patch("app.admin.monitoring.telemetry",store):
            chart=await timeseries(15,False)
        self.assertEqual(chart["instance_id"],store.instance)
        self.assertEqual(sum(row["completed"] for row in chart["items"]),store.snapshot()["metrics"]["completed"])
        self.assertEqual(sum(row["errors"] for row in chart["items"]),1)

    async def test_nested_router_records_full_registered_template(self):
        app, parent, child, store = FastAPI(), APIRouter(), APIRouter(), Telemetry()
        @child.get("/comics/{slug}")
        async def comic(slug: str):return {"ok": True}
        parent.include_router(child, prefix="/source")
        app.include_router(parent, prefix="/api/v1")
        with patch.object(settings,"ADMIN_CONSOLE_ENABLED",True),patch("app.admin.telemetry.telemetry",store):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=TelemetryMiddleware(app)),base_url="http://test") as client:
                response=await client.get("/api/v1/source/comics/private-slug?token=synthetic-secret")
                missing=await client.get("/api/v1/not-a-registered-route")
        self.assertEqual(response.status_code,200)
        self.assertEqual(missing.status_code,404)
        self.assertEqual(store.requests[0]["route"],"/api/v1/source/comics/{slug}")
        self.assertEqual(store.requests[1]["route"],"unmatched")
        self.assertNotIn("private-slug",str(store.requests))
        self.assertNotIn("synthetic-secret",str(store.requests))

    async def test_duration_ends_at_final_body_before_background_work(self):
        store=Telemetry()
        async def application(scope,receive,send):
            scope["route"]=SimpleNamespace(path="/api/v1/comics/{slug}")
            await send({"type":"http.response.start","status":200,"headers":[]})
            await send({"type":"http.response.body","body":b"part","more_body":True})
            await asyncio.sleep(.01)
            await send({"type":"http.response.body","body":b"end","more_body":False})
            await asyncio.sleep(.08)
        sent=[]
        async def send(value):sent.append(value)
        with patch.object(settings,"ADMIN_CONSOLE_ENABLED",True),patch("app.admin.telemetry.telemetry",store):
            await TelemetryMiddleware(application)({"type":"http","method":"GET","path":"/api/v1/comics/private-slug","query_string":b"token=synthetic-secret"},None,send)
        self.assertEqual(store.snapshot()["metrics"]["completed"],1)
        self.assertLess(store.requests[0]["duration_ms"],70)
        self.assertNotIn("synthetic-secret",str(store.requests))
        self.assertNotIn("private-slug",str(store.requests))
        self.assertTrue(any(name==b"x-request-id" for name,_ in sent[0]["headers"]))

    async def test_aborted_body_does_not_become_completed_request(self):
        store=Telemetry()
        store.record("GET","/api/v1/images/proxy",200,5,1,"aborted","test")
        self.assertEqual(store.snapshot()["metrics"]["completed"],0)
        self.assertEqual(store.requests[0]["outcome"],"aborted")

    async def test_dev_identity_header_cannot_grant_admin(self):
        app=FastAPI()
        @app.get("/protected",dependencies=[Depends(require("monitoring:read"))])
        async def protected():return {"ok":True}
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url="http://test") as client:
            response=await client.get("/protected",headers={"X-User-Id":settings.ADMIN_USER_IDS.split(",")[0]})
        self.assertEqual(response.status_code,401)
