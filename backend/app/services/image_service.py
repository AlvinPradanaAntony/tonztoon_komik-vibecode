"""
Tonztoon Komik — Image Service

Utility functions untuk image proxy logic.
Digunakan oleh route /api/v1/images/proxy.
"""

from urllib.parse import urlparse


# Mapping domain -> Referer header yang benar
REFERER_MAP = {
    "komiku.org": "https://komiku.org/",
    "komiku.asia": "https://01.komiku.asia/",
    "komikcast": "https://v1.komikcast.fit/",
    "shinigami": "https://e.shinigami.asia/",
}

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)


def get_proxy_headers(image_url: str) -> dict[str, str]:
    """
    Generate headers yang tepat untuk fetch gambar dari server asli.
    Menentukan Referer berdasarkan domain URL gambar.
    """
    referer = None
    for key, ref_url in REFERER_MAP.items():
        if key in image_url:
            referer = ref_url
            break

    if referer is None:
        parsed = urlparse(image_url)
        referer = f"{parsed.scheme}://{parsed.netloc}/"

    return {
        "Referer": referer,
        "User-Agent": DEFAULT_USER_AGENT,
    }
