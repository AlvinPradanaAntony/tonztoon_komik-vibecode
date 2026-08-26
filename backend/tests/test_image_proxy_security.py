import socket
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import httpx

from app.config import settings
from app.services.image_service import (
    ImageProxyPayloadTooLargeError,
    ImageProxyValidationError,
    get_proxy_headers,
    is_allowed_image_content_type,
    open_validated_image_proxy_response,
    validate_image_response_headers,
    validate_proxy_image_dns,
    validate_proxy_image_url,
)


class ImageProxySecurityTests(unittest.IsolatedAsyncioTestCase):
    def test_allowed_source_host_is_accepted(self):
        self.assertEqual(
            validate_proxy_image_url("https://cdnkomiku.xyz/images/page-1.jpg"),
            "https://cdnkomiku.xyz/images/page-1.jpg",
        )
        self.assertEqual(
            validate_proxy_image_url(
                "https://thumbnail.komiku.to/uploads/manga/absolute-sword-sense/"
                "manga_thumbnail-Manhwa-Absolute-Sword-Sense.jpg?w=500"
            ),
            "https://thumbnail.komiku.to/uploads/manga/absolute-sword-sense/"
            "manga_thumbnail-Manhwa-Absolute-Sword-Sense.jpg?w=500",
        )
        self.assertEqual(
            validate_proxy_image_url(
                "https://cdn.komikcast.fit/wp-content/img/C/Chronicles_of_the_Reincarnated_Demon_God/001/00.jpg"
            ),
            "https://cdn.komikcast.fit/wp-content/img/C/Chronicles_of_the_Reincarnated_Demon_God/001/00.jpg",
        )

    def test_komikcast_cdn_referer_header(self):
        headers = get_proxy_headers(
            "https://cdn.komikcast.fit/wp-content/img/C/Chronicles_of_the_Reincarnated_Demon_God/001/00.jpg"
        )
        self.assertEqual(headers.get("Referer"), "https://v1.komikcast.fit/")

    def test_komiku_thumbnail_referer_header(self):
        headers = get_proxy_headers(
            "https://thumbnail.komiku.to/uploads/manga/absolute-sword-sense/cover.jpg"
        )
        self.assertEqual(headers.get("Referer"), "https://komiku.org/")

    def test_private_ip_literal_is_rejected(self):
        with self.assertRaises(ImageProxyValidationError):
            validate_proxy_image_url("http://127.0.0.1/private.jpg")

    def test_non_http_scheme_is_rejected(self):
        with self.assertRaises(ImageProxyValidationError):
            validate_proxy_image_url("file:///etc/passwd")

    def test_non_standard_port_is_rejected(self):
        with self.assertRaises(ImageProxyValidationError):
            validate_proxy_image_url("https://cdnkomiku.xyz:8080/page.jpg")

    async def test_dns_private_address_is_rejected(self):
        fake_dns = [
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                6,
                "",
                ("10.0.0.5", 443),
            )
        ]
        with patch("app.services.image_service.socket.getaddrinfo", return_value=fake_dns):
            with self.assertRaises(ImageProxyValidationError):
                await validate_proxy_image_dns("https://cdnkomiku.xyz/a.jpg")

    def test_content_type_must_be_image(self):
        self.assertTrue(is_allowed_image_content_type("image/webp; charset=binary"))
        self.assertFalse(is_allowed_image_content_type("text/html"))
        with self.assertRaises(ImageProxyValidationError):
            validate_image_response_headers({"content-type": "text/html"})

    def test_content_length_above_limit_is_rejected(self):
        with self.assertRaises(ImageProxyPayloadTooLargeError):
            validate_image_response_headers(
                {
                    "content-type": "image/jpeg",
                    "content-length": str(settings.IMAGE_PROXY_MAX_BYTES + 1),
                }
            )

    async def test_redirect_target_is_revalidated(self):
        async def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(
                302,
                headers={"location": "http://127.0.0.1/private.jpg"},
            )

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            with patch(
                "app.services.image_service.validate_proxy_image_dns",
                new=AsyncMock(),
            ):
                with self.assertRaises(ImageProxyValidationError):
                    await open_validated_image_proxy_response(
                        "https://cdnkomiku.xyz/start.jpg",
                        client=client,
                    )
        finally:
            await client.aclose()

    async def test_non_image_success_response_is_rejected(self):
        async def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200,
                headers={"content-type": "text/html"},
                content=b"<html></html>",
            )

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            with patch(
                "app.services.image_service.validate_proxy_image_dns",
                new=AsyncMock(),
            ):
                with self.assertRaises(ImageProxyValidationError):
                    await open_validated_image_proxy_response(
                        "https://cdnkomiku.xyz/page.jpg",
                        client=client,
                    )
        finally:
            await client.aclose()

    async def test_cdnkomiku_403_retries_with_scrapling_fetcher(self):
        async def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(
                403,
                headers={"content-type": "text/html"},
                content=b"cloudflare challenge",
            )

        scrapling_page = SimpleNamespace(
            status=200,
            headers={"content-type": "image/jpeg"},
            body=b"\xff\xd8\xff\xe0jpeg",
        )
        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        image_url = (
            "https://cdnkomiku.xyz/wp-content/9/sample/chapter-00/page.JPEG"
        )
        try:
            with (
                patch(
                    "app.services.image_service.validate_proxy_image_dns",
                    new=AsyncMock(),
                ),
                patch(
                    "scrapling.fetchers.Fetcher.get",
                    return_value=scrapling_page,
                ) as fetcher_get,
            ):
                result = await open_validated_image_proxy_response(
                    image_url,
                    client=client,
                )
                self.assertEqual(result.response.status_code, 200)
                self.assertEqual(await result.response.aread(), b"\xff\xd8\xff\xe0jpeg")
                fetcher_get.assert_called_once()
        finally:
            await client.aclose()


if __name__ == "__main__":
    unittest.main()
