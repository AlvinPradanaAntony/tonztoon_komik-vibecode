# Supabase Auth Setup

Dokumen ini melengkapi backend supaya siap dipakai bersama Supabase Auth, JWT validation, dan RLS.

Arsitektur user yang dipakai:

- `auth.users` untuk identitas, kredensial, session, dan provider auth
- `public.profiles` untuk data aplikasi user seperti `display_name`, `username`, `avatar_url`, dan status onboarding

Lihat juga:

- [backend/.env.example](</e:/Projek/projek_vibecode/tonztoon_komik/backend/.env.example>)
- [flutter_backend_integration.md](</e:/Projek/projek_vibecode/tonztoon_komik/backend/docs/flutter_backend_integration.md>)

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

# Optional redirect email confirmation
SUPABASE_AUTH_REDIRECT_URL=myapp://auth/callback

# Optional local-only fallback for old testing flow
ALLOW_DEV_USER_HEADER=false
```

## Endpoint backend auth

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`
- `GET /api/v1/auth/profile`
- `PATCH /api/v1/auth/profile`

`GET /api/v1/auth/me` dan semua endpoint library menerima:

```http
Authorization: Bearer <supabase_access_token>
```

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

- [supabase_rls_user_library.sql](</e:/Projek/projek_vibecode/tonztoon_komik/backend/sql/supabase_rls_user_library.sql>)

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
