# tonztoon

A new Flutter project.

## Google Sign-In via Backend

Flow login Google memakai native `google_sign_in` hanya untuk mengambil token
Google. Token itu dikirim ke backend `POST /auth/google`, lalu FastAPI menukar
token ke Supabase Auth dengan grant `id_token`, memastikan `public.profiles`
terisi, dan mengembalikan session ke Flutter. Access token Supabase yang
diterima disimpan di secure storage yang sama dengan login email/password,
sehingga API backend tetap memakai header:

```text
Authorization: Bearer <supabase_access_token>
```

Jalankan aplikasi dengan konfigurasi berikut:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=your-ios-client-id.apps.googleusercontent.com
```

`GOOGLE_IOS_CLIENT_ID` hanya wajib untuk iOS/macOS. Android tetap membutuhkan
OAuth client Android di Google Cloud dengan package name dan SHA certificate yang
sesuai, tetapi kode Flutter memakai Web Client ID sebagai `serverClientId`.

Backend tetap membutuhkan konfigurasi Supabase Auth seperti `SUPABASE_URL` dan
`SUPABASE_PUBLISHABLE_KEY`.

Checklist Supabase:

- Aktifkan provider Google di Supabase Dashboard: Authentication > Providers.
- Isi Google Client ID dan Client Secret dari Google Cloud OAuth.
- Pastikan URL redirect Supabase Google provider sudah terdaftar di Google
  Cloud OAuth authorized redirect URIs.
- Untuk iOS Google Sign-In native, ikuti setup URL scheme dari package
  `google_sign_in` menggunakan reversed iOS client ID.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
