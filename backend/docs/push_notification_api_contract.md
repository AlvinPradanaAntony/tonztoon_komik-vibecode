# Push Notification API Contract

Kontrak ini mendefinisikan API backend untuk remote push notification Android
melalui Firebase Cloud Messaging (FCM). Frontend Android mengirim token device
ke endpoint ini. iOS tetap memakai local notification.

Base URL frontend mengarah ke prefix API v1, misalnya:

```text
http://localhost:8000/api/v1
```

Semua endpoint user-scoped wajib memakai:

```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

## Register Device Token

Mendaftarkan FCM registration token milik user aktif. Frontend memanggil endpoint
ini saat notifikasi diaktifkan, setelah login/restore session, dan saat token FCM
berubah.

```http
POST /notifications/devices
```

Request body:

```json
{
  "provider": "fcm",
  "platform": "android",
  "token": "fcm_registration_token",
  "user_id": "b7c8d9e0-1111-2222-3333-444455556666"
}
```

Field:

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `provider` | string | yes | Saat ini hanya `fcm`. |
| `platform` | string | yes | Saat ini hanya `android`. |
| `token` | string | yes | FCM registration token dari `FirebaseMessaging.getToken()`. |
| `user_id` | UUID string | yes | Harus sama dengan user dari bearer token, atau backend boleh mengabaikan body ini dan memakai user auth. |

Response `200 OK`:

```json
{
  "id": "device-token-row-id",
  "provider": "fcm",
  "platform": "android",
  "token_hash": "sha256-token-hash",
  "active": true,
  "created_at": "2026-06-03T11:00:00Z",
  "updated_at": "2026-06-03T11:00:00Z",
  "last_seen_at": "2026-06-03T11:00:00Z"
}
```

Recommended behavior:

- Upsert by `(provider, token_hash)` or raw token if stored directly.
- Associate token with authenticated user.
- Mark `active = true` and update `last_seen_at`.
- If the same token moved to another user, reassign to the current user.
- Store raw token encrypted, or store token hash plus encrypted token. Backend
  still needs the raw token to send FCM.

Errors:

| Status | Meaning |
| --- | --- |
| `400` | Invalid provider/platform/token. |
| `401` | Missing or invalid bearer token. |
| `403` | `user_id` does not match authenticated user, if backend validates it. |
| `422` | Malformed JSON/body validation failed. |

## Unregister Device Token

Menonaktifkan token saat user mematikan notifikasi atau logout.

```http
DELETE /notifications/devices
```

Request body:

```json
{
  "provider": "fcm",
  "platform": "android",
  "token": "fcm_registration_token"
}
```

Response `204 No Content`.

Recommended behavior:

- Resolve token to authenticated user.
- Mark `active = false`.
- Do not delete row physically unless retention policy memang mengharuskan.
- Endpoint harus idempotent. Token yang tidak ditemukan tetap boleh return
  `204 No Content`.

Errors:

| Status | Meaning |
| --- | --- |
| `401` | Missing or invalid bearer token. |
| `422` | Malformed JSON/body validation failed. |

## Chapter Update Event

Bagian ini untuk backend/scraper. Jika scraper berjalan dalam proses backend,
event ini bisa dipanggil sebagai service internal tanpa HTTP. Jika scraper
berjalan dari job eksternal, gunakan endpoint internal berikut.

Implementasi saat ini sudah menghubungkan `python -m scraper.main` ke service
internal. Event dikirim setelah data comic/chapter berhasil di-commit, hanya
untuk komik yang sudah pernah ada di DB dan memiliki nomor chapter terbaru yang
lebih tinggi dari data sebelumnya. Full library/backfill tidak memicu push agar
tidak mengirim notifikasi massal saat seeding.

```http
POST /notifications/events/chapter-update
```

Auth untuk endpoint internal:

- Wajib protected, misalnya admin bearer token, service token, atau API key
  internal.
- Jangan expose endpoint ini sebagai public unauthenticated route.

Request body:

```json
{
  "source_name": "komikcast",
  "comic_slug": "example-slug",
  "comic_title": "Example Comic",
  "latest_chapter_number": 12,
  "latest_chapter_title": "Chapter 12",
  "release_date": "2026-06-03T10:30:00Z",
  "event_id": "chapter:komikcast:example-slug:12"
}
```

Response `202 Accepted`:

```json
{
  "event_id": "chapter:komikcast:example-slug:12",
  "matched_users": 42,
  "target_devices": 55,
  "queued_messages": 55,
  "duplicate": false
}
```

Recommended behavior:

- Idempotent by `event_id`.
- Kirim hanya ke user dengan `profiles.push_notifications_enabled = true`.
- Kirim hanya ke token device `active = true`.
- Jika ada sistem bookmark/follow, targetkan user yang mengikuti komik itu.
  Jika belum ada follow list, backend boleh mengirim ke semua user opt-in.
- Simpan audit event agar scraper tidak mengirim ulang chapter yang sama.

## FCM Message Payload

Backend mengirim FCM HTTP v1 message ke token Android. Gunakan notification
payload agar Android system bisa menampilkan notifikasi saat app background atau
terminated. Gunakan data payload untuk route dan metadata yang dibaca frontend.

FCM message:

```json
{
  "message": {
    "token": "fcm_registration_token",
    "notification": {
      "title": "Chapter baru tersedia",
      "body": "Example Comic Chapter 12 baru saja rilis."
    },
    "data": {
      "id": "chapter:komikcast:example-slug:12",
      "kind": "chapter_update",
      "category": "Update",
      "route": "/comic/komikcast/example-slug",
      "source_name": "komikcast",
      "comic_slug": "example-slug",
      "chapter_number": "12"
    },
    "android": {
      "priority": "HIGH",
      "notification": {
        "channel_id": "comic_updates",
        "click_action": "FLUTTER_NOTIFICATION_CLICK"
      }
    }
  }
}
```

Frontend membaca route dari salah satu key berikut:

1. `route`
2. `action_route`
3. `actionRoute`
4. `click_action_route`

Route harus dimulai dengan `/`. Contoh route valid:

```text
/notifications
/comic/komikcast/example-slug
/reader/komikcast/example-slug/12
/library?tab=downloads
```

## Token Failure Handling

Saat mengirim FCM, backend harus menangani error token:

| FCM error | Backend action |
| --- | --- |
| `UNREGISTERED` | Mark token inactive. |
| `INVALID_ARGUMENT` untuk token invalid | Mark token inactive. |
| Auth/credential error | Jangan mark token inactive, perbaiki server credential. |
| Rate limit/transient error | Retry dengan backoff. |

## Minimal Database Shape

Contoh tabel device token:

```sql
create table user_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  provider text not null check (provider in ('fcm')),
  platform text not null check (platform in ('android')),
  token text not null,
  token_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz,
  unique (provider, token_hash)
);
```

Contoh tabel event:

```sql
create table push_notification_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  kind text not null,
  source_name text,
  comic_slug text,
  chapter_number numeric,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

## Frontend Compatibility Checklist

- Android package Firebase harus sesuai `com.tonzdev.tonztoon`.
- File `frontend/android/app/google-services.json` harus tersedia sebelum build
  release Android.
- Backend endpoint register/unregister harus tersedia di bawah `/api/v1`.
- Push notification setting tetap memakai `PATCH /auth/profile` dengan field
  `push_notifications_enabled`.
- Backend harus mengirim `notification.title`, `notification.body`, dan data
  `route` agar tap notifikasi membuka halaman yang tepat.

## Backend Environment

Implementasi backend membaca konfigurasi berikut:

| Env | Required | Description |
| --- | --- | --- |
| `PUSH_EVENT_API_KEY` | recommended | API key internal untuk `POST /notifications/events/chapter-update` via header `X-Push-Event-Key`. Jika kosong, endpoint event hanya bisa dipakai admin bearer token. |
| `FCM_PROJECT_ID` | optional | Firebase project ID. Jika kosong, backend memakai `project_id` dari service account JSON. |
| `FCM_SERVICE_ACCOUNT_JSON` | one of two | Raw JSON service account Firebase untuk FCM HTTP v1. |
| `FCM_SERVICE_ACCOUNT_FILE` | one of two | Path file service account Firebase. Dipakai jika `FCM_SERVICE_ACCOUNT_JSON` kosong. |

Jika service account belum dikonfigurasi, endpoint event tetap mencatat event dan
return `202`, tetapi `queued_messages` akan `0` karena FCM tidak dikirim.
