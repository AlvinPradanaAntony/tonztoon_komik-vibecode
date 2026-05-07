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

from app.services.image_service import (
    get_proxy_headers,
)

router = APIRouter()


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

    headers = get_proxy_headers(url)

    client = httpx.AsyncClient(follow_redirects=True, timeout=30.0)
    response: httpx.Response | None = None
    try:
        request = client.build_request("GET", url, headers=headers)
        response = await client.send(request, stream=True)

        if response.status_code != 200:
            await response.aclose()
            await client.aclose()
            raise HTTPException(
                status_code=response.status_code,
                detail="Failed to fetch image from source",
            )

        content_type = response.headers.get("content-type", "image/jpeg")

        async def stream_content():
            try:
                async for chunk in response.aiter_bytes():
                    yield chunk
            finally:
                await response.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_content(),
            media_type=content_type,
            headers={
                "Cache-Control": "public, max-age=86400",  # 24h cache
            },
        )

    except httpx.TimeoutException:
        if response is not None:
            await response.aclose()
        await client.aclose()
        raise HTTPException(status_code=504, detail="Image source timed out")
    except httpx.RequestError as e:
        if response is not None:
            await response.aclose()
        await client.aclose()
        raise HTTPException(status_code=502, detail=f"Failed to fetch image: {str(e)}")
