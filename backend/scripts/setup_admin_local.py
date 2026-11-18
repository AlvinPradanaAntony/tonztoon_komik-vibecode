"""Create ignored local Next.js configuration without printing secrets."""
import base64
import os
from pathlib import Path
from app.config import settings

destination=Path(__file__).resolve().parents[2]/"web"/".env.local"
if destination.exists():
    print("web/.env.local already exists; left unchanged.")
else:
    values={
        "BACKEND_BASE_URL":"http://127.0.0.1:8000",
        "ADMIN_WEB_ORIGIN":"http://localhost:3000",
        "ADMIN_SESSION_DATABASE_URL":settings.DATABASE_URL.replace("postgresql+asyncpg://","postgresql://"),
        "ADMIN_SESSION_ENCRYPTION_KEY":base64.b64encode(os.urandom(32)).decode(),
        "SUPABASE_URL":settings.SUPABASE_URL,
        "SUPABASE_PUBLISHABLE_KEY":settings.SUPABASE_PUBLISHABLE_KEY,
        "ADMIN_USER_IDS":settings.ADMIN_USER_IDS,
        "ADMIN_ENVIRONMENT":settings.APP_ENV,
    }
    destination.write_text("\n".join(f"{k}={v}" for k,v in values.items())+"\n",encoding="utf-8")
    print("Created ignored web/.env.local using backend configuration. Secret values were not printed.")
