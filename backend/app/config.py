"""
Tonztoon Komik — Application Configuration

Menggunakan Pydantic Settings untuk mengelola environment variables
dengan validasi otomatis dan type safety.
"""

from pydantic_settings import BaseSettings
from pydantic import Field


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

    # --- App ---
    APP_ENV: str = Field(default="development")
    APP_DEBUG: bool = Field(default=False)

    model_config = {
        "env_file": ".env",
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
