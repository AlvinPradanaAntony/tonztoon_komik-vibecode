# Tonztoon Library API Contract

Kontrak backend sementara untuk fase frontend sebelum integrasi auth Supabase penuh.

## Auth

- Semua endpoint user-library sekarang menerima `Authorization: Bearer <supabase_access_token>`
- Fallback `X-User-Id: <uuid>` hanya dipakai untuk development lokal jika `ALLOW_DEV_USER_HEADER=true`

## Endpoint inti

- `GET /api/v1/library/summary`
  - counts library, continue reading, recent history, collections, reader preferences
- `GET /api/v1/library/state/{source_name}/comics/{comic_slug}`
  - state CTA comic detail: bookmark, collections, progress, favorite count, downloads

## Progress & Continue Reading

- `GET /api/v1/library/progress/continue-reading`
- `GET /api/v1/library/progress/{source_name}/comics/{comic_slug}`
- `PUT /api/v1/library/progress/{source_name}/comics/{comic_slug}/chapters/{chapter_number}`

Payload `PUT progress`:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201,
  "reading_mode": "vertical",
  "scroll_offset": 1824.5,
  "page_index": null,
  "last_read_page_item_index": 18,
  "total_page_items": 80,
  "is_completed": false
}
```

## Bookmarks

- `GET /api/v1/library/bookmarks`
- `PUT /api/v1/library/bookmarks/{source_name}/comics/{comic_slug}`
- `DELETE /api/v1/library/bookmarks/{source_name}/comics/{comic_slug}`

## Collections

- `GET /api/v1/library/collections`
- `POST /api/v1/library/collections`
- `GET /api/v1/library/collections/{collection_id}`
- `PATCH /api/v1/library/collections/{collection_id}`
- `DELETE /api/v1/library/collections/{collection_id}`
- `PUT /api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}`
- `DELETE /api/v1/library/collections/{collection_id}/comics/{source_name}/{comic_slug}`

## Favorite Scenes

- `GET /api/v1/library/favorite-scenes`
- `POST /api/v1/library/favorite-scenes`
- `DELETE /api/v1/library/favorite-scenes/{scene_id}`

Payload `POST favorite scene`:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201,
  "page_item_index": 7,
  "image_url": "https://cdn.example/image.jpg",
  "note": "panel favorit"
}
```

## History

- `GET /api/v1/library/history`
- history diupdate otomatis saat endpoint progress dipanggil

## Downloads / Offline Wishlist

- `GET /api/v1/library/downloads`
- `PUT /api/v1/library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}`
- `DELETE /api/v1/library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}`
- `POST /api/v1/library/downloads/batch`

Catatan:
- tabel backend menyimpan intent/status sinkronisasi per chapter
- file offline tetap lokal di device
- frontend tidak boleh menganggap status `completed` di cloud berarti file tersedia di device lain

## Reader Preferences

- `GET /api/v1/library/reader-preferences`
- `PUT /api/v1/library/reader-preferences`

## One-time Migration

- `POST /api/v1/library/sync/import`
- dipakai untuk upload snapshot local guest -> cloud setelah login pertama
