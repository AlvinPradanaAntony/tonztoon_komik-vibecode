import unittest

from app.services.http_client_service import (
    get_auth_http_client,
    get_image_proxy_http_client,
    get_shared_http_client,
    shutdown_http_clients,
    startup_http_clients,
)


class HttpClientServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncTearDown(self):
        await shutdown_http_clients()

    async def test_clients_are_reused_until_shutdown(self):
        await startup_http_clients()

        shared = get_shared_http_client()
        auth = get_auth_http_client()
        image = get_image_proxy_http_client()

        self.assertIs(shared, get_shared_http_client())
        self.assertIs(auth, get_auth_http_client())
        self.assertIs(image, get_image_proxy_http_client())

        await shutdown_http_clients()

        self.assertTrue(shared.is_closed)
        self.assertTrue(auth.is_closed)
        self.assertTrue(image.is_closed)
        self.assertFalse(get_shared_http_client().is_closed)


if __name__ == "__main__":
    unittest.main()
