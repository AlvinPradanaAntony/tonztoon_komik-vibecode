"""
Helper parsing bersama untuk scraper sources.
"""

import logging
import re
from typing import Any
from urllib.parse import urljoin


logger = logging.getLogger("scraper.common")


class ScraperCommonMixin:
    """Kumpulan helper parsing agar scraper sources lebih konsisten."""

    _KNOWN_TYPES = ("manhwa", "manhua", "manga", "comic")
    _COUNT_SUFFIXES = {
        "k": 1_000,
        "m": 1_000_000,
        "b": 1_000_000_000,
    }
    _CHAPTER_PATTERNS = (
        r"(?:chapter|chap|ch)\.?\s*([0-9]+(?:[.\-][0-9]+)?)",
        r"\b([0-9]+(?:[.\-][0-9]+)?)\b",
    )
    _COMIC_TEXT_LIMITS = {
        "author": 300,
        "artist": 300,
        "status": 50,
        "type": 50,
    }

    BASE_URL = ""
    SOURCE_NAME = ""

    def _clean_text(self, text: str | None) -> str:
        """Rapikan whitespace berlebih dari text HTML."""
        if not text:
            return ""
        return re.sub(r"\s+", " ", text).strip()

    def _make_slug(self, title: str) -> str:
        """Bangun slug stabil dari judul komik."""
        slug = title.lower().strip()
        slug = re.sub(r"[^a-z0-9\s-]", "", slug)
        slug = re.sub(r"[\s-]+", "-", slug)
        return slug.strip("-")

    def _parse_chapter_number(self, text: str | None) -> float:
        """Extract nomor chapter dari berbagai format judul chapter."""
        cleaned = self._clean_text(text)
        if not cleaned:
            return 0.0

        for pattern in self._CHAPTER_PATTERNS:
            match = re.search(pattern, cleaned, re.IGNORECASE)
            if not match:
                continue

            try:
                return float(match.group(1).replace("-", "."))
            except ValueError:
                continue

        return 0.0

    def _parse_rating(self, text: str | None) -> float | None:
        """Parse nilai rating numerik jika tersedia."""
        cleaned = self._clean_text(text)
        if not cleaned:
            return None

        try:
            return self._normalize_rating_value(float(cleaned))
        except ValueError:
            return None

    def _normalize_rating_value(self, value: float | None) -> float | None:
        """
        Normalisasi rating lintas source ke skala 0-10.

        Beberapa source/mirror kadang mengembalikan angka seperti `73`
        untuk merepresentasikan `7.3/10`.
        """
        if value is None:
            return None
        if value < 0:
            return None
        if value <= 10:
            return round(value, 2)
        if value <= 100:
            return round(value / 10, 2)
        return None

    def _parse_compact_number(self, text: str | None) -> int | None:
        """Parse angka singkat seperti `238.5k` menjadi integer penuh."""
        cleaned = self._clean_text(text).lower().replace(",", "")
        if not cleaned:
            return None

        match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([kmb])?", cleaned)
        if not match:
            return None

        try:
            value = float(match.group(1))
        except ValueError:
            return None

        suffix = match.group(2)
        multiplier = self._COUNT_SUFFIXES.get(suffix, 1)
        return int(value * multiplier)

    def _parse_type_from_text(self, text: str | None) -> str | None:
        """Deteksi tipe komik dari text atau daftar class."""
        cleaned = self._clean_text(text).lower()
        for comic_type in self._KNOWN_TYPES:
            if comic_type in cleaned:
                return comic_type
        return None

    def _normalize_status(self, text: str | None) -> str | None:
        """Normalisasi status komik lintas source ke nilai yang lebih konsisten."""
        cleaned = self._clean_text(text).lower()
        if not cleaned:
            return None

        normalized = cleaned.replace("-", " ")
        if normalized in {"on going", "ongoing"} or "on going" in normalized:
            return "ongoing"
        if any(keyword in normalized for keyword in ("completed", "complete", "end", "ended")):
            return "completed"
        if "hiatus" in normalized:
            return "hiatus"
        return cleaned

    def _resolve_url(self, href: str | None) -> str:
        """Gabungkan href relatif ke BASE_URL scraper."""
        return urljoin(self.BASE_URL, href or "")

    def _extract_image_url(
        self,
        element,
        *,
        attrs: tuple[str, ...] = ("src", "data-src"),
        invalid_substrings: tuple[str, ...] = ("lazy.jpg",),
    ) -> str | None:
        """Ambil URL gambar yang paling valid dari element HTML."""
        if element is None:
            return None

        for attr in attrs:
            value = element.attrib.get(attr)
            if not value:
                continue
            if any(marker in value for marker in invalid_substrings):
                continue
            return value

        for attr in attrs:
            value = element.attrib.get(attr)
            if value:
                return value

        return None

    def _truncate_text(
        self,
        value: str | None,
        *,
        field_name: str,
        title: str,
    ) -> str | None:
        """Rapikan text dan potong aman sesuai limit field DB/schema."""
        cleaned = self._clean_text(value)
        if not cleaned:
            return None

        limit = self._COMIC_TEXT_LIMITS[field_name]
        if len(cleaned) <= limit:
            return cleaned

        logger.warning(
            "Field %s melebihi batas untuk '%s' (%s > %s); nilai dipotong sebelum upsert.",
            field_name,
            title,
            len(cleaned),
            limit,
        )
        return cleaned[:limit].rstrip(" ,;/|-")

    def _looks_like_title_list(self, value: str | None) -> bool:
        """
        Deteksi heuristik ketika field `author` sebenarnya berisi daftar
        judul alternatif dari source yang salah label.
        """
        cleaned = self._clean_text(value)
        if not cleaned:
            return False

        segments = [segment.strip() for segment in cleaned.split(",") if segment.strip()]
        if len(segments) < 4:
            return False

        phrase_like_segments = sum(1 for segment in segments if len(segment.split()) >= 4)
        return phrase_like_segments >= max(3, len(segments) // 2)

    def _normalize_comic_payload_fields(
        self,
        *,
        title: str,
        extra_fields: dict[str, Any],
    ) -> dict[str, Any]:
        """Normalisasi payload komik agar aman divalidasi dan di-upsert."""
        normalized = dict(extra_fields)

        alternative_titles = self._clean_text(normalized.get("alternative_titles")) or None
        author = self._clean_text(normalized.get("author")) or None

        if author and not alternative_titles and self._looks_like_title_list(author):
            logger.warning(
                "Field author tampak berisi daftar judul alternatif untuk '%s'; dipindah ke alternative_titles.",
                title,
            )
            alternative_titles = author
            author = None

        normalized["alternative_titles"] = alternative_titles
        normalized["author"] = self._truncate_text(author, field_name="author", title=title)
        normalized["artist"] = self._truncate_text(
            normalized.get("artist"),
            field_name="artist",
            title=title,
        )
        normalized["status"] = self._truncate_text(
            normalized.get("status"),
            field_name="status",
            title=title,
        )
        normalized["type"] = self._truncate_text(
            normalized.get("type"),
            field_name="type",
            title=title,
        )
        normalized["rating"] = self._normalize_rating_value(normalized.get("rating"))

        return normalized

    def _build_comic_payload(
        self,
        *,
        title: str,
        source_url: str,
        **extra_fields: Any,
    ) -> dict[str, Any]:
        """Payload komik dasar yang konsisten antar scraper."""
        normalized_fields = self._normalize_comic_payload_fields(
            title=title,
            extra_fields=extra_fields,
        )
        return {
            "title": title,
            "slug": self._make_slug(title),
            "source_url": source_url,
            "source_name": self.SOURCE_NAME,
            **normalized_fields,
        }

    def _build_chapter_payload(
        self,
        *,
        chapter_number: float,
        title: str,
        source_url: str,
        release_date,
    ) -> dict[str, Any]:
        """Payload chapter dasar yang konsisten antar scraper."""
        return {
            "chapter_number": chapter_number,
            "title": title,
            "source_url": source_url,
            "release_date": release_date,
        }

    def _build_metadata_patch(
        self,
        detail: dict[str, Any],
        *,
        fields: set[str] | None = None,
    ) -> dict[str, Any]:
        """Ambil subset metadata komik dari payload detail lengkap."""
        patch = {
            "title": detail.get("title"),
            "alternative_titles": detail.get("alternative_titles"),
            "cover_image_url": detail.get("cover_image_url"),
            "author": detail.get("author"),
            "artist": detail.get("artist"),
            "status": detail.get("status"),
            "type": detail.get("type"),
            "synopsis": detail.get("synopsis"),
            "rating": detail.get("rating"),
            "total_view": detail.get("total_view"),
            "source_url": detail.get("source_url"),
        }
        if not fields:
            return patch
        return {key: value for key, value in patch.items() if key in fields}
