import unittest
from unittest.mock import AsyncMock, patch

import httpx

from app.services.image_service import (
    ImageProxyFetchResult,
    _parse_avif_dimensions,
    _parse_jpeg_dimensions,
    probe_image_dimensions,
)


def _box(box_type: bytes, payload: bytes) -> bytes:
    return (8 + len(payload)).to_bytes(4, "big") + box_type + payload


def _avif_fixture(width: int = 1080, height: int = 670) -> bytes:
    ftyp = _box(
        b"ftyp",
        b"avif" + (0).to_bytes(4, "big") + b"avif",
    )
    ispe = _box(
        b"ispe",
        (0).to_bytes(4, "big")
        + width.to_bytes(4, "big")
        + height.to_bytes(4, "big"),
    )
    # The parser should not depend on the nesting depth used by the AVIF file.
    nested_properties = _box(b"ipco", ispe)
    return ftyp + _box(
        b"meta",
        (0).to_bytes(4, "big") + _box(b"iprp", nested_properties),
    )


def _jpeg_fixture(width: int = 720, height: int = 1280) -> bytes:
    app1_payload = b"Exif\x00\x00" + b"metadata"
    app1 = b"\xff\xe1" + (len(app1_payload) + 2).to_bytes(2, "big") + app1_payload
    sof0_payload = (
        b"\x08"
        + height.to_bytes(2, "big")
        + width.to_bytes(2, "big")
        + b"\x01\x01\x11\x00"
    )
    sof0 = b"\xff\xc0" + (len(sof0_payload) + 2).to_bytes(2, "big") + sof0_payload
    return b"\xff\xd8" + app1 + sof0


class _FakeResponse:
    def __init__(self, body: bytes, status_code: int = 206):
        self.body = body
        self.status_code = status_code

    async def aclose(self):
        return None

    async def aiter_bytes(self):
        yield self.body


class _FakeStream:
    def __init__(self, response: _FakeResponse):
        self.response = response

    async def __aenter__(self):
        return self.response

    async def __aexit__(self, exc_type, exc, traceback):
        return False


class _FakeClient:
    def __init__(self, body: bytes, status_code: int = 206):
        self.response = _FakeResponse(body, status_code)
        self.headers = None

    def stream(self, method, url, *, headers, follow_redirects, timeout):
        self.headers = headers
        return _FakeStream(self.response)


class ImageDimensionTests(unittest.IsolatedAsyncioTestCase):
    def test_parse_avif_dimensions_from_ispe_box(self):
        self.assertEqual(_parse_avif_dimensions(_avif_fixture()), (1080, 670))

    def test_parse_avif_rejects_truncated_ispe_box(self):
        data = _avif_fixture()[:-2]
        self.assertIsNone(_parse_avif_dimensions(data))

    def test_parse_jpeg_dimensions_from_sof_marker(self):
        self.assertEqual(_parse_jpeg_dimensions(_jpeg_fixture()), (720, 1280))

    async def test_probe_accepts_partial_avif_response(self):
        client = _FakeClient(_avif_fixture(1440, 2560))

        dimensions = await probe_image_dimensions(
            client,
            "https://img.komiku.org/chapter/1.avif",
        )

        self.assertEqual(dimensions, (1440, 2560))
        self.assertEqual(client.headers["Range"], "bytes=0-524287")

    async def test_probe_uses_scrapling_fallback_for_cdnkomiku_403(self):
        client = _FakeClient(b"cloudflare response", status_code=403)
        image_url = "https://cdnkomiku.xyz/chapter/1.JPEG"
        fallback_response = httpx.Response(
            200,
            headers={"content-type": "image/jpeg"},
            content=_jpeg_fixture(720, 1280),
            request=httpx.Request("GET", image_url),
        )
        fallback_result = ImageProxyFetchResult(
            response=fallback_response,
            url=image_url,
            content_type="image/jpeg",
        )

        with patch(
            "app.services.image_service._fetch_image_via_scrapling",
            new=AsyncMock(return_value=fallback_result),
        ) as fetch_fallback:
            dimensions = await probe_image_dimensions(client, image_url)

        self.assertEqual(dimensions, (720, 1280))
        fetch_fallback.assert_awaited_once_with(image_url)

    async def test_probe_uses_scrapling_fallback_for_cdn_voratoon_404(self):
        client = _FakeClient(b"not found", status_code=404)
        image_url = "https://cdn.voratoon.com/wp-content/img/K/page.jpg"
        fallback_response = httpx.Response(
            200,
            headers={"content-type": "image/jpeg"},
            content=_jpeg_fixture(800, 1200),
            request=httpx.Request("GET", image_url),
        )
        fallback_result = ImageProxyFetchResult(
            response=fallback_response,
            url=image_url,
            content_type="image/jpeg",
        )

        with patch(
            "app.services.image_service._fetch_image_via_scrapling",
            new=AsyncMock(return_value=fallback_result),
        ) as fetch_fallback:
            dimensions = await probe_image_dimensions(client, image_url)

        self.assertEqual(dimensions, (800, 1200))
        fetch_fallback.assert_awaited_once_with(image_url)


if __name__ == "__main__":
    unittest.main()
