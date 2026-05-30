# Flutter Backend Integration

Panduan integrasi Flutter dengan backend TonzToon. Base path backend adalah `/api/v1`.

## Base URL

Contoh lokal:

```text
http://10.0.2.2:8000/api/v1
```

Gunakan `10.0.2.2` untuk Android emulator, `127.0.0.1` untuk iOS simulator, dan IP LAN mesin backend untuk device fisik.

Flutter membaca base URL dari:

```bash
--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

## Auth Lifecycle

1. Register: `POST /auth/register`
2. Login email/password: `POST /auth/login`
3. Login Google native: `POST /auth/google`
4. Simpan `access_token`, `refresh_token`, dan `expires_at` di secure storage.
5. Kirim `Authorization: Bearer <access_token>` ke endpoint user-scoped.
6. Saat app boot, panggil `GET /auth/me`, lalu `GET /auth/profile`.
7. Saat token hampir expired atau request mendapat `401`, panggil `POST /auth/refresh`, simpan token baru, lalu retry request.
8. Saat logout, clear state lokal dan panggil `POST /auth/logout` secara best effort.

## Endpoint Auth

### Register

`POST /api/v1/auth/register`

Request:

```json
{
  "email": "reader@example.com",
  "password": "securePassword123",
  "display_name": "Tony Reader",
  "username": "tony_reader",
  "email_redirect_to": "tonztoon://auth/callback"
}
```

Response dapat berisi `session: null` jika email confirmation aktif. Jika session tersedia, simpan token seperti login biasa.

### Login

`POST /api/v1/auth/login`

Request saat ini memakai `identifier`, bukan hanya `email`, agar username/email bisa diarahkan oleh service auth.

```json
{
  "identifier": "reader@example.com",
  "password": "securePassword123"
}
```

Response:

```json
{
  "user": {
    "id": "11111111-1111-1111-1111-111111111111",
    "email": "reader@example.com",
    "role": "authenticated",
    "app_metadata": {
      "provider": "email",
      "providers": ["email"]
    },
    "user_metadata": {
      "display_name": "Tony Reader"
    },
    "created_at": "2026-05-27T00:00:00.000000+00:00",
    "last_sign_in_at": "2026-05-27T00:05:00.000000+00:00",
    "email_confirmed_at": "2026-05-27T00:00:00.000000+00:00",
    "phone": null,
    "is_anonymous": false
  },
  "session": {
    "access_token": "<jwt>",
    "refresh_token": "<refresh_token>",
    "token_type": "bearer",
    "expires_in": 3600,
    "expires_at": 1770003600
  },
  "email_confirmation_required": false,
  "message": "Authentication successful."
}
```

### Google Login

`POST /api/v1/auth/google`

Request:

```json
{
  "id_token": "<google_id_token>",
  "access_token": "<optional_google_access_token>",
  "nonce": null
}
```

Flutter memakai package `google_sign_in` untuk mengambil token Google, lalu backend menukarnya ke Supabase Auth dan memastikan `public.profiles` tersedia.

### Me

`GET /api/v1/auth/me`

Headers:

```http
Authorization: Bearer <access_token>
```

Response berisi claim bearer token yang sudah tervalidasi:

```json
{
  "user_id": "11111111-1111-1111-1111-111111111111",
  "email": "reader@example.com",
  "role": "authenticated",
  "audience": "authenticated",
  "issuer": "https://your-project-ref.supabase.co/auth/v1",
  "expires_at": 1770003600,
  "issued_at": 1770000000,
  "session_id": "22222222-2222-2222-2222-222222222222",
  "is_anonymous": false,
  "raw_claims": {}
}
```

### Profile

`GET /api/v1/auth/profile`

`PATCH /api/v1/auth/profile`

Patch request:

```json
{
  "username": "tony_reader",
  "display_name": "Tony Reader",
  "avatar_url": "https://cdn.example/avatar.png"
}
```

Upload avatar:

```http
POST /api/v1/auth/profile/avatar
Content-Type: multipart/form-data
Authorization: Bearer <access_token>
```

Field file: `file`. Backend mengoptimalkan gambar dan menyimpan URL ke profile.

### Password dan Email Callback

| Endpoint | Fungsi |
|---|---|
| `POST /auth/password/forgot` | Kirim email recovery |
| `POST /auth/password/recovery/verify` | Verifikasi `token_hash` recovery dari callback |
| `POST /auth/email/verify` | Verifikasi signup dari callback |
| `POST /auth/password/update` | Update password memakai bearer token recovery |

Deep link Flutter yang didukung router:

| Path | Fungsi |
|---|---|
| `/auth/callback` dan `/callback` | Email verification atau callback auth |
| `/auth/reset-password` dan `/reset-password` | Reset password |

### Refresh

`POST /api/v1/auth/refresh`

```json
{
  "refresh_token": "<refresh_token>"
}
```

### Security

`GET /api/v1/auth/security`

Dipakai settings screen untuk menampilkan email, status verifikasi, provider, info password, dan sesi aktif.

### Logout

`POST /api/v1/auth/logout`

Header bearer wajib. Flutter saat ini melakukan logout lokal lebih dulu, lalu revoke server session secara best effort.

## Library Flow

### Setelah Login Sukses

1. Restore session dengan `GET /auth/me`.
2. Ambil profile dengan `GET /auth/profile`.
3. Ambil summary dengan `GET /library/summary`.
4. Ambil reader preferences dengan `GET /library/reader-preferences`.
5. Jika ada data guest, tampilkan dialog migrasi dan kirim snapshot ke `POST /library/sync/import`.

### Comic Detail

Panggil:

```text
GET /library/state/{source_name}/comics/{comic_slug}
```

Gunakan response untuk render:

- status bookmark
- koleksi yang memuat komik
- progress terakhir
- completed chapter
- jumlah favorite scene
- status download chapter

### Continue Reading

Preview home:

```text
GET /library/progress/continue-reading?page=1&page_size=6
```

Halaman "Lanjutkan Membaca":

```text
GET /library/progress/continue-reading?page=<page>&page_size=20
```

Gunakan `page_size`, bukan `limit`. Response diurutkan dari `last_read_at` terbaru.

### Saat User Membaca

```text
PUT /library/progress/{source_name}/comics/{comic_slug}/chapters/{chapter_number}
```

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

### Bookmark

```text
GET /library/bookmarks?page=1&page_size=20
PUT /library/bookmarks/{source_name}/comics/{comic_slug}
DELETE /library/bookmarks/{source_name}/comics/{comic_slug}
```

### Collections

```text
GET /library/collections
POST /library/collections
GET /library/collections/{collection_id}
PATCH /library/collections/{collection_id}
DELETE /library/collections/{collection_id}
PUT /library/collections/{collection_id}/comics/{source_name}/{comic_slug}
DELETE /library/collections/{collection_id}/comics/{source_name}/{comic_slug}
```

### Favorite Scenes

```text
GET /library/favorite-scenes?limit=100
POST /library/favorite-scenes
DELETE /library/favorite-scenes/{scene_id}
```

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

### History

```text
GET /library/history?page=<page>&page_size=20
```

History diupdate otomatis saat progress disimpan dan menyimpan daftar chapter yang pernah dibaca. Satu komik dapat muncul beberapa kali jika chapter yang dibaca berbeda.

### Downloads

```text
GET /library/downloads?limit=200
PUT /library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}
DELETE /library/downloads/{source_name}/comics/{comic_slug}/chapters/{chapter_number}
POST /library/downloads/batch
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

Status cloud download adalah intent/status sinkronisasi. File offline tetap harus dicek di local storage device.

### Reader Preferences dan Reading Time

```text
GET /library/reader-preferences
PUT /library/reader-preferences
GET /library/reading-time
POST /library/reading-time
```

`POST /library/reading-time`:

```json
{
  "delta_seconds": 120
}
```

### Migrasi Guest

```text
POST /library/sync/import
```

Kirim snapshot bookmark, collection, progress, history per chapter, completed chapters, favorite scenes, downloads, reader preferences, dan reading time. Setelah backend sukses, cache guest dapat dibersihkan/diberi label sebagai cache akun.

## Dart/Dio Notes

`TonztoonApi` di frontend sudah menangani:

- `Authorization` header otomatis.
- refresh token dengan leeway 2 menit sebelum expired.
- retry request setelah refresh sukses.
- clear token saat refresh invalid.
- mapping error koneksi ke pesan user-friendly.

Endpoint auth yang tidak boleh memicu refresh ulang:

```text
/auth/refresh
/auth/login
```

## Error Handling

| Status | Arti umum |
|---|---|
| `400` | Payload/path tidak cocok atau request invalid |
| `401` | Bearer token kosong/invalid/expired |
| `403` | User tidak punya akses, terutama account manager |
| `404` | Source, comic, chapter, atau item library tidak ditemukan |
| `409` | Conflict, misalnya username atau nama collection sudah dipakai |
| `422` | Validasi schema gagal |
| `503` | Source komik sedang gagal diakses saat lazy-load chapter images |
