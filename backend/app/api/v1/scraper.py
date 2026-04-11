"""
Tonztoon Komik — Scraper Sync Route (Manual Trigger)

Endpoints:
    POST /api/v1/scraper/sync — Trigger GitHub Actions workflow_dispatch

Alur:
1. Flutter app memanggil endpoint ini untuk sync manual
2. Backend request ke GitHub API (workflow_dispatch)
3. GitHub Actions menjalankan scraper/main.py secara asinkron
4. Backend langsung merespons "Sync started" ke client (fire-and-forget)
"""

from fastapi import APIRouter, HTTPException
import httpx

from app.config import settings

router = APIRouter()


@router.post("/sync")
async def trigger_manual_sync():
    """
    Trigger manual scraping via GitHub Actions workflow_dispatch.

    Membutuhkan environment variables:
    - GITHUB_PAT: Personal Access Token
    - GITHUB_REPO_OWNER: Owner/username
    - GITHUB_REPO_NAME: Repository name
    - GITHUB_WORKFLOW_FILE: Nama file workflow (e.g. scraper.yml)
    """
    # Validasi konfigurasi
    if not settings.GITHUB_PAT:
        raise HTTPException(
            status_code=500,
            detail="GitHub PAT not configured. Set GITHUB_PAT in .env",
        )
    if not settings.GITHUB_REPO_OWNER:
        raise HTTPException(
            status_code=500,
            detail="GitHub repo owner not configured. Set GITHUB_REPO_OWNER in .env",
        )

    # GitHub API URL untuk workflow_dispatch
    api_url = (
        f"https://api.github.com/repos/"
        f"{settings.GITHUB_REPO_OWNER}/{settings.GITHUB_REPO_NAME}/"
        f"actions/workflows/{settings.GITHUB_WORKFLOW_FILE}/dispatches"
    )

    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {settings.GITHUB_PAT}",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    payload = {
        "ref": "main",  # Branch target
        "inputs": {
            "trigger_source": "manual_api",
        },
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(api_url, json=payload, headers=headers)

        # GitHub returns 204 No Content on success
        if response.status_code == 204:
            return {
                "status": "success",
                "message": "Scraper sync triggered successfully. GitHub Actions will run the scraper shortly.",
            }
        elif response.status_code == 404:
            raise HTTPException(
                status_code=404,
                detail="Workflow not found. Check GITHUB_WORKFLOW_FILE and repository settings.",
            )
        elif response.status_code == 403:
            raise HTTPException(
                status_code=403,
                detail="GitHub PAT lacks permissions. Ensure it has 'actions:write' scope.",
            )
        else:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"GitHub API error: {response.text}",
            )

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="GitHub API request timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Failed to reach GitHub API: {str(e)}")
