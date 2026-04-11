"""
Tonztoon Komik — API Router Aggregator

Menggabungkan semua sub-router ke satu v1 prefix.
"""

from fastapi import APIRouter

from app.api.v1 import comics, chapters, search, genres, images, scraper

api_router = APIRouter()

api_router.include_router(comics.router, prefix="/v1/comics", tags=["Comics"])
api_router.include_router(chapters.router, prefix="/v1/chapters", tags=["Chapters"])
api_router.include_router(search.router, prefix="/v1/search", tags=["Search"])
api_router.include_router(genres.router, prefix="/v1/genres", tags=["Genres"])
api_router.include_router(images.router, prefix="/v1/images", tags=["Images"])
api_router.include_router(scraper.router, prefix="/v1/scraper", tags=["Scraper"])
