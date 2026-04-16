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
    APP_DEBUG: bool = Field(default=True)

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


# Singleton instance
settings = Settings()
