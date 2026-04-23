"""
Tonztoon Komik — API Router Aggregator

Menggabungkan semua sub-router ke satu v1 prefix.
"""

from fastapi import APIRouter

from app.api.v1 import sources, search, genres, images, scraper, library, auth

api_router = APIRouter()

api_router.include_router(sources.router, prefix="/v1/sources", tags=["Sources"])
api_router.include_router(search.router, prefix="/v1/search", tags=["Search"])
api_router.include_router(genres.router, prefix="/v1/genres", tags=["Genres"])
api_router.include_router(images.router, prefix="/v1/images", tags=["Images"])
api_router.include_router(scraper.router, prefix="/v1/scraper", tags=["Scraper"])
api_router.include_router(library.router, prefix="/v1/library", tags=["Library"])
api_router.include_router(auth.router, prefix="/v1/auth", tags=["Auth"])
