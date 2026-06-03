import unittest

from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from app.api.router import api_router
from app.models import PushNotificationEvent, UserPushDevice
from app.schemas import (
    AdminAnnouncementRequest,
    ChapterUpdateEventRequest,
    ComicCreate,
    PushDeviceRegisterRequest,
)
from scraper.main import build_chapter_update_event


def compile_sql(statement) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


class PushNotificationContractTests(unittest.TestCase):
    def test_router_exposes_notification_contract_paths(self):
        paths = {getattr(route, "path", "") for route in api_router.routes}
        self.assertIn("/v1/notifications/devices", paths)
        self.assertIn("/v1/notifications/events/chapter-update", paths)
        self.assertIn("/v1/notifications/admin-announcements", paths)

    def test_device_model_declares_token_uniqueness_and_active_index(self):
        constraint_names = {
            constraint.name for constraint in UserPushDevice.__table__.constraints
        }
        index_names = {index.name for index in UserPushDevice.__table__.indexes}

        self.assertIn(
            "uq_user_push_devices_provider_token_hash",
            constraint_names,
        )
        self.assertIn("ix_user_push_devices_user_active", index_names)

    def test_event_model_declares_event_id_uniqueness(self):
        constraint_names = {
            constraint.name for constraint in PushNotificationEvent.__table__.constraints
        }
        self.assertIn("uq_push_notification_events_event_id", constraint_names)

    def test_target_device_query_is_source_independent(self):
        sql = compile_sql(
            select(UserPushDevice.id).where(
                UserPushDevice.provider == "fcm",
                UserPushDevice.platform == "android",
                UserPushDevice.active.is_(True),
            )
        )
        self.assertIn("user_push_devices.provider", sql)
        self.assertIn("user_push_devices.platform", sql)
        self.assertIn("user_push_devices.active IS true", sql)

    def test_register_request_trims_token(self):
        payload = PushDeviceRegisterRequest(
            provider="fcm",
            platform="android",
            token=" token-value ",
            user_id="00000000-0000-0000-0000-000000000001",
        )
        self.assertEqual(payload.token, "token-value")

    def test_chapter_event_request_trims_route_parts(self):
        payload = ChapterUpdateEventRequest(
            source_name=" komikcast ",
            comic_slug=" example-slug ",
            comic_title=" Example Comic ",
            latest_chapter_number=12,
            event_id=" chapter:komikcast:example-slug:12 ",
        )
        self.assertEqual(payload.source_name, "komikcast")
        self.assertEqual(payload.comic_slug, "example-slug")
        self.assertEqual(payload.event_id, "chapter:komikcast:example-slug:12")

    def test_admin_announcement_request_trims_payload(self):
        payload = AdminAnnouncementRequest(
            title=" Maintenance ",
            message=" Server akan maintenance. ",
            category=" Pengumuman ",
            action_route=" /notifications ",
        )
        self.assertEqual(payload.title, "Maintenance")
        self.assertEqual(payload.message, "Server akan maintenance.")
        self.assertEqual(payload.category, "Pengumuman")
        self.assertEqual(payload.action_route, "/notifications")

    def test_scraper_builds_chapter_update_event_contract(self):
        comic = ComicCreate(
            title="Example Comic",
            slug="example-slug",
            source_name="komikcast",
            source_url="https://example.test/comic/example-slug",
        )
        event = build_chapter_update_event(
            validated=comic,
            latest_chapter={
                "chapter_number": 12,
                "title": "Chapter 12",
                "source_url": "https://example.test/chapter-12",
            },
        )

        self.assertIsNotNone(event)
        self.assertEqual(event.event_id, "chapter:komikcast:example-slug:12")
        self.assertEqual(event.source_name, "komikcast")
        self.assertEqual(event.comic_slug, "example-slug")
        self.assertEqual(event.latest_chapter_number, 12)


if __name__ == "__main__":
    unittest.main()
