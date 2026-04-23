"""
Tonztoon Komik — Scraper Shared Utilities

Utilitas bersama yang dipakai oleh beberapa CLI script scraper
(main.py, sync_full_library.py, sync_chapter_images.py) agar
tidak terduplikasi di masing-masing file.

Berisi:
- random_delay / backoff_delay — anti-blocking delay
- _format_elapsed_duration — format durasi human-readable
- resolve_log_path / configure_logging — logging setup
- GracefulShutdown — graceful SIGINT/SIGTERM handler
"""

import asyncio
from contextlib import suppress
import logging
import random
import re
import signal
import shutil
import sys
from pathlib import Path

DEFAULT_LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
LIVE_PROGRESS_BAR_WIDTH = 24
LIVE_PROGRESS_FRAMES = ("|", "/", "-", "\\")
LIVE_PROGRESS_REFRESH_SEC = 0.15
SCRAPLING_NOISY_MESSAGE_MARKERS = (
    "no cloudflare challenge found.",
    "looks like cloudflare captcha is still present, solving again",
)
_active_live_progress = None

# ═══════════════════════════════════════════════════════════════════
# TEXT & FORMATTING OPS
# ═══════════════════════════════════════════════════════════════════

def clean_text(text: str | None) -> str:
    """Rapikan whitespace berlebih dari text HTML/String."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def _supports_live_progress(stream) -> bool:
    """Aktifkan live progress hanya pada terminal interaktif."""
    return bool(stream) and hasattr(stream, "isatty") and stream.isatty()


# ═══════════════════════════════════════════════════════════════════
# DELAY & BACKOFF
# ═══════════════════════════════════════════════════════════════════

_utils_logger = logging.getLogger("scraper.utils")


async def random_delay(min_sec: float, max_sec: float, label: str = "") -> None:
    """Jeda acak antara min_sec dan max_sec detik."""
    delay = random.uniform(min_sec, max_sec)
    if label:
        _utils_logger.info("  ⏳ %s: menunggu %.1fs...", label, delay)
    await asyncio.sleep(delay)


async def backoff_delay(
    attempt: int,
    label: str = "",
    *,
    base: float = 2.0,
    maximum: float = 120.0,
) -> None:
    """
    Exponential backoff dengan jitter ±25%.

    Contoh (base=2): 2s → 4s → 8s → 16s → ... (maks `maximum`).
    """
    delay = min(base * (2 ** attempt), maximum)
    jitter = delay * random.uniform(-0.25, 0.25)
    delay = max(1.0, delay + jitter)
    _utils_logger.warning(
        "  ⏳ Backoff (attempt %s): %s — menunggu %.1fs...",
        attempt + 1,
        label,
        delay,
    )
    await asyncio.sleep(delay)


# ═══════════════════════════════════════════════════════════════════
# FORMAT HELPERS
# ═══════════════════════════════════════════════════════════════════


def format_elapsed_duration(elapsed_seconds: float) -> str:
    """Format durasi menjadi bentuk natural + total detik."""
    total_seconds = max(0, int(round(elapsed_seconds)))
    minutes, seconds = divmod(total_seconds, 60)
    hours, minutes = divmod(minutes, 60)

    parts: list[str] = []
    if hours:
        parts.append(f"{hours} jam")
    if minutes:
        parts.append(f"{minutes} menit")
    if seconds or not parts:
        parts.append(f"{seconds} detik")

    return f"{' '.join(parts)} ({total_seconds} detik)"


# ═══════════════════════════════════════════════════════════════════
# LOGGING SETUP
# ═══════════════════════════════════════════════════════════════════


def resolve_log_path(
    log_file: str | Path | None,
    *,
    default_filename: str | Path = "scraper.log",
) -> Path:
    """Resolve path log ke folder backend/logs kecuali path absolut."""
    log_path = Path(log_file or default_filename).expanduser()
    if not log_path.is_absolute():
        log_path = DEFAULT_LOG_DIR / log_path
    return log_path


def configure_logging(
    log_file: str | Path | None = None,
    *,
    default_filename: str | Path = "scraper.log",
    stdout_handler: logging.Handler | None = None,
) -> None:
    """
    Konfigurasi logger root ke stdout dan file UTF-8 di backend/logs.

    Parameters:
        log_file: Path file log kustom. Jika None, pakai default_filename.
        default_filename: Nama file log default (relatif ke backend/logs/).
        stdout_handler: Handler stdout kustom (misalnya RealtimeConsoleHandler
                        untuk live progress bar). Jika None, pakai StreamHandler biasa.
    """
    console_handler = stdout_handler or logging.StreamHandler(sys.stdout)
    handlers: list[logging.Handler] = [console_handler]

    log_path = resolve_log_path(log_file, default_filename=default_filename)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handlers.append(logging.FileHandler(log_path, mode="w", encoding="utf-8"))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=handlers,
        force=True,
    )


def configure_external_loggers() -> None:
    """Rapikan logger eksternal agar tidak berebut terminal dengan progress bar."""
    scrapling_logger = logging.getLogger("scrapling")
    if scrapling_logger.handlers:
        scrapling_logger.handlers.clear()
    scrapling_logger.propagate = True


class RealtimeConsoleHandler(logging.StreamHandler):
    """Handler stdout yang bisa hidup berdampingan dengan live progress bar."""

    def emit(self, record: logging.LogRecord) -> None:
        if self._should_skip_console_record(record):
            return
        progress = _active_live_progress
        if progress is not None:
            progress.clear_line()
        super().emit(record)
        if progress is not None:
            progress.render()

    @staticmethod
    def _should_skip_console_record(record: logging.LogRecord) -> bool:
        """Sembunyikan noise yang tidak menambah sinyal di CLI realtime."""
        message = record.getMessage().lower()
        if record.name == "scraper.komiku_asia" and message.startswith("stealth fetch:"):
            return _active_live_progress is not None
        if record.name.startswith("scrapling"):
            return any(marker in message for marker in SCRAPLING_NOISY_MESSAGE_MARKERS)
        return False


class CliLiveProgress:
    """Progress bar satu baris untuk fase yang berpotensi terlihat freeze di CLI."""

    def __init__(
        self,
        *,
        label: str,
        total_steps: int,
        stream=None,
    ) -> None:
        self.stream = stream or sys.stdout
        self.label = label
        self.total_steps = max(total_steps, 1)
        self.current_step = 0
        self.detail = "menyiapkan"
        self.started_at = asyncio.get_running_loop().time()
        self.frame_index = 0
        self.running = False
        self.enabled = _supports_live_progress(self.stream)
        self._task: asyncio.Task | None = None
        self._last_line_length = 0

    def start(self) -> None:
        """Mulai animasi progress bar realtime."""
        global _active_live_progress
        if not self.enabled:
            return
        self.running = True
        _active_live_progress = self
        self.render()
        self._task = asyncio.create_task(self._animate())

    def set_detail(self, detail: str) -> None:
        """Perbarui detail aktif tanpa menaikkan progress."""
        self.detail = detail
        self.render()

    def advance(self, detail: str) -> None:
        """Naikkan progress satu langkah dan render ulang."""
        self.current_step = min(self.current_step + 1, self.total_steps)
        self.detail = detail
        self.render()

    def clear_line(self) -> None:
        """Hapus baris progress aktif dari terminal."""
        if not self.enabled or self._last_line_length == 0:
            return
        self.stream.write("\r" + (" " * self._last_line_length) + "\r")
        self.stream.flush()

    def render(self) -> None:
        """Render progress bar ke satu baris terminal."""
        if not self.enabled or not self.running:
            return

        progress_ratio = self.current_step / self.total_steps
        filled = int(progress_ratio * LIVE_PROGRESS_BAR_WIDTH)
        bar = "#" * filled + "-" * (LIVE_PROGRESS_BAR_WIDTH - filled)
        elapsed = asyncio.get_running_loop().time() - self.started_at
        frame = LIVE_PROGRESS_FRAMES[self.frame_index % len(LIVE_PROGRESS_FRAMES)]
        text = (
            f"  {frame} [{bar}] {self.current_step}/{self.total_steps} "
            f"{self.label} | {self.detail} | {elapsed:5.1f}s"
        )
        terminal_width = shutil.get_terminal_size((120, 20)).columns
        if len(text) > terminal_width - 1:
            text = text[: max(terminal_width - 4, 1)] + "..."

        padded = text
        if len(text) < self._last_line_length:
            padded += " " * (self._last_line_length - len(text))

        self.stream.write("\r" + padded)
        self.stream.flush()
        self._last_line_length = len(padded)

    async def stop(self) -> None:
        """Hentikan animasi dan bersihkan baris progress."""
        global _active_live_progress
        if not self.enabled:
            return

        self.running = False
        if self._task is not None:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
            self._task = None

        self.clear_line()
        self._last_line_length = 0
        if _active_live_progress is self:
            _active_live_progress = None

    async def _animate(self) -> None:
        """Animasi spinner kecil agar fase lambat tetap terlihat hidup."""
        while self.running:
            self.frame_index = (self.frame_index + 1) % len(LIVE_PROGRESS_FRAMES)
            self.render()
            await asyncio.sleep(LIVE_PROGRESS_REFRESH_SEC)


# ═══════════════════════════════════════════════════════════════════
# GRACEFUL SHUTDOWN
# ═══════════════════════════════════════════════════════════════════


class GracefulShutdown:
    """
    Enkapsulasi graceful shutdown handler untuk CLI scripts.

    Usage:
        shutdown = GracefulShutdown()
        shutdown.install()  # pasang signal handler

        while not shutdown.requested:
            ...  # main loop
    """

    def __init__(self) -> None:
        self.requested: bool = False
        self._logger = logging.getLogger("scraper.shutdown")

    def install(self) -> None:
        """Pasang handler SIGINT dan SIGTERM."""
        signal.signal(signal.SIGINT, self._handler)
        signal.signal(signal.SIGTERM, self._handler)

    def _handler(self, signum, frame) -> None:
        if self.requested:
            self._logger.warning("⛔ Paksa berhenti!")
            sys.exit(1)
        self.requested = True
        self._logger.warning(
            "\n🛑 Shutdown diminta. Menyelesaikan proses aktif "
            "dan menyimpan checkpoint..."
        )
