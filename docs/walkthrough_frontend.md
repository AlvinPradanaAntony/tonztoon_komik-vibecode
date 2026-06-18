# TonzToon Comic - Frontend Walkthrough

Frontend TonzToon adalah aplikasi Flutter untuk membaca komik multi-source dari backend FastAPI. Aplikasi saat ini berfokus pada pengalaman local-first: guest tetap bisa memakai library lokal, sedangkan user login mendapat sinkronisasi cloud melalui endpoint `/library/*`.

## 1. Stack

| Area           | Package                                                                      |
| -------------- | ---------------------------------------------------------------------------- |
| State          | `flutter_riverpod`                                                           |
| Routing        | `go_router`                                                                  |
| HTTP           | `dio`                                                                        |
| Local database | `hive`, `hive_flutter`                                                       |
| Token storage  | `flutter_secure_storage`                                                     |
| Image cache    | `cached_network_image`, `flutter_cache_manager`                              |
| UI             | `lucide_icons_flutter`, `flutter_svg`, `shimmer`, `awesome_snackbar_content` |
| Notifications  | `flutter_local_notifications`                                                |
| Files/offline  | `path_provider`                                                              |
| Profile media  | `image_picker`, `image`, `image_cropper`                                     |
| Auth provider  | `google_sign_in`                                                             |

## 2. Struktur Direktori

```text
frontend/lib/
├── main.dart
└── src/
    ├── app.dart
    ├── core/
    │   ├── api_client.dart
    │   ├── app_navigation.dart
    │   ├── app_theme.dart
    │   ├── config.dart
    │   ├── storage.dart
    │   └── token_store.dart
    ├── features/
    │   ├── auth/
    │   ├── catalog/
    │   ├── comic/
    │   ├── home/
    │   ├── library/
    │   ├── notifications/
    │   ├── onboarding/
    │   ├── reader/
    │   ├── search/
    │   ├── settings/
    │   ├── shell/
    │   └── splash/
    ├── models/
    ├── repositories/
    ├── routing/
    └── widgets/
```

## 3. App Bootstrap

`main.dart` menginisialisasi Flutter dan storage lokal, lalu menjalankan root app di `src/app.dart`.

Konfigurasi runtime ada di `src/core/config.dart`:

- `API_BASE_URL`
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`

Contoh:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

## 4. Routing

Routing terpusat di `src/routing/app_router.dart` dengan `GoRouter`.

Route utama:

| Route                                        | Screen                     |
| -------------------------------------------- | -------------------------- |
| `/splash`                                    | Splash                     |
| `/onboarding`                                | Onboarding                 |
| `/`                                          | Home                       |
| `/catalog`                                   | Full catalog               |
| `/search`                                    | Search                     |
| `/library`                                   | Library tab utama          |
| `/library?tab=collections`                   | Tab collections            |
| `/library?tab=scenes`                        | Tab favorite scenes        |
| `/library?tab=history`                       | Tab history                |
| `/library?tab=downloads`                     | Tab downloads              |
| `/library/continue-reading`                  | Continue reading full page |
| `/settings`                                  | Settings                   |
| `/auth`                                      | Auth                       |
| `/auth/forgot-password`                      | Forgot password            |
| `/auth/callback` dan `/callback`             | Email/auth callback        |
| `/auth/reset-password` dan `/reset-password` | Reset password             |
| `/notifications`                             | Notifications              |
| `/comic/:source/:slug`                       | Comic detail               |
| `/reader/:source/:slug/:chapter`             | Reader                     |

`StatefulShellRoute.indexedStack` menjaga state tab utama: home, catalog, search, library, settings.

## 5. Data Layer

Repository penting:

| Repository               | Fungsi                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------- |
| `AuthRepository`         | restore/login/register/google/refresh-aware session, profile, avatar, logout                            |
| `CatalogRepository`      | source, katalog, latest/popular, detail, chapter list                                                   |
| `ProgressRepository`     | continue reading, progress lokal, queue sync progress ke cloud                                          |
| `LibraryRepository`      | summary, bookmark, collection, favorite scene, history, downloads, preferences, reading time, migration |
| `OfflineRepository`      | file offline lokal                                                                                      |
| `NotificationRepository` | notifikasi internal sync/download                                                                       |

Provider Riverpod berada terutama di `repositories/providers.dart` dan menghubungkan UI dengan repository.

## 6. API Client dan Token Refresh

`src/core/api_client.dart` membungkus Dio.

Perilaku penting:

- Menambahkan bearer token otomatis dari secure storage.
- Refresh token jika `expires_at` tersisa kurang dari 2 menit.
- Retry request awal setelah refresh sukses saat menerima `401`.
- Membersihkan token jika refresh invalid.
- Mengubah error koneksi menjadi pesan Bahasa Indonesia yang ramah user.

Endpoint yang tidak memicu refresh ulang:

```text
/auth/refresh
/auth/login
```

## 7. Auth Flow

Flow email/password:

1. Register: `POST /auth/register`.
2. Login: `POST /auth/login` dengan `identifier` dan `password`.
3. Restore session: `GET /auth/me`, lalu `GET /auth/profile`.
4. Token disimpan sebagai `access_token`, `refresh_token`, dan `expires_at`.

Flow Google:

1. `google_sign_in` mengambil Google token native.
2. Flutter mengirim `id_token` ke `POST /auth/google`.
3. Backend menukar token ke Supabase Auth.
4. Session dipersist seperti login email/password.

Flow callback:

- `/auth/callback` dan `/callback` menerima email verification atau callback auth.
- `/auth/reset-password` dan `/reset-password` menangani recovery/reset password.

## 8. Local-first Library & Status Implementasi

Data guest tersimpan di Hive. Setelah user login, repository memakai pola sinkronisasi dengan cloud. Namun, status implementasi _local-first_ pada mode _auth_ (login) belum diterapkan di semua fitur.

Berikut rincian status penerapan _local-first_ (UI langsung diperbarui berdasarkan data lokal, API bekerja di latar) pada mode _auth_:

**Fitur dengan pendekatan Local-First:**

- **Reading Progress** (`progress_repository.dart`): Data selalu ditulis ke cache Hive. Jika _auth_, progres masuk queue untuk _sync_ API di latar. Bila _sync_ gagal, UI tetap menggunakan data lokal dengan peringatan.
- **Continue Reading** (`progress_repository.dart`): Mendapatkan _cache_ lokal _authenticated_ secara cepat, proses _refresh_ dari cloud diproses di latar belakang.
- **Reading Time** (`providers.dart`): Durasi tambahan disimpan ke _local state_, dan dikirim ke _cloud background_ sebagai _pending delta_.
- **Reader Preferences** (`library_repository.dart`): Menyimpan data persistensi lokal _Hive_ lebih dulu sebelum _sync_ API (meskipun fungsinya masih menunggu respons API untuk _return final value_).

**Fitur dengan pendekatan Server-First:**

- Bookmark (_toggle_ & daftar)
- Ringkasan Library (_Library summary_)
- Collections
- Favorite scenes
- History
- Unduhan (_Downloads wishlist_ & status)
- Aksi hapus/perbarui pustaka (_Library actions_)

*(Catatan: `getComicState()` masih mengambil dari *server* lebih dulu, lalu menggabungkannya (*merge*) dengan data progres/historis lokal sebagai *fallback* bila API gagal).*

Migrasi guest memakai `POST /library/sync/import`. Dialog migrasi menghitung data lokal seperti bookmark, collection, progress, favorite scenes, downloads, dan reading time.

## 9. Reader

Reader mendukung:

- Vertical scroll.
- Paged mode.
- Penyimpanan `scroll_offset` atau `page_index`.
- `last_read_page_item_index` dan `total_page_items` untuk resume lebih akurat.
- Sync progress ke cloud jika user login.
- Fallback local progress jika offline atau sync gagal.

Saat `is_completed=true`, backend menyimpan completed chapter dan history.

## 10. Library UI

`features/library/library_screen.dart` dan `library_shared_panes.dart` menangani:

- Bookmark list dengan pagination.
- Collections dan manajemen item.
- Favorite scenes.
- History.
- Downloads: gabungan queue aktif, file offline lokal, dan cloud download entries.

Tab dapat dibuka lewat query param:

```text
/library?tab=collections
/library?tab=scenes
/library?tab=history
/library?tab=downloads
```

## 11. Settings

Settings menggabungkan:

- Auth/profile state.
- Avatar upload.
- Security overview.
- Reader preferences.
- Reading time.
- Guest migration.
- Local/offline cleanup.
- Link ke library tabs dan account-related actions.

## 12. Menjalankan dan Menguji

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Asset tooling:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## 13. Catatan Pengembangan

- Jangan mengandalkan cloud download `completed` sebagai bukti file tersedia di device.
- Untuk Android emulator, gunakan `10.0.2.2`; untuk device fisik gunakan IP LAN backend.
- Jika menambah endpoint user-scoped, pastikan `TonztoonApi` bisa mengirim bearer token dan repository punya fallback lokal yang masuk akal.
- Jika mengubah model library backend, sinkronkan parser di `models/library.dart`, `models/progress.dart`, dan payload repository terkait.
- Pertahankan pola cache lokal agar UI tetap responsif saat koneksi backend lambat.
