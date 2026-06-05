import unittest

from pydantic import ValidationError

from app.api.router import api_router
from app.models import HelpdeskSubmission
from app.schemas import HelpdeskSubmissionCreateRequest


class HelpdeskContractTests(unittest.TestCase):
    def test_router_exposes_helpdesk_paths(self):
        paths = {getattr(route, "path", "") for route in api_router.routes}
        self.assertIn("/v1/helpdesk/submissions", paths)
        methods = {
            method
            for route in api_router.routes
            if getattr(route, "path", "") == "/v1/helpdesk/submissions"
            for method in getattr(route, "methods", set())
        }
        self.assertIn("POST", methods)
        self.assertIn("GET", methods)

    def test_model_declares_reference_and_workflow_constraints(self):
        constraint_names = {
            constraint.name
            for constraint in HelpdeskSubmission.__table__.constraints
        }
        index_names = {
            index.name for index in HelpdeskSubmission.__table__.indexes
        }
        self.assertIn("ck_helpdesk_submissions_category", constraint_names)
        self.assertIn("ck_helpdesk_submissions_rating", constraint_names)
        self.assertIn("ck_helpdesk_submissions_status", constraint_names)
        self.assertIn(
            "ix_helpdesk_submissions_status_created_at",
            index_names,
        )

    def test_review_requires_rating_and_normalizes_message(self):
        payload = HelpdeskSubmissionCreateRequest(
            category="review",
            rating=5,
            title="ignored",
            message="  Aplikasi ini sangat membantu untuk membaca komik.  ",
            platform=" android ",
        )
        self.assertEqual(payload.rating, 5)
        self.assertIsNone(payload.title)
        self.assertEqual(
            payload.message,
            "Aplikasi ini sangat membantu untuk membaca komik.",
        )
        self.assertEqual(payload.platform, "android")

    def test_report_requires_title_and_rejects_rating(self):
        with self.assertRaises(ValidationError):
            HelpdeskSubmissionCreateRequest(
                category="report",
                rating=3,
                title="Crash",
                message="Aplikasi crash ketika membuka chapter tertentu.",
                platform="android",
            )

        with self.assertRaises(ValidationError):
            HelpdeskSubmissionCreateRequest(
                category="report",
                title="Bug",
                message="Aplikasi crash ketika membuka chapter tertentu.",
                platform="android",
            )


if __name__ == "__main__":
    unittest.main()
