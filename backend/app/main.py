import sys
import os
import asyncio

if sys.platform == "win32":
    # Playwright/patchright membutuhkan ProactorEventLoop di Windows untuk menjalankan subprocess browser
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
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
    # Startup — mulai background worker Komiku Asia
    from app.services.http_client_service import (
        shutdown_http_clients,
        startup_http_clients,
    )
    from app.services.komiku_asia_worker import start_worker, stop_worker

    await startup_http_clients()
    try:
        await start_worker()
        yield
    finally:
        # Shutdown — hentikan worker secara graceful dan tutup pooled HTTP clients
        await stop_worker()
        await shutdown_http_clients()


app = FastAPI(
    title="Tonztoon Komik API",
    description="REST API untuk aplikasi pembaca komik (manga/manhwa/manhua)",
    version="1.21.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS — izinkan app lokal, admin HTML file://, dan frontend development mengakses API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "null",
        "http://127.0.0.1:8000",
        "http://localhost:8000",
    ],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Include all API routes
app.include_router(api_router, prefix="/api")

# Mount admin static files (mendukung local dev & Docker container)
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
admin_dir = os.path.join(base_dir, "admin")
if not os.path.exists(admin_dir):
    admin_dir = os.path.join(os.path.dirname(base_dir), "admin")

if os.path.exists(admin_dir):
    app.mount("/admin", StaticFiles(directory=admin_dir, html=True), name="admin")


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        headers=exc.headers,
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
        "version": "1.21.0",
        "status": "running",
        "environment": settings.APP_ENV,
    }
