"""
Tonztoon Komik — Image Proxy Route

Endpoints:
    GET /api/v1/images/proxy?url={target_url} — Stream gambar dari server asli

Menggunakan FastAPI StreamingResponse untuk mengalirkan bytes gambar
tanpa memuat seluruh gambar di RAM server.
"""

from fastapi import APIRouter, Query, HTTPException, Depends
from fastapi.responses import Response, StreamingResponse
import httpx
import logging
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.services.image_service import (
    ImageProxyPayloadTooLargeError,
    ImageProxyValidationError,
    extract_komikcast_series_slug_from_cover_url,
    optimize_image_response,
    open_validated_image_proxy_response,
    refresh_komikcast_cover_url,
    stream_image_response_with_limit,
    update_komikcast_cover_url_for_slug,
)
from app.services.http_client_service import get_image_proxy_http_client

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/proxy")
async def proxy_image(
    url: str = Query(..., description="URL gambar asli dari server komik"),
    width: int | None = Query(
        None,
        ge=160,
        le=1440,
        description="Lebar maksimum varian cover hasil resize.",
    ),
    quality: int = Query(
        82,
        ge=60,
        le=95,
        description="Kualitas WebP varian cover.",
    ),
    db: AsyncSession = Depends(get_db),
):
    """
    Proxy gambar komik menggunakan StreamingResponse.

    Flow:
    1. Flutter request ke endpoint ini dengan query param `url`
    2. Backend fetch gambar dari server asli dengan header Referer yang benar
    3. Response di-stream langsung ke client tanpa buffering penuh di RAM
    """
    client = get_image_proxy_http_client()
    proxy_result = None
    try:
        proxy_result = await open_validated_image_proxy_response(url, client=client)
        response = proxy_result.response

        if response.status_code != 200:
            await response.aclose()
            fresh_url = await refresh_komikcast_cover_url(client, url)
            if fresh_url:
                proxy_result = await open_validated_image_proxy_response(
                    fresh_url,
                    client=client,
                )
                response = proxy_result.response
                if response.status_code == 200:
                    slug = extract_komikcast_series_slug_from_cover_url(url)
                    if slug:
                        try:
                            await update_komikcast_cover_url_for_slug(
                                db,
                                slug=slug,
                                cover_url=fresh_url,
                            )
                        except Exception:
                            await db.rollback()
                            logger.exception(
                                "Failed to persist refreshed Komikcast cover URL for slug=%s",
                                slug,
                            )
                else:
                    await response.aclose()
                    raise HTTPException(
                        status_code=response.status_code,
                        detail="Failed to fetch refreshed image from source",
                    )
            else:
                raise HTTPException(
                    status_code=response.status_code,
                    detail="Failed to fetch image from source",
                )

        if response.status_code != 200:
            raise HTTPException(
                status_code=response.status_code,
                detail="Failed to fetch image from source",
            )

        if width is not None:
            optimized = await optimize_image_response(
                response,
                content_type=proxy_result.content_type,
                max_width=width,
                quality=quality,
            )
            return Response(
                content=optimized.body,
                media_type=optimized.content_type,
                headers={
                    "Cache-Control": "public, max-age=86400",
                },
            )

        return StreamingResponse(
            stream_image_response_with_limit(response),
            media_type=proxy_result.content_type,
            headers={
                "Cache-Control": "public, max-age=86400",  # 24h cache
            },
        )

    except ImageProxyPayloadTooLargeError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    except ImageProxyValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except httpx.TimeoutException:
        if proxy_result is not None:
            await proxy_result.response.aclose()
        raise HTTPException(status_code=504, detail="Image source timed out")
    except httpx.RequestError as e:
        if proxy_result is not None:
            await proxy_result.response.aclose()
        raise HTTPException(status_code=502, detail=f"Failed to fetch image: {str(e)}")
