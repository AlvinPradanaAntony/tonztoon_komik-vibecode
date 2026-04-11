"""
Tonztoon Komik — FastAPI Application Entry Point

Menjalankan:
    uvicorn app.main:app --reload
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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


@app.get("/", tags=["Health"])
async def root():
    """Health check endpoint."""
    return {
        "app": "Tonztoon Komik API",
        "version": "0.1.0",
        "status": "running",
        "environment": settings.APP_ENV,
    }
