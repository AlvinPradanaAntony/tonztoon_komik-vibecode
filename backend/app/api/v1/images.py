"""
Tonztoon Komik — Image Proxy Route

Endpoints:
    GET /api/v1/images/proxy?url={target_url} — Stream gambar dari server asli

Menggunakan FastAPI StreamingResponse untuk mengalirkan bytes gambar
tanpa memuat seluruh gambar di RAM server.
"""

from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse
import httpx

router = APIRouter()

# Referer headers per-source agar tidak terblokir hotlink protection
SOURCE_REFERERS = {
    "komiku.org": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "komikcast": "https://v1.komikcast.fit/",
    "shinigami": "https://e.shinigami.asia/",
}


def _guess_referer(url: str) -> str:
    """Tebak header Referer yang tepat berdasarkan URL gambar."""
    for key, referer in SOURCE_REFERERS.items():
        if key in url:
            return referer
    # Fallback: gunakan origin dari URL
    from urllib.parse import urlparse
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}/"


@router.get("/proxy")
async def proxy_image(
    url: str = Query(..., description="URL gambar asli dari server komik"),
):
    """
    Proxy gambar komik menggunakan StreamingResponse.

    Flow:
    1. Flutter request ke endpoint ini dengan query param `url`
    2. Backend fetch gambar dari server asli dengan header Referer yang benar
    3. Response di-stream langsung ke client tanpa buffering penuh di RAM
    """
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Invalid image URL")

    referer = _guess_referer(url)

    headers = {
        "Referer": referer,
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
    }

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
            response = await client.get(url, headers=headers)

            if response.status_code != 200:
                raise HTTPException(
                    status_code=response.status_code,
                    detail="Failed to fetch image from source",
                )

            content_type = response.headers.get("content-type", "image/jpeg")

            async def stream_content():
                yield response.content

            return StreamingResponse(
                stream_content(),
                media_type=content_type,
                headers={
                    "Cache-Control": "public, max-age=86400",  # 24h cache
                },
            )

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Image source timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Failed to fetch image: {str(e)}")
