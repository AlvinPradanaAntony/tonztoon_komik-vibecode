import unittest

from pydantic import ValidationError

from app.api.router import api_router
from app.models import HelpdeskSubmission
from app.schemas import HelpdeskSubmissionCreateRequest


class HelpdeskContractTests(unittest.TestCase):
    def test_router_exposes_helpdesk_paths(self):
        def get_all_routes(router, prefix=""):
            res = []
            for route in router.routes:
                path = getattr(route, "path", None)
                if path is not None:
                    res.append((prefix + path, getattr(route, "methods", set())))
                else:
                    original_router = getattr(route, "original_router", None)
                    include_context = getattr(route, "include_context", None)
                    if original_router is not None and include_context is not None:
                        sub_prefix = getattr(include_context, "prefix", "")
                        res.extend(get_all_routes(original_router, prefix + sub_prefix))
            return res

        routes = get_all_routes(api_router)
        paths = {r[0] for r in routes}
        self.assertIn("/v1/helpdesk/submissions", paths)
        self.assertIn("/v1/helpdesk/submissions/{submission_id}", paths)
        
        methods = {
            method
            for path, m_set in routes
            if path == "/v1/helpdesk/submissions"
            for method in m_set
        }
        self.assertIn("POST", methods)
        self.assertIn("GET", methods)

        detail_methods = {
            method
            for path, m_set in routes
            if path == "/v1/helpdesk/submissions/{submission_id}"
            for method in m_set
        }
        self.assertIn("PATCH", detail_methods)
        self.assertIn("DELETE", detail_methods)

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
