"""
Tonztoon Komik — Application Configuration

Menggunakan Pydantic Settings untuk mengelola environment variables
dengan validasi otomatis dan type safety.
"""

from pathlib import Path

from pydantic_settings import BaseSettings
from pydantic import Field


BACKEND_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = BACKEND_DIR / ".env"


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # --- Database ---
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/tonztoon_komik",
        description="PostgreSQL connection string (async)"
    )

    # --- Supabase Auth ---
    SUPABASE_URL: str = Field(
        default="",
        description="Supabase project URL, e.g. https://project-ref.supabase.co",
    )
    SUPABASE_PUBLISHABLE_KEY: str = Field(
        default="",
        description="Supabase publishable/anon key used for public auth operations",
    )
    SUPABASE_SERVICE_ROLE_KEY: str = Field(
        default="",
        description="Supabase service role key for privileged server-side operations",
    )
    SUPABASE_COVER_BUCKET: str = Field(
        default="",
        description="Supabase Storage bucket for cached comic cover images",
    )
    SUPABASE_AVATAR_BUCKET: str = Field(
        default="avatars",
        description="Supabase Storage bucket for user profile avatars",
    )
    SUPABASE_JWT_SECRET: str = Field(
        default="",
        description="Legacy JWT secret fallback for HS256 token verification",
    )
    SUPABASE_JWT_AUDIENCE: str = Field(
        default="authenticated",
        description="Expected aud claim for Supabase access tokens",
    )
    SUPABASE_JWT_ISSUER: str = Field(
        default="",
        description="Expected iss claim. Defaults to <SUPABASE_URL>/auth/v1 if empty",
    )
    SUPABASE_AUTH_REDIRECT_URL: str = Field(
        default="",
        description="Optional redirect URL for signup confirmation emails",
    )
    ADMIN_USER_IDS: str = Field(
        default="",
        description="Comma-separated Supabase Auth user IDs allowed to access admin endpoints",
    )
    ALLOW_DEV_USER_HEADER: bool = Field(
        default=False,
        description="Allow X-User-Id fallback header during development when bearer token is absent",
    )

    # --- GitHub API (workflow_dispatch) ---
    GITHUB_PAT: str = Field(
        default="",
        description="GitHub Personal Access Token for triggering workflow_dispatch"
    )
    GITHUB_REPO_OWNER: str = Field(
        default="",
        description="GitHub repository owner/username"
    )
    GITHUB_REPO_NAME: str = Field(
        default="tonztoon_komik",
        description="GitHub repository name"
    )
    GITHUB_WORKFLOW_FILE: str = Field(
        default="scraper.yml",
        description="GitHub Actions workflow filename"
    )

    # --- Image Proxy Protection ---
    IMAGE_PROXY_ALLOWED_HOSTS: str = Field(
        default="",
        description=(
            "Comma-separated host suffixes allowed by image proxy, appended to "
            "the built-in source allowlist."
        ),
    )
    IMAGE_PROXY_MAX_BYTES: int = Field(
        default=10 * 1024 * 1024,
        ge=1,
        description="Maximum upstream image payload size accepted by proxy.",
    )
    IMAGE_PROXY_MAX_REDIRECTS: int = Field(
        default=3,
        ge=0,
        le=10,
        description="Maximum validated redirects followed by image proxy.",
    )

    # --- Firebase Cloud Messaging ---
    FCM_PROJECT_ID: str = Field(
        default="",
        description="Firebase project ID used for FCM HTTP v1.",
    )
    FCM_SERVICE_ACCOUNT_JSON: str = Field(
        default="",
        description="Raw Firebase service account JSON for FCM HTTP v1.",
    )
    FCM_SERVICE_ACCOUNT_FILE: str = Field(
        default="",
        description="Path to Firebase service account JSON file.",
    )
    PUSH_EVENT_API_KEY: str = Field(
        default="",
        description="Optional API key for internal push notification event endpoints.",
    )


    KOMIKU_ASIA_LIVE_SCRAPE_PROVIDER: str = Field(
        default="auto",
        description=(
            "Deprecated compatibility setting for Komiku Asia lazy chapter "
            "image fetching. Runtime always uses the first-party API scraper."
        ),
    )
    KOMIKU_ASIA_ZENROWS_WAIT_MS: int = Field(
        default=6000,
        ge=0,
        description="Legacy ZenRows wait time; inactive for the API-first Komiku scraper.",
    )

    # --- ZenRows Scraping API ---
    ZENROWS_API_KEY: str = Field(
        default="",
        description="Legacy ZenRows API key; inactive for the API-first Komiku scraper.",
    )
    ZENROWS_API_BASE_URL: str = Field(
        default="https://api.zenrows.com/v1/",
        description="Legacy ZenRows endpoint; inactive for the API-first Komiku scraper.",
    )
    ZENROWS_TIMEOUT_SECONDS: float = Field(
        default=120.0,
        ge=10.0,
        description="Legacy ZenRows timeout; inactive for the API-first Komiku scraper.",
    )


    # --- App ---
    APP_ENV: str = Field(default="development")
    APP_DEBUG: bool = Field(default=False)

    model_config = {
        "env_file": ENV_FILE,
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


# Singleton instance
settings = Settings()


def _strip_trailing_slash(value: str) -> str:
    return value.rstrip("/")


def get_supabase_auth_base_url() -> str:
    """Return Supabase Auth base URL."""
    if not settings.SUPABASE_URL:
        return ""
    return f"{_strip_trailing_slash(settings.SUPABASE_URL)}/auth/v1"


def get_supabase_jwks_url() -> str:
    """Return Supabase JWKS URL."""
    auth_base = get_supabase_auth_base_url()
    if not auth_base:
        return ""
    return f"{auth_base}/.well-known/jwks.json"


def get_supabase_jwt_issuer() -> str:
    """Return expected JWT issuer."""
    if settings.SUPABASE_JWT_ISSUER:
        return settings.SUPABASE_JWT_ISSUER.rstrip("/")
    return get_supabase_auth_base_url()
