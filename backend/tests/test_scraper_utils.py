import io
import logging
import threading
import unittest
from unittest.mock import patch

from scraper import utils


class _FakeProgress:
    def __init__(self):
        self.clear_calls = 0
        self.render_calls = 0

    def clear_line(self):
        self.clear_calls += 1

    def render(self):
        self.render_calls += 1


class RealtimeConsoleHandlerTests(unittest.TestCase):
    def test_worker_thread_logging_does_not_touch_async_live_progress(self):
        stream = io.StringIO()
        handler = utils.RealtimeConsoleHandler(stream)
        progress = _FakeProgress()
        record = logging.LogRecord(
            name="scrapling",
            level=logging.INFO,
            pathname=__file__,
            lineno=1,
            msg="Fetched (200) <GET https://example.test>",
            args=(),
            exc_info=None,
        )
        errors = []

        def emit_from_worker():
            try:
                handler.emit(record)
            except Exception as exc:  # pragma: no cover - assertion below
                errors.append(exc)

        with patch.object(utils, "_active_live_progress", progress):
            worker = threading.Thread(target=emit_from_worker)
            worker.start()
            worker.join()

        self.assertEqual(errors, [])
        self.assertEqual(progress.clear_calls, 0)
        self.assertEqual(progress.render_calls, 0)
        self.assertIn("Fetched (200)", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
