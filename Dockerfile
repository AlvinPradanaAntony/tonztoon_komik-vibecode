FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=/home/user/.cache/ms-playwright

# Instal dependensi sistem untuk browser headless (Scrapling/Camoufox/Playwright)
# dan buat non-root user (best practice Hugging Face Spaces)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        # Dependensi Playwright/Camoufox browser headless
        libnss3 \
        libnspr4 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libdbus-1-3 \
        libxkbcommon0 \
        libatspi2.0-0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
        libgl1 \
        libglib2.0-0 \
        fonts-liberation \
        # Virtual display — diperlukan oleh Scrapling AsyncStealthySession
        xvfb \
        xauth \
    && useradd -m -u 1000 user \
    && rm -rf /var/lib/apt/lists/*

# Set up HOME directory untuk non-root user (Best practice Hugging Face)
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR $HOME/app

COPY backend/requirements.txt ./requirements.txt
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Instal browser dan dependensi OS saat masih root. `scrapling install` menjalankan
# `playwright install-deps chromium`, yang membutuhkan akses apt tanpa prompt su.
# KomikuAsiaScraper memakai `real_chrome=True`, jadi instal Google Chrome juga.
RUN scrapling install \
    && python -m playwright install chrome \
    && chown -R user:user /home/user/.cache

USER user

# Salin kode dengan chown agar user punya akses baca/tulis penuh
COPY --chown=user backend ./

EXPOSE 7860

# xvfb-run menyediakan virtual display agar browser headless bisa berjalan
# di container tanpa GPU/display fisik
CMD ["sh", "-c", "xvfb-run -a -s '-screen 0 1366x768x24' uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-7860}"]
