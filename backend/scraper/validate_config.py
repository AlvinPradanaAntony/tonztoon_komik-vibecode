"""
Tonztoon Komik — Pre-flight Configuration Validator.

Memvalidasi bahwa secret environment variables (DATABASE_URL, FCM configuration)
terisi dan valid sebelum workflow scraper / sync dijalankan.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


def validate_configuration(*, require_fcm: bool = True) -> list[str]:
    """Validasi konfigurasi database dan Firebase Cloud Messaging (FCM)."""
    errors: list[str] = []

    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        errors.append("DATABASE_URL secret is empty.")

    if not require_fcm:
        return errors

    project_id = os.environ.get("FCM_PROJECT_ID", "").strip()
    raw_service_account = os.environ.get("FCM_SERVICE_ACCOUNT_JSON", "").strip()

    service_account: dict[str, Any] = {}
    if not raw_service_account:
        errors.append("FCM_SERVICE_ACCOUNT_JSON secret is empty.")
    else:
        try:
            service_account = json.loads(raw_service_account)
        except json.JSONDecodeError:
            errors.append("FCM_SERVICE_ACCOUNT_JSON is not valid JSON.")

    for field in ("client_email", "private_key"):
        if service_account and not service_account.get(field):
            errors.append(f"FCM_SERVICE_ACCOUNT_JSON is missing {field}.")

    json_project_id = str(service_account.get("project_id") or "").strip()
    if not project_id and not json_project_id:
        errors.append(
            "FCM project ID is missing from both FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT_JSON."
        )
    elif project_id and json_project_id and project_id != json_project_id:
        errors.append("FCM_PROJECT_ID does not match the service account project_id.")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate environment configuration secrets.")
    parser.add_argument("--db-only", action="store_true", help="Only validate DATABASE_URL, skip FCM checks")
    args = parser.parse_args()

    errors = validate_configuration(require_fcm=not args.db_only)
    if errors:
        for error in errors:
            print(f"::error::{error}")
        sys.exit(1)

    if args.db_only:
        print("Database configuration is present and valid.")
    else:
        print("Database and FCM configuration are present and valid.")


if __name__ == "__main__":
    main()
