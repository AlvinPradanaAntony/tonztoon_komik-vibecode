# TonzToon Flutter App

Frontend TonzToon adalah aplikasi Flutter untuk membaca komik multi-source dari backend FastAPI. Aplikasi memakai local-first cache untuk guest dan user login, lalu menyinkronkan data akun ke backend saat token Supabase tersedia.

## Fitur Utama

- Home dengan katalog, source, latest, popular, dan preview continue reading.
- Catalog/search global dan per-source.
- Detail komik dengan bookmark, koleksi, download intent, chapter list, dan CTA lanjut baca.
- Reader vertical dan paged dengan progress tersimpan berkala.
- Library dengan tab bookmark, koleksi, favorite scenes, history, dan downloads.
- Settings untuk profil, avatar, auth/security, statistik reading time, dan migrasi data guest.
- Login email/password, Google Sign-In native, email verification, forgot/reset password, token refresh otomatis.

## Stack

| Area | Package |
|---|---|
| State | `flutter_riverpod` |
| Routing | `go_router` |
| HTTP | `dio` |
| Local data | `hive`, `hive_flutter` |
| Secure token | `flutter_secure_storage` |
| Images/cache | `cached_network_image`, `flutter_cache_manager` |
| UI helpers | `lucide_icons_flutter`, `shimmer`, `awesome_snackbar_content` |
| Offline/download support | `path_provider`, `flutter_local_notifications` |
| Media/profile | `image_picker`, `image`, `image_cropper` |
| Auth provider | `google_sign_in` |

## Struktur Penting

```text
lib/
├── main.dart
└── src/
    ├── app.dart
    ├── core/             # config, api client, storage, theme, navigation, token store
    ├── features/         # auth, catalog, comic, home, library, notifications, reader, search, settings
    ├── models/           # model JSON API dan model lokal
    ├── repositories/     # data layer remote/local
    ├── routing/          # GoRouter routes dan deep-link callback
    └── widgets/          # UI reusable lintas fitur
```

## Konfigurasi Runtime

`AppConfig.fromEnvironment()` membaca nilai dari `--dart-define`.

| Define | Fungsi |
|---|---|
| `API_BASE_URL` | Base URL backend, default lokal saat ini ada di `lib/src/core/config.dart` |
| `GOOGLE_WEB_CLIENT_ID` | Web client ID Google OAuth, dipakai sebagai `serverClientId` |
| `GOOGLE_IOS_CLIENT_ID` | iOS/macOS client ID untuk Google Sign-In native |

Contoh:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=your-ios-client-id.apps.googleusercontent.com
```

Gunakan `10.0.2.2` untuk Android emulator, `127.0.0.1` untuk iOS simulator, dan IP LAN backend untuk device fisik.

## Auth Flow

1. Register lewat `POST /auth/register` atau login lewat `POST /auth/login`.
2. Google Sign-In native mengambil token Google, lalu Flutter mengirim `id_token` ke `POST /auth/google`.
3. Backend menukar token ke Supabase Auth, memastikan profile aplikasi ada, lalu mengembalikan session.
4. Flutter menyimpan `access_token`, `refresh_token`, dan `expires_at` di secure storage.
5. `TonztoonApi` otomatis menambahkan `Authorization: Bearer <access_token>`.
6. Jika token hampir kedaluwarsa atau request menerima `401`, client mencoba `POST /auth/refresh`, menyimpan token baru, lalu retry request.
7. Logout membersihkan token, cache user-scoped, file offline akun, dan mencoba revoke session backend.

## Library dan Local-first

- Guest data disimpan lokal di Hive: progress, bookmark, koleksi, favorite scenes, download intent, reader preferences, dan reading time.
- Setelah login, repository memakai cache lokal user-scoped untuk render cepat lalu refresh dari backend.
- Progress baca di-queue dan disinkronkan ke `/library/progress/...`.
- Continue reading memakai endpoint `/library/progress/continue-reading?page=&page_size=`.
- Migrasi guest ke cloud memakai `/library/sync/import`, lalu cache guest dibersihkan setelah sukses.
- Status download di cloud adalah intent/status sinkronisasi. File offline tetap milik device lokal.

## Menjalankan dan Menguji

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Saat mengubah icon/splash:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Setup Google/Supabase

- Aktifkan Google provider di Supabase Dashboard: Authentication > Providers.
- Isi Google Client ID dan Client Secret dari Google Cloud.
- Daftarkan redirect URL Supabase Google provider di Google Cloud OAuth authorized redirect URIs.
- Untuk iOS/macOS, ikuti setup URL scheme `google_sign_in` memakai reversed iOS client ID.
- Backend tetap membutuhkan `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, dan konfigurasi Supabase Auth lainnya.
