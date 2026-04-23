# Flutter Backend Integration

Panduan singkat untuk tim Flutter agar bisa langsung hookup ke backend auth + library Tonztoon.

## Base URL

Contoh:

```text
http://10.0.2.2:8000/api/v1
```

Untuk Android emulator gunakan `10.0.2.2`, untuk iOS simulator biasanya `127.0.0.1` atau IP LAN mesin backend.

## Auth flow

1. User register ke backend `POST /auth/register`
2. User login ke backend `POST /auth/login`
3. Simpan `access_token` dan `refresh_token`
4. Kirim `Authorization: Bearer <access_token>` ke semua endpoint `/library/*`
5. Saat app boot, verifikasi token dengan `GET /auth/me`
6. Ambil profile aplikasi dengan `GET /auth/profile`
6. Jika access token expired, refresh lewat `POST /auth/refresh`
7. Saat logout, panggil `POST /auth/logout` lalu hapus token lokal

## Endpoint auth

### Register

`POST /api/v1/auth/register`

Request:

```json
{
  "email": "reader@example.com",
  "password": "securePassword123",
  "display_name": "Tony Reader",
  "email_redirect_to": "myapp://auth/callback"
}
```

Response jika email confirmation aktif:

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
    "created_at": "2026-04-23T12:00:00.000000+00:00",
    "last_sign_in_at": null,
    "email_confirmed_at": null,
    "phone": null,
    "is_anonymous": false
  },
  "session": null,
  "email_confirmation_required": true,
  "message": "Email confirmation required before sign in."
}
```

Response jika signup langsung memberi session:

```json
{
  "user": {
    "id": "11111111-1111-1111-1111-111111111111",
    "email": "reader@example.com",
    "role": "authenticated",
    "app_metadata": {},
    "user_metadata": {},
    "created_at": "2026-04-23T12:00:00.000000+00:00",
    "last_sign_in_at": "2026-04-23T12:00:00.000000+00:00",
    "email_confirmed_at": "2026-04-23T12:00:00.000000+00:00",
    "phone": null,
    "is_anonymous": false
  },
  "session": {
    "access_token": "<jwt>",
    "refresh_token": "<refresh_token>",
    "token_type": "bearer",
    "expires_in": 3600,
    "expires_at": 1770000000
  },
  "email_confirmation_required": false,
  "message": "Authentication successful."
}
```

### Login

`POST /api/v1/auth/login`

Request:

```json
{
  "email": "reader@example.com",
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
    "created_at": "2026-04-23T12:00:00.000000+00:00",
    "last_sign_in_at": "2026-04-23T12:05:00.000000+00:00",
    "email_confirmed_at": "2026-04-23T12:00:00.000000+00:00",
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

### Me

`GET /api/v1/auth/me`

Headers:

```http
Authorization: Bearer <access_token>
```

Response:

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

Headers:

```http
Authorization: Bearer <access_token>
```

Response:

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "username": "tony_reader",
  "display_name": "Tony Reader",
  "avatar_url": null,
  "onboarding_completed": false,
  "created_at": "2026-04-23T12:00:00.000000+00:00",
  "updated_at": "2026-04-23T12:00:00.000000+00:00"
}
```

`PATCH /api/v1/auth/profile`

Request:

```json
{
  "username": "tony_reader",
  "display_name": "Tony Reader",
  "avatar_url": "https://cdn.example/avatar.png",
  "onboarding_completed": true
}
```

### Refresh

`POST /api/v1/auth/refresh`

Request:

```json
{
  "refresh_token": "<refresh_token>"
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
    "created_at": "2026-04-23T12:00:00.000000+00:00",
    "last_sign_in_at": "2026-04-23T12:05:00.000000+00:00",
    "email_confirmed_at": "2026-04-23T12:00:00.000000+00:00",
    "phone": null,
    "is_anonymous": false
  },
  "session": {
    "access_token": "<new_jwt>",
    "refresh_token": "<new_refresh_token>",
    "token_type": "bearer",
    "expires_in": 3600,
    "expires_at": 1770007200
  },
  "email_confirmation_required": false,
  "message": "Authentication successful."
}
```

### Logout

`POST /api/v1/auth/logout`

Headers:

```http
Authorization: Bearer <access_token>
```

Response:

```json
{
  "success": true,
  "message": "Session revoked successfully."
}
```

## Library flow yang direkomendasikan

### Setelah login sukses

1. Panggil `GET /library/summary`
2. Panggil `GET /auth/profile`
3. Panggil `GET /library/reader-preferences`
4. Saat buka comic detail, panggil `GET /library/state/{source_name}/comics/{comic_slug}`

### Saat user membaca

Panggil:

`PUT /library/progress/{source_name}/comics/{comic_slug}/chapters/{chapter_number}`

Request:

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

### Saat user bookmark

`PUT /library/bookmarks/{source_name}/comics/{comic_slug}`

### Saat user save favorite scene

`POST /library/favorite-scenes`

Request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_number": 201,
  "page_item_index": 7,
  "image_url": "https://cdn.example/panel-7.jpg",
  "note": "panel favorit"
}
```

### Saat user enqueue download batch

`POST /library/downloads/batch`

Request:

```json
{
  "source_name": "komiku_asia",
  "comic_slug": "solo-leveling",
  "chapter_numbers": [201, 200, 199],
  "status": "pending",
  "source_device_id": "android-pixel-7"
}
```

## Dart example

Contoh sederhana dengan `http` package:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class TonztoonApi {
  TonztoonApi(this.baseUrl);

  final String baseUrl;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception(response.body);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getLibrarySummary(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/library/summary'),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode >= 400) {
      throw Exception(response.body);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refreshSession(String refreshToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'refresh_token': refreshToken,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception(response.body);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> logout(String accessToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode >= 400) {
      throw Exception(response.body);
    }
  }
}
```

## Error handling yang perlu diperhatikan

- `400`: payload invalid atau register gagal
- `401`: login gagal / refresh gagal / bearer token invalid / expired
- `404`: source, comic, chapter, atau resource library tidak ditemukan
- `409`: conflict, mis. nama collection sudah ada
- `409`: username profile sudah dipakai user lain
- `503`: source komik sedang gagal diakses

## Catatan implementasi Flutter

- Simpan `access_token` dan `refresh_token` di secure storage
- Saat menerima `401`, coba `POST /auth/refresh` menggunakan refresh token terakhir
- Jika refresh sukses, simpan pasangan token baru lalu retry request awal
- Jika refresh gagal, anggap session habis, hapus token lokal, lalu arahkan ke login
- Saat logout, panggil `POST /auth/logout` lalu hapus token lokal
- Jangan menganggap `downloads.status=completed` di cloud berarti file offline ada di device lain

## Recommended lifecycle

1. Login/Register
2. Simpan `access_token` + `refresh_token`
3. Panggil endpoint backend dengan bearer token
4. Jika `401`, jalankan refresh
5. Jika refresh sukses, retry request
6. Jika refresh gagal, force relogin
7. Saat logout, revoke session lalu clear secure storage
