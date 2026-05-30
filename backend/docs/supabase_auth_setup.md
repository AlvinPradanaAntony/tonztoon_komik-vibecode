# Supabase Auth Setup

Dokumen ini melengkapi backend supaya siap dipakai bersama Supabase Auth, JWT validation, dan RLS.

Arsitektur user yang dipakai:

- `auth.users` untuk identitas, kredensial, session, dan provider auth
- `public.profiles` untuk data aplikasi user seperti `display_name`, `username`, `avatar_url`, dan status onboarding

Lihat juga:

- [backend/.env.example](../.env.example)
- [flutter_backend_integration.md](flutter_backend_integration.md)

## Environment variables

Tambahkan ke `.env` backend:

```env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx_or_legacy_anon_key
SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx_or_legacy_service_role_key
SUPABASE_JWT_AUDIENCE=authenticated
SUPABASE_JWT_ISSUER=https://your-project-ref.supabase.co/auth/v1

# Optional fallback untuk project legacy HS256
SUPABASE_JWT_SECRET=

# Redirect email confirmation, recovery, dan callback auth lain ke aplikasi Flutter
SUPABASE_AUTH_REDIRECT_URL=tonztoon://auth/callback

# Storage bucket untuk avatar profile
SUPABASE_AVATAR_BUCKET=avatars

# Optional local-only fallback for old testing flow
ALLOW_DEV_USER_HEADER=false

# Optional, untuk dashboard account manager.
# Isi dengan UUID Supabase Auth user admin, pisahkan koma bila lebih dari satu.
ADMIN_USER_IDS=
```

## Endpoint backend auth

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/google`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/password/forgot`
- `POST /api/v1/auth/password/recovery/verify`
- `POST /api/v1/auth/email/verify`
- `POST /api/v1/auth/password/update`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`
- `GET /api/v1/auth/security`
- `GET /api/v1/auth/profile`
- `PATCH /api/v1/auth/profile`
- `POST /api/v1/auth/profile/avatar`

`GET /api/v1/auth/me` dan semua endpoint library menerima:

```http
Authorization: Bearer <supabase_access_token>
```

`POST /api/v1/auth/google` menerima Google `id_token` dari Flutter native
`google_sign_in`, lalu backend menukarnya ke Supabase Auth melalui
`/auth/v1/token?grant_type=id_token`. Setelah session diterima, backend tetap
menjalankan bootstrap `public.profiles` seperti login email/password.

Untuk login Google, aktifkan provider Google di Supabase Dashboard
Authentication > Providers dan isi Google OAuth Client ID/Secret. Flutter hanya
perlu `GOOGLE_WEB_CLIENT_ID` dan, untuk iOS/macOS, `GOOGLE_IOS_CLIENT_ID`.

## Endpoint account manager

Dashboard statis di [admin/account-dashboard.html](../../admin/account-dashboard.html) memakai endpoint backend berikut:

- `GET /api/v1/account-manager/accounts`
- `POST /api/v1/account-manager/accounts`
- `PATCH /api/v1/account-manager/accounts/{user_id}`
- `GET /api/v1/account-manager/accounts/{user_id}/relations`
- `GET /api/v1/account-manager/accounts/{user_id}/delete-preview`
- `DELETE /api/v1/account-manager/accounts/{user_id}`

Semua endpoint tersebut wajib memakai:

```http
Authorization: Bearer <supabase_access_token_admin>
```

Akun dianggap admin bila salah satu kondisi benar:

- UUID user ada di `ADMIN_USER_IDS`
- `app_metadata.role`, `app_metadata.account_role`, atau `app_metadata.admin_role` bernilai `admin`, `owner`, atau `superadmin`
- `user_metadata.role`, `user_metadata.account_role`, atau `user_metadata.admin_role` bernilai `admin`, `owner`, atau `superadmin`

Operasi Supabase Auth Admin memakai `SUPABASE_SERVICE_ROLE_KEY` hanya di backend. Jangan pernah menaruh service role key di file HTML, Flutter, atau JavaScript browser.

Catatan perilaku dashboard:

- Status `suspended` akan mengirim `ban_duration` ke Supabase Auth sehingga akun benar-benar diblokir login.
- Status `active` dan `pending` akan melepas ban Supabase Auth bila sebelumnya user disuspend.
- Dashboard memblokir penghapusan akun admin yang sedang dipakai login agar tidak mengunci akses sendiri.

## JWT validation strategy

Backend memakai urutan berikut:

1. Verifikasi lokal via `JWKS` bila project memakai signing key asimetris.
2. Fallback ke `SUPABASE_JWT_SECRET` untuk token legacy `HS256`.
3. Jika secret tidak ada, fallback ke `GET /auth/v1/user` untuk verifikasi server-side.

Ini sengaja dibuat supaya backend tetap kompatibel dengan setup Supabase lama maupun baru.

## Session lifecycle

- `access_token` adalah JWT short-lived untuk authorize request ke backend
- `refresh_token` dipakai untuk menukar session lama menjadi pasangan token baru
- backend Tonztoon tidak menyimpan session sendiri; session source of truth tetap Supabase Auth
- endpoint `POST /api/v1/auth/refresh` meneruskan refresh token ke Supabase Auth
- endpoint `POST /api/v1/auth/logout` merevoke session saat ini melalui Supabase Auth

Catatan penting:

- refresh token pada Supabase pada dasarnya single-use dan akan diputar menjadi token baru saat refresh
- access token yang sudah terbit tidak bisa langsung "dibunuh"; ia tetap valid sampai `exp` habis
- karena itu logout merevoke refresh token/session chain, lalu client tetap harus menghapus token lokal

## Enable RLS

Jalankan file SQL ini di Supabase SQL Editor setelah migrasi Alembic:

- [supabase_rls_user_library.sql](../sql/supabase_rls_user_library.sql)

SQL tersebut:

- menambahkan relasi opsional `public.profiles -> auth.users`
- mengaktifkan `RLS` untuk seluruh tabel user-library
- mengaktifkan `RLS` untuk `public.profiles`
- membuat policy `authenticated` berbasis `auth.uid()`
- menambah foreign key ke `auth.users` bila tersedia
- membuat trigger opsional untuk bootstrap `profiles` + `reader_preferences`

## Catatan arsitektur

- Endpoint backend FastAPI tetap melakukan authorization check sendiri dari bearer token.
- RLS terutama berguna bila nanti frontend atau service lain juga mengakses tabel user-library melalui Supabase Data API / PostgREST.
- Koneksi database backend saat ini masih berupa koneksi server langsung, jadi RLS di DB adalah lapisan tambahan, bukan satu-satunya guard.
