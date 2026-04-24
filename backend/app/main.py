"""
Tonztoon Komik — FastAPI Application Entry Point

Menjalankan:
    uvicorn app.main:app --reload
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.errors import (
    build_error_payload,
    build_unhandled_error_payload,
    get_fallback_error_message,
)
from app.config import settings
from app.api.router import api_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup & shutdown lifecycle events."""
    # Startup
    yield
    # Shutdown — cleanup resources jika perlu


app = FastAPI(
    title="Tonztoon Komik API",
    description="REST API untuk aplikasi pembaca komik (manga/manhwa/manhua)",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS — izinkan Flutter app mengakses API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: restrict untuk production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include all API routes
app.include_router(api_router, prefix="/api")


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content=build_error_payload(
            exc.detail,
            fallback_message=get_fallback_error_message(exc.status_code),
        ),
    )


@app.exception_handler(RequestValidationError)
async def request_validation_exception_handler(
    _: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "message": get_fallback_error_message(422),
            "errors": exc.errors(),
        },
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content=build_unhandled_error_payload(
            exc,
            fallback_message=get_fallback_error_message(500),
            include_debug_detail=settings.APP_DEBUG,
        ),
    )


@app.get("/", tags=["Health"])
async def root():
    """Health check endpoint."""
    return {
        "app": "Tonztoon Komik API",
        "version": "0.1.0",
        "status": "running",
        "environment": settings.APP_ENV,
    }
