FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Buat user terlebih dahulu
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
    && useradd -m -u 1000 user \
    && rm -rf /var/lib/apt/lists/*

# Set up HOME directory untuk non-root user (Best practice Hugging Face)
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR $HOME/app

COPY backend/requirements.txt ./requirements.txt
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Salin kode dengan chown agar user punya akses baca/tulis penuh
COPY --chown=user backend ./

USER user

EXPOSE 7860

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-7860}"]
