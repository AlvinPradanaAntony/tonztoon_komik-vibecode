"""
Tonztoon Komik — Pagination Utility

Helper functions untuk kalkulasi pagination yang konsisten
di seluruh API endpoints.
"""

import math


def paginate(total: int, page: int, page_size: int) -> dict:
    """
    Hitung metadata pagination.

    Args:
        total: Total jumlah item
        page: Halaman saat ini (1-indexed)
        page_size: Jumlah item per halaman

    Returns:
        Dict berisi metadata pagination
    """
    total_pages = math.ceil(total / page_size) if page_size > 0 else 0
    offset = (page - 1) * page_size

    return {
        "total": total,
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
        "offset": offset,
        "has_next": page < total_pages,
        "has_prev": page > 1,
    }
