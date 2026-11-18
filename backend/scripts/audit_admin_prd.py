"""Read-only, in-memory contract probes for the admin PRD audit.

No HTTP calls, database writes, production log emission, or real credentials.
Run from backend/: python -m scripts.audit_admin_prd
"""
import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from app.admin.telemetry import LIMITS, Telemetry, TelemetryMiddleware
from app.config import settings


async def main():
    checks = []

    async def request_probe(method, path, expected):
        store = Telemetry()

        async def application(scope, receive, send):
            scope["route"] = SimpleNamespace(path=path)
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"{}", "more_body": False})

        async def send(message):
            pass

        with patch.object(settings, "ADMIN_CONSOLE_ENABLED", True), patch("app.admin.telemetry.telemetry", store):
            await TelemetryMiddleware(application)({"type": "http", "method": method, "path": path}, None, send)
        actual = store.snapshot()["metrics"]["completed"]
        checks.append({"check": f"reader_kpi_scope:{method} {path}", "expected": expected, "actual": actual, "passed": actual == expected})

    await request_probe("GET", "/api/v1/comics", 1)
    await request_probe("GET", "/api/v1/account-manager/accounts", 0)
    await request_probe("OPTIONS", "/api/v1/comics", 0)
    store = Telemetry()
    required = {"client_errors", "client_error_rate_percent", "p50_ms", "p99_ms"}
    missing = sorted(required - store.snapshot()["metrics"].keys())
    checks.append({"check": "overview_required_metric_families", "missing": missing, "passed": not missing})
    expected_limits = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000, 60000, float("inf")]
    checks.append({"check": "prd_histogram_boundaries", "passed": LIMITS == expected_limits})
    synthetic = "AUDIT_SYNTHETIC_CREDENTIAL_42"
    store.log("audit.fixture", "ERROR", json.dumps({"password": synthetic}))
    leaked = synthetic in json.dumps(list(store.logs))
    checks.append({"check": "json_password_redacted_before_runtime_buffer", "synthetic_value_retained": leaked, "passed": not leaked})
    report = {"report_date": "2026-10-26", "scope": "in_memory_contract_probes", "checks": checks,
              "result": "nonconformant" if any(not item["passed"] for item in checks) else "passed"}
    target = Path(__file__).resolve().parents[2] / "web" / "test-results" / "prd-audit-contracts.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))
    return report["result"] == "passed"


if __name__ == "__main__":
    raise SystemExit(0 if asyncio.run(main()) else 1)
