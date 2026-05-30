# TonzToon Library API Contract

Kontrak endpoint `GET/POST/PUT/PATCH/DELETE /api/v1/library/*` untuk fitur library, progress baca, dan sinkronisasi data akun. Dokumen ini mengikuti implementasi saat ini di `backend/app/api/v1/library.py` dan schema di `backend/app/schemas/library.py`.

## Auth

Semua endpoint library membutuhkan user aktif.

```http
Authorization: Bearer <supabase_access_token>
```

Fallback development:

```http
X-User-Id: <uuid>
```

Fallback `X-User-Id` hanya aktif jika `ALLOW_DEV_USER_HEADER=true`. Jangan aktifkan fallback ini di environment shared atau production.

## Response Model Umum

`LibraryComicRef`:

```json
{
  "comic_id": 1,
  "source_name": "komiku_asia",
  "slug": "solo-leveling",
  "title": "Solo Leveling",
  "cover_image_url": "http://localhost:8000/api/v1/images/proxy?url=...",
  "author": null,
  "status": "completed",
  "type": "manhwa",
  "rating": 8.7,
  "total_view": 238500
}
```

`LibraryChapterRef`:

```json
{
  "chapter_id": 10,
  "chapter_number": 201.0,
  "title": "Chapter 201",
  "release_date": null,
  "total_images": 80
}
```

Chapter number bertipe `float` di API dan path. Frontend boleh mengirim `201` atau `201.0`; backend membandingkan payload dan path dengan toleransi kecil.

## Summary dan Comic State

### `GET /api/v1/library/summary`

Mengembalikan ringkasan untuk home/library/settings.

Response:

```json
{
  "counts": {
    "bookmarks": 12,
    "collections": 3,
    "favorite_scenes": 5,
    "history": 20,
    "downloads": 8,
    "continue_reading": 4
  },
  "reading_time_seconds": 3600,
  "continue_reading": [],
  "recent_history": [],
  "collections": [],
  "reader_preferences": {
    "default_reading_mode": "vertical",
    "reading_direction": "ltr",
    "mark_read_on_complete": false,
    "default_binge_mode": false,
    "updated_at": "2026-05-27T00:00:00Z"
  }
}
```

### `GET /api/v1/library/state/{source_name}/comics/{comic_slug}`

State terpadu untuk comic detail: bookmark, koleksi terpilih, progress, history, completed chapters, jumlah favorite scene, dan status download.

Response field utama:

```json
{
  "comic": {},
  "bookmarked": true,
  "collections": [],
  "progress": null,
  "history": null,
  "completed_chapter_numbers": [1.0, 2.0],
  "favorite_scene_count": 0,
  "download_status_counts": {
    "pending": 2,
    "completed": 1
  },
  "download_entries": []
}
```

## Progress dan Continue Reading

### `GET /api/v1/library/progress/continue-reading?page=1&page_size=20`

Query:

| Nama | Default | Batas | Catatan |
|---|---:|---:|---|
| `page` | `1` | `>=1` | Offset dihitung `(page - 1) * page_size` |
| `page_size` | `20` | `1..100` | Home memakai `6`; halaman continue reading memakai `20` |

Response berupa list `ProgressResponse`, diurutkan dari `last_read_at` terbaru. Jika jumlah item kurang dari `page_size`, frontend dapat menghentikan infinite scroll.

### `GET /api/v1/library/progress/{source_name}/comics/{comic_slug}`

Mengembalikan `ProgressResponse` atau `null` jika user belum punya progress untuk komik tersebut.

### `PUT /api/v1/library/progress/{source_name}/comics/{comic_slug}/chapters/{chapter_number}`

Upsert progress baca terakhir per komik dan mirror ke history per chapter. Jika `is_completed=true`, backend juga mencatat completed chapter.

Request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201.0,
  "reading_mode": "vertical",
  "scroll_offset": 1824.5,
  "page_index": null,
  "last_read_page_item_index": 18,
  "total_page_items": 80,
  "is_completed": false
}
```

`reading_mode` hanya menerima `"vertical"` atau `"paged"`.

## Bookmarks

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/api/v1/library/bookmarks?page=1&page_size=20` | `BookmarkResponse[]` |
| `PUT` | `/api/v1/library/bookmarks/{source_name}/comics/{comic_slug}` | `BookmarkResponse` |
| `DELETE` | `/api/v1/library/bookmarks/{source_name}/comics/{comic_slug}` | `{ "deleted": true }` |

Pagination bookmark memakai `page` dan `page_size` dengan batas `1..100`.

## Collections

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/v1/library/collections` | List ringkasan koleksi |
| `POST` | `/api/v1/library/collections` | Buat koleksi |
| `GET` | `/api/v1/library/collections/{collection_id}` | Detail koleksi beserta item |
| `PATCH` | `/api/v1/library/collections/{collection_id}` | Rename koleksi |
| `DELETE` | `/api/v1/library/collections/{collection_id}` | Hapus koleksi |
| `PUT` | `/api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}` | Tambahkan komik |
| `DELETE` | `/api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}` | Hapus komik dari koleksi |

Create/rename payload:

```json
{
  "name": "Favorit Mingguan"
}
```

Nama dinormalisasi dengan trim dan collapse whitespace. Duplikasi nama per user menghasilkan `409`.

## Favorite Scenes

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/api/v1/library/favorite-scenes?limit=100` | `FavoriteSceneResponse[]` |
| `POST` | `/api/v1/library/favorite-scenes` | `FavoriteSceneResponse` |
| `DELETE` | `/api/v1/library/favorite-scenes/{scene_id}` | `{ "deleted": true }` |

`limit` default `100`, maksimum `200`.

Request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201.0,
  "page_item_index": 7,
  "image_url": "https://cdn.example/panel-7.jpg",
  "note": "panel favorit"
}
```

Favorite scene unik per `(user_id, chapter_id, page_item_index)`, sehingga `POST` dapat berperilaku sebagai upsert.

## History

### `GET /api/v1/library/history?page=1&page_size=20`

Mengembalikan list `HistoryItemResponse` per chapter yang pernah dibaca, diurutkan dari `last_read_at` terbaru. Pagination memakai `page` dan `page_size`, dengan `page_size` default `20` dan maksimum `50`.

History diupdate otomatis saat endpoint `PUT progress` dipanggil. Berbeda dari continue reading, history dapat berisi beberapa chapter dari komik yang sama.

## Downloads / Offline Intent

Cloud download entry hanya menyimpan intent/status sinkronisasi chapter. File offline tetap lokal di device. Frontend tidak boleh menganggap status `completed` di cloud berarti file tersedia di device lain.

Status valid:

```text
pending, downloading, completed, failed, cancelled, missing
```

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/api/v1/library/downloads?limit=200` | `DownloadEntryResponse[]` |
| `PUT` | `/api/v1/library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}` | `DownloadEntryResponse` |
| `DELETE` | `/api/v1/library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}` | `{ "deleted": true }` |
| `POST` | `/api/v1/library/downloads/batch` | `DownloadBatchResponse` |

`GET downloads` menerima `limit` default `200`, maksimum `500`.

Upsert request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201.0,
  "status": "pending",
  "source_device_id": "android-pixel-7",
  "last_error": null
}
```

Batch request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_numbers": [201.0, 200.0, 199.0],
  "status": "pending",
  "source_device_id": "android-pixel-7"
}
```

Jika `chapter_numbers` kosong atau `null`, backend enqueue semua chapter komik.

## Reader Preferences

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/api/v1/library/reader-preferences` | `ReaderPreferenceResponse` |
| `PUT` | `/api/v1/library/reader-preferences` | `ReaderPreferenceResponse` |

Request:

```json
{
  "default_reading_mode": "vertical",
  "reading_direction": "ltr",
  "mark_read_on_complete": false,
  "default_binge_mode": false
}
```

Nilai valid:

| Field | Nilai |
|---|---|
| `default_reading_mode` | `vertical`, `paged` |
| `reading_direction` | `ltr`, `rtl` |

## Reading Time

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/v1/library/reading-time` | Ambil total waktu baca user |
| `POST` | `/api/v1/library/reading-time` | Tambahkan delta durasi baca |

Request `POST`:

```json
{
  "delta_seconds": 120
}
```

Response:

```json
{
  "total_reading_seconds": 3720,
  "updated_at": "2026-05-27T00:00:00Z"
}
```

## One-time Migration Guest ke Cloud

### `POST /api/v1/library/sync/import`

Dipakai setelah login pertama untuk mengunggah snapshot data guest dari Hive ke cloud.

Request:

```json
{
  "bookmarks": [
    {
      "source_name": "komiku_asia",
      "comic_slug": "solo-leveling"
    }
  ],
  "collections": [
    {
      "name": "Favorit",
      "comics": [
        {
          "source_name": "komiku_asia",
          "comic_slug": "solo-leveling"
        }
      ]
    }
  ],
  "progress": [],
  "history": [],
  "completed_chapters": [],
  "favorite_scenes": [],
  "downloads": [],
  "reader_preferences": null,
  "reading_time_seconds": 3600
}
```

Response:

```json
{
  "bookmarks_upserted": 1,
  "collections_upserted": 1,
  "collection_items_upserted": 1,
  "progress_upserted": 0,
  "history_upserted": 0,
  "completed_chapters_upserted": 0,
  "favorite_scenes_upserted": 0,
  "downloads_upserted": 0,
  "reader_preferences_updated": false,
  "reading_time_seconds_imported": 3600
}
```
