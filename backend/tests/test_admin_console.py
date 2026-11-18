import asyncio
import os
import unittest
import uuid
from unittest.mock import AsyncMock

from app.admin.security import permissions_for
from app.admin.telemetry import Telemetry, TelemetryMiddleware, sanitize
from app.schemas import AuthenticatedUser
from app.config import settings


class AdminSecurityTests(unittest.TestCase):
    def test_editable_metadata_cannot_grant_access(self):
        user=AuthenticatedUser(user_id=uuid.uuid4(),raw_claims={"user_metadata":{"role":"superadmin","admin_permissions":["logs:read"]}})
        self.assertEqual(permissions_for(user),set())

    def test_trusted_permissions_are_separate(self):
        user=AuthenticatedUser(user_id=uuid.uuid4(),raw_claims={"app_metadata":{"admin_permissions":["preview:read","invented"]}})
        self.assertEqual(permissions_for(user),{"preview:read"})

    def test_redaction(self):
        result=sanitize("token=synthetic-secret password=test-password email=user@example.com https://cdn.example.com/a?token=abc Bearer test-token")
        for secret in ("synthetic-secret","test-password","user@example.com","token=abc","test-token"):
            self.assertNotIn(secret,result)

    def test_metrics_count_before_sampling(self):
        store=Telemetry()
        for _ in range(100):
            store.record("GET","/api/v1/comics",200,10,2,"completed",str(uuid.uuid4()))
        for _ in range(6):
            store.record("GET","/api/v1/comics",500,3000,2,"completed",str(uuid.uuid4()))
        self.assertEqual(store.snapshot()["metrics"]["completed"],106)
        self.assertEqual(store.snapshot()["metrics"]["server_errors"],6)
        self.assertEqual(len(store.pending),7)


@unittest.skipUnless(os.environ.get("ADMIN_INTEGRATION_TESTS")=="1","Set ADMIN_INTEGRATION_TESTS=1 for rollback-isolated database integration")
class AdminDatabaseTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        import httpx
        from sqlalchemy.ext.asyncio import AsyncSession
        from app.database import engine,get_db
        from app.api.deps import get_current_auth_user
        from app.admin.security import get_admin_auth_user
        from app.main import app
        self.engine=engine
        self.previous_enabled=settings.ADMIN_CONSOLE_ENABLED
        settings.ADMIN_CONSOLE_ENABLED=True
        self.connection=await engine.connect()
        self.transaction=await self.connection.begin()
        self.session=AsyncSession(bind=self.connection,expire_on_commit=False,join_transaction_mode="create_savepoint")
        async def db():
            yield self.session
        async def user():
            return AuthenticatedUser(user_id=uuid.uuid4(),raw_claims={"app_metadata":{"role":"admin"}})
        self.app=app
        app.dependency_overrides[get_db]=db
        app.dependency_overrides[get_current_auth_user]=user
        self.client=httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url="http://admin.test")
        self.actor=uuid.uuid4()
        async def stable_user():
            return AuthenticatedUser(user_id=self.actor,raw_claims={"app_metadata":{"role":"admin"}})
        app.dependency_overrides[get_current_auth_user]=stable_user
        app.dependency_overrides[get_admin_auth_user]=stable_user

    async def asyncTearDown(self):
        await self.client.aclose()
        self.app.dependency_overrides.clear()
        await self.session.close()
        await self.transaction.rollback()
        await self.connection.close()
        await self.engine.dispose()
        settings.ADMIN_CONSOLE_ENABLED=self.previous_enabled

    async def test_editorial_conflict_idempotency_archive_and_reader(self):
        from scraper.sources.registry import get_all_source_metadata
        source=get_all_source_metadata()[0]
        slug=f"admin-integration-{uuid.uuid4().hex}"
        payload={"title":"Uji integrasi admin","slug":slug,"source_name":source["id"],"source_url":source["base_url"].rstrip("/")+"/"+slug}
        response=await self.client.post("/api/v1/admin-data/comics",json=payload,headers={"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(response.status_code,200,response.text)
        data=response.json();identifier=data["id"]
        path=f"/api/v1/admin-data/comics/{identifier}"
        headers={"If-Match":data["etag"],"Idempotency-Key":str(uuid.uuid4())}
        changed=await self.client.patch(path,json={"title":"Judul editorial teruji"},headers=headers)
        self.assertEqual(changed.status_code,200,changed.text)
        replay=await self.client.patch(path,json={"title":"Judul editorial teruji"},headers=headers)
        self.assertEqual(replay.json(),changed.json())
        conflict=await self.client.patch(path,json={"title":"Draft admin kedua"},headers={**headers,"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(conflict.status_code,412,conflict.text)
        public=f'/api/v1/sources/{source["id"]}/comics/{slug}'
        reader=await self.client.get(public)
        self.assertEqual(reader.status_code,200,reader.text)
        self.assertEqual(reader.json()["title"],"Judul editorial teruji")
        from app.models import Genre,comic_genre
        from sqlalchemy import select,func
        genre_id=await self.session.scalar(select(Genre.id).order_by(Genre.id).limit(1))
        genre_update=await self.client.patch(path,json={"genre_ids":[genre_id]},headers={"If-Match":changed.json()["etag"],"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(genre_update.status_code,200,genre_update.text)
        self.assertEqual(genre_update.json()["source"]["genre_ids"],[])
        genre_reader=await self.client.get(public)
        self.assertEqual([g["id"] for g in genre_reader.json()["genres"]],[genre_id])
        self.assertEqual(await self.session.scalar(select(func.count()).select_from(comic_genre).where(comic_genre.c.comic_id==identifier)),0)
        schema_response=await self.client.get("/api/v1/admin-data/schema")
        self.assertEqual(schema_response.status_code,200,schema_response.text)
        self.assertTrue(any(t["id"]=="monitoring.admin_sessions" for t in schema_response.json()["tables"]))
        from sqlalchemy import update,select
        from app.models import Comic
        await self.session.execute(update(Comic.__table__).where(Comic.__table__.c.id==identifier).values(title="Judul source diperbarui"))
        self.session.expire_all()
        current=(await self.client.get(path)).json()
        self.assertEqual(current["effective"]["title"],"Judul editorial teruji")
        self.assertEqual(current["source"]["title"],"Judul source diperbarui")
        archived=await self.client.post(path+"/archive",headers={"If-Match":current["etag"],"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(archived.status_code,200,archived.text)
        hidden=await self.client.get(public)
        self.assertEqual(hidden.status_code,404,hidden.text)
        restored=await self.client.post(path+"/restore",headers={"If-Match":archived.json()["etag"],"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(restored.status_code,200,restored.text)
        reset=await self.client.delete(path+"/overrides/title",headers={"If-Match":restored.json()["etag"],"Idempotency-Key":str(uuid.uuid4())})
        self.assertEqual(reset.status_code,200,reset.text)
        self.assertEqual(reset.json()["effective"]["title"],"Judul source diperbarui")


if __name__=="__main__":
    unittest.main()
