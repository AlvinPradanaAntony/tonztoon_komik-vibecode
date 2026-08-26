# TonzToon Comic - Backend Walkthrough

Backend TonzToon adalah aplikasi FastAPI yang melayani katalog komik, auth, user library, image proxy, account manager, dan trigger scraper. Scraper CLI hidup di repo yang sama, tetapi dijalankan sebagai proses terpisah atau GitHub Actions workflow.

## 1. Tanggung Jawab Backend

Backend memiliki empat area utama:

1. REST API publik untuk katalog, source, search, genre, detail komik, dan chapter reader.
2. REST API user-scoped untuk auth Supabase, profile, avatar, library, progress, reading time, dan account manager.
3. Image proxy untuk cover/chapter/avatar agar frontend tidak bergantung langsung pada hotlink source.
4. Scraper dan script sync untuk mengisi PostgreSQL/Supabase dari source komik eksternal.

## 2. Stack

| Area | Teknologi |
|---|---|
| Web API | FastAPI, Uvicorn |
| Schema | Pydantic v2 |
| Database | PostgreSQL, SQLAlchemy async, asyncpg |
| Migration | Alembic |
| Auth | Supabase Auth, PyJWT |
| HTTP/Scraping | httpx, Scrapling |
| Images | Pillow |
| Config | pydantic-settings, python-dotenv |

## 3. Struktur Direktori

```text
backend/
├── app/
│   ├── api/
│   │   ├── deps.py          # bearer auth + dev fallback
│   │   ├── errors.py        # error payload konsisten
│   │   ├── router.py        # aggregator /api/v1
│   │   └── v1/              # auth, sources, comics, library, dll.
│   ├── models/              # Comic, Chapter, Profile, Library models
│   ├── schemas/             # Pydantic response/request models
│   ├── services/            # auth, chapter, image, library, profile, account manager
│   ├── config.py
│   ├── database.py
│   └── main.py
├── scraper/
│   ├── sources/             # source-specific scraper + registry
│   ├── main.py
│   ├── sync_full_library.py
│   ├── sync_chapter_images.py
│   ├── sync_cover_images.py
│   ├── check_pending_chapter_images.py
│   └── refresh_source_stats.py
├── scripts/
│   └── export_komiku_asia_account.py
├── alembic/
├── docs/
├── .env.example
└── requirements.txt
```

## 4. Router API

Semua route API v1 dipasang dari `app/api/router.py` dengan prefix `/api`.

| Prefix | Modul | Catatan |
|---|---|---|
| `/api/v1/comics` | `comics.py` | Katalog gabungan semua source, pagination, filter, sort |
| `/api/v1/sources` | `sources.py` | Source list, katalog per source, latest/popular, source search, detail/chapter |
| `/api/v1/search` | `search.py` | Search global title/alternative_titles |
| `/api/v1/genres` | `genres.py` | Genre list dan komik per genre |
| `/api/v1/images` | `images.py` | Proxy image streaming |
| `/api/v1/scraper` | `scraper.py` | Trigger workflow scraper |
| `/api/v1/auth` | `auth.py` | Supabase Auth, profile, avatar, password/reset/security |
| `/api/v1/library` | `library.py` | User library dan reading sync |
| `/api/v1/account-manager` | `account_manager.py` | Admin-only account management |

## 5. Auth dan Authorization

Dependency utama ada di `app/api/deps.py`.

- Request dengan `Authorization: Bearer <token>` divalidasi memakai Supabase JWT.
- `get_current_auth_user` mengembalikan `AuthenticatedUser`.
- `get_current_user_id` dipakai endpoint yang hanya butuh UUID user.
- Header `X-User-Id` hanya berlaku untuk development jika `ALLOW_DEV_USER_HEADER=true`.
- Account manager hanya bisa diakses user dalam `ADMIN_USER_IDS` atau user yang metadata-nya memiliki role admin/owner/superadmin.

Endpoint auth saat ini:

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/google`
- `POST /auth/refresh`
- `POST /auth/password/forgot`
- `POST /auth/password/recovery/verify`
- `POST /auth/email/verify`
- `POST /auth/password/update`
- `POST /auth/logout`
- `GET /auth/me`
- `GET /auth/security`
- `GET/PATCH /auth/profile`
- `POST /auth/profile/avatar`

## 6. Model Data

Core catalog:

- `comics`: metadata komik, source, feed marker latest/popular, cover URL.
- `chapters`: chapter per komik. Kolom `images` menyimpan daftar page image sebagai JSONB.
- `genres` dan asosiasi comic-genre.
- `source_stats`: statistik jumlah komik source eksternal.

User domain:

- `profiles`: public profile aplikasi.
- `reader_preferences`: mode baca default, reading direction, mark-read, binge mode.
- `user_reading_stats`: total waktu baca.
- `user_bookmarks`: bookmark komik.
- `user_collections` dan `user_collection_comics`: folder/koleksi user.
- `user_progress`: posisi baca terakhir per komik.
- `user_completed_chapters`: chapter yang sudah selesai dibaca.
- `user_history_entries`: riwayat baca per chapter.
- `user_favorite_scenes`: panel/page item favorit.
- `user_download_entries`: intent/status download offline per chapter.

## 7. Library API

Library API didesain untuk kebutuhan Flutter local-first.

- Summary: `GET /library/summary`
- Comic state: `GET /library/state/{source}/comics/{slug}`
- Continue reading: `GET /library/progress/continue-reading?page=&page_size=`
- Progress: `GET/PUT /library/progress/...`
- Bookmarks: `GET/PUT/DELETE /library/bookmarks/...`
- Collections: CRUD collection dan membership komik.
- Favorite scenes: `GET/POST/DELETE /library/favorite-scenes`
- History: `GET /library/history?page=&page_size=`
- Downloads: `GET/PUT/DELETE/POST batch /library/downloads`
- Reader preferences: `GET/PUT /library/reader-preferences`
- Reading time: `GET/POST /library/reading-time`
- Guest import: `POST /library/sync/import`
- Completed chapter batch: `POST /library/completed-chapters/batch`

Detail payload ada di `backend/docs/library_api_contract.md`.

Sinkronisasi completed chapter dari panel detail memakai satu payload batch,
bulk upsert, dan propagation set-based. Endpoint lama satu chapter tetap ada
untuk kompatibilitas, tetapi bukan jalur yang dipakai frontend chapter panel.

## 8. Chapter Image Lazy Loading

Endpoint:

```text
GET /api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number}
```

Alur:

1. Backend mencari comic/chapter berdasarkan `source_name`, `slug`, dan `chapter_number`.
2. Jika `chapters.images` sudah berisi data, response langsung dibangun.
3. Jika kosong, service chapter mencoba fetch image list dari source scraper.
4. Hasil fetch disimpan ke DB.
5. URL gambar dibungkus memakai `/api/v1/images/proxy`.
6. Backend menjadwalkan nearby prefetch untuk chapter sekitar di background.
7. Jika source gagal diakses, API mengembalikan `503`.

Untuk `komiku_asia`, jika chapter tidak ditemukan atau URL tersimpan merupakan
URL legacy, service me-refresh detail dan listing chapter melalui scraper
API-first, meng-upsert metadata/URL saja, lalu mencoba ulang fetch images untuk
chapter yang diminta. Resolver slug Komiku Asia memprioritaskan `Comic.title`
lokal sebagai query official search API, lalu memakai slug lama sebagai
fallback jika hasil title tidak cukup kuat. Source lain belum memakai repair
metadata chapter otomatis ini.

Queue `chapter_image_jobs` dan worker khusus Komiku Asia bukan lagi bagian dari
runtime. Nearby prefetch dan reader on-demand berjalan langsung melalui
`chapter_service` dan scraper source; migration penghapusan tabel harus
diterapkan setelah proses worker versi lama dihentikan.

## 9. Scraper

Scraper source diinisialisasi melalui registry di `scraper/sources/registry.py`. Implementasi source berada di `scraper/sources/`, termasuk source berbasis HTML dan helper API.

Script utama:

| Script | Fungsi |
|---|---|
| `python -m scraper.main` | Sync feed latest/popular dan pre-warm data ringan |
| `python -m scraper.sync_full_library` | Seed/refresh katalog dan detail komik |
| `python -m scraper.sync_chapter_images` | Isi/backfill `chapters.images` |
| `python -m scraper.sync_cover_images` | Download/optimasi/upload cover |
| `python -m scraper.check_pending_chapter_images` | Hitung backlog chapter tanpa images |
| `python -m scraper.refresh_source_stats` | Refresh statistik source |
| `python -m scripts.export_komiku_asia_account` | Helper export token akun Komiku Asia |

Contoh:

```bash
python -m scraper.main --source komiku_asia --max-pages 5
python -m scraper.sync_full_library --source komiku_asia --mode validate --start 1 --max 20
python -m scraper.sync_chapter_images --selection random --batch-size 10 --limit 20
python -m scraper.sync_cover_images --limit 500
python -m scraper.check_pending_chapter_images --json-only
```

## 10. Environment

Mulai dari `.env.example`.

```bash
cd backend
copy .env.example .env
```

Variable penting:

- `DATABASE_URL`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_JWT_AUDIENCE`
- `SUPABASE_JWT_ISSUER`
- `SUPABASE_JWT_SECRET`
- `SUPABASE_COVER_BUCKET`
- `SUPABASE_AVATAR_BUCKET`
- `SUPABASE_AUTH_REDIRECT_URL`
- `ADMIN_USER_IDS`
- `ALLOW_DEV_USER_HEADER`
- `GITHUB_PAT`
- `GITHUB_REPO_OWNER`
- `GITHUB_REPO_NAME`
- `GITHUB_WORKFLOW_FILE`
- `KOMIKU_ASIA_ACCESS_TOKEN`

## 11. Menjalankan Lokal

```bash
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload
```

Swagger:

```text
http://127.0.0.1:8000/docs
```

Health check:

```text
GET /
```

## 12. Catatan Pengembangan

- Gunakan migration Alembic saat mengubah model SQLAlchemy.
- Jangan menaruh secret di repo.
- Hindari menjalankan scraping berat di proses API; pakai CLI atau GitHub Actions.
- `chapters.images` adalah JSONB dan sengaja tidak dinormalisasi ke tabel page-image.
- Response image publik sebaiknya memakai proxy URL backend agar hotlink protection source tidak bocor ke client.
- Endpoint user-scoped harus memakai bearer token; fallback header dev hanya untuk testing lokal.
