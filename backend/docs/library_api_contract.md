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
    "bookmark_status_counts": {
      "ongoing": 5,
      "completed": 3,
      "hiatus": 2
    },
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
    "auto_scroll_enabled": false,
    "auto_scroll_speed": 1.0,
    "updated_at": "2026-05-27T00:00:00Z"
  }
}
```

### `GET /api/v1/library/state/{source_name}/comics/{comic_slug}`

State terpadu untuk comic detail: bookmark, koleksi terpilih, progress, history, completed chapters, jumlah favorite scene, dan status download.
Bookmark terhubung tetap menghasilkan `bookmarked: true`, dengan
`bookmark_relation: "linked"` dan `bookmark_origin` menunjuk bookmark utama.

Response field utama:

```json
{
  "comic": {},
  "bookmarked": true,
  "bookmark_relation": "direct",
  "bookmark_origin": {},
  "linked_comics": [],
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

### Sinkronisasi Completed Chapter dari Chapter Panel

Endpoint berikut dipakai tombol **Sync status read** pada panel listing chapter:

```text
POST /api/v1/library/completed-chapters/batch
```

Endpoint ini membutuhkan bearer token dan menerima maksimal `5.000` item per
request. Request bersifat idempotent; item duplikat dalam payload diabaikan.

Request:

```json
{
  "chapters": [
    {
      "source_name": "komiku_asia",
      "comic_slug": "solo-leveling",
      "chapter_number": 150.0
    },
    {
      "source_name": "komikcast",
      "comic_slug": "solo-leveling",
      "chapter_number": 150.0
    }
  ]
}
```

Response:

```json
{
  "completed_synced": 2,
  "completed_propagated": 0
}
```

`completed_synced` adalah jumlah chapter yang berhasil di-resolve dan
di-upsert untuk user. `completed_propagated` adalah jumlah status tambahan
yang ditandai pada komik lain dalam grup bookmark multi-source.

Backend melakukan resolve, upsert, propagation, dan commit secara batch/set-
based. Jumlah query dan transaksi tidak bertambah satu per chapter. Endpoint
lama `POST /library/completed-chapters` tetap dipertahankan untuk kompatibilitas
caller satu chapter, tetapi frontend chapter panel menggunakan endpoint batch.

Endpoint ini hanya mengubah status completed. Progress posisi, scroll, history,
dan continue reading tidak ikut diubah.

## Bookmarks

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/api/v1/library/bookmarks?page=1&page_size=20&type=&status=&sort=` | `BookmarkResponse[]` |
| `PUT` | `/api/v1/library/bookmarks/{source_name}/comics/{comic_slug}` | `BookmarkResponse` |
| `PATCH` | `/api/v1/library/bookmarks/{source_name}/comics/{comic_slug}/status` | `204 No Content` |
| `DELETE` | `/api/v1/library/bookmarks/{source_name}/comics/{comic_slug}` | `{ "deleted": true }` |

Pagination bookmark memakai `page` dan `page_size` dengan batas `1..100`.
Setiap `BookmarkResponse` juga memiliki `linked_comics`, yaitu source alternatif
yang sudah dikonfirmasi user.
Urutan response menempatkan bookmark dengan chapter baru yang belum dibaca di
posisi teratas berdasarkan source utama bookmark.

Filter opsional: `type` (`manga`, `manhwa`, `manhua`) dan `status`
(`ongoing`, `completed`, `hiatus`). Beberapa nilai dapat dikirim dengan pemisah
koma dan diperlakukan sebagai pilihan OR. Nilai `status` mengikuti override
bookmark reader bila tersedia. Pilihan `sort`: `latest`, `az`, dan `za`.
Tanpa parameter `sort`, seluruh bookmark tetap ditampilkan dengan urutan normal.
`sort=latest` mengutamakan bookmark dengan `hasNewChapter=true` berdasarkan
source utama dan hanya mengembalikan bookmark tersebut; bookmark tanpa chapter
baru tidak ditampilkan. Jika sama, urutan dilanjutkan dari bookmark yang dibuat
lebih baru.

`PATCH .../status` menerima `{ "status": "ongoing" | "completed" | "hiatus" }`.
Endpoint ini hanya mengonfirmasi perubahan dengan `204 No Content`; klien
memperbarui item bookmark, ringkasan pustaka, dan detail komik dari state-nya.
Untuk role `reader`, status disimpan sebagai override pada bookmark milik user.
Untuk role `admin` (role claim Supabase atau `ADMIN_USER_IDS`), status diterapkan
ke seluruh `Comic` dalam grup multi-source bookmark dan override bookmark lama
dibersihkan. Saat scraper menyimpan chapter baru dari salah satu source dalam grup,
status seluruh source terhubung dan bookmark terkait otomatis kembali menjadi
`ongoing`.

## Relasi Bookmark Multi-source

Pemindaian tidak dijalankan ketika bookmark dibuat. Frontend memanggil endpoint
berikut hanya setelah user menekan tombol pencarian source lain:

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/v1/library/bookmark-links/candidates?offset=0&page_size=5` | Cari kandidat berdasarkan kemiripan judul dan alias dalam batch |
| `POST` | `/api/v1/library/bookmark-links` | Simpan kandidat dan kembalikan grup yang perlu disinkronkan |
| `POST` | `/api/v1/library/bookmark-links/completed-sync` | Sinkronkan maksimal 10 grup bookmark per transaksi |
| `DELETE` | `/api/v1/library/bookmark-links/{source_name}/comics/{comic_slug}` | Putuskan satu source alternatif |

Request `POST`:

```json
{
  "links": [
    {
      "bookmark": {
        "source_name": "komiku_asia",
        "comic_slug": "solo-leveling"
      },
      "linked_comic": {
        "source_name": "komikcast",
        "comic_slug": "solo-leveling"
      },
      "confidence": 0.96
    }
  ]
}
```

Sinkronisasi chapter menjadi bagian dari konfirmasi bookmark multi-source dan
hanya mencocokkan `chapter_number` yang sama. Relasi disimpan pada tingkat
pasangan komik, bukan sebagai row mapping untuk setiap chapter. Setelah relasi
disimpan, client mengirim `completion_sync_bookmark_ids` ke endpoint completed
sync dalam batch kecil. Setiap batch memakai operasi set-based dan transaksi
terpisah, sehingga pustaka dengan ribuan completed chapter tidak menahan satu
request atau satu transaksi panjang.
Setiap batch memakai `INSERT ... SELECT ... ON CONFLICT DO NOTHING`, sehingga
jumlah query tidak bertambah mengikuti jumlah chapter completed dalam grup.
Setelah terhubung, `is_completed=true` pada endpoint
progress atau import completed chapter langsung menandai seluruh grup yang
memiliki nomor chapter sama. Contoh `Utama ↔ A` dan `Utama ↔ B`: selesai dari
A akan menandai Utama dan B dalam satu aksi, tanpa propagasi rekursif.
Posisi scroll, halaman, history, dan continue reading tidak disalin.

Response penyimpanan relasi:

```json
{
  "linked_total": 1,
  "completed_propagated": 0,
  "completion_sync_bookmark_ids": [123]
}
```

Frontend membagi ID tersebut menjadi maksimal lima grup per request
`completed-sync`, lalu menjumlahkan `completed_propagated` dari setiap batch.
Relasi kandidat juga dikirim maksimal lima item per request dan di-retry secara
idempotent saat timeout. UI menampilkan progress determinate terpisah untuk
fase penyimpanan relasi dan sinkronisasi completed.

Pemindaian kandidat memakai operator trigram yang dapat menggunakan indeks GIN.
Frontend me-retry batch kandidat maksimal tiga kali dan menyimpan offset serta
kandidat yang sudah terkumpul selama instance aplikasi masih hidup. Jika retry
tetap gagal, pemindaian berikutnya melanjutkan offset terakhir, bukan kembali
ke bookmark pertama.
Hasil scan yang sudah selesai juga dipertahankan sampai seluruh kandidat
terpilih berhasil dihubungkan. Karena itu timeout saat fase penghubungan tidak
memaksa frontend memindai seluruh bookmark lagi.

## Collections

| Method | Endpoint | Fungsi |
|---|---|---|
| `GET` | `/api/v1/library/collections` | List ringkasan koleksi |
| `POST` | `/api/v1/library/collections` | Buat koleksi |
| `GET` | `/api/v1/library/collections/{collection_id}` | Detail koleksi beserta item |
| `PATCH` | `/api/v1/library/collections/{collection_id}` | Rename koleksi |
| `DELETE` | `/api/v1/library/collections/{collection_id}` | Hapus koleksi |
| `PUT` | `/api/v1/library/comics/{source_name}/{comic_slug}/collections` | Set seluruh koleksi komik (`204`) |
| `PUT` | `/api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}` | Tambahkan komik (`204`) |
| `DELETE` | `/api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}` | Hapus komik dari koleksi (`204`) |

Create/rename payload:

```json
{
  "name": "Favorit Mingguan"
}
```

Nama dinormalisasi dengan trim dan collapse whitespace. Duplikasi nama per user menghasilkan `409`.

Halaman detail memakai endpoint set membership dalam satu transaksi:

```json
{
  "collection_ids": [3, 8, 12]
}
```

Payload kosong menghapus komik dari seluruh koleksi user. Ketiga endpoint membership
mengembalikan `204 No Content`; detail dan daftar koleksi dimuat ulang oleh client.

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
  "default_binge_mode": false,
  "auto_scroll_enabled": false,
  "auto_scroll_speed": 1.0
}
```

Nilai valid:

| Field | Nilai |
|---|---|
| `default_reading_mode` | `vertical`, `paged` |
| `reading_direction` | `ltr`, `rtl` |
| `auto_scroll_speed` | `0.5` sampai `1.5` |

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
  "bookmark_links": [],
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
  "bookmark_links_upserted": 0,
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
