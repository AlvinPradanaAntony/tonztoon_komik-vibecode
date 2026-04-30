# TonzToon Comic - Frontend Walkthrough

## 1. Ikhtisar (Overview)
Frontend TonzToon Comic adalah aplikasi mobile cross-platform yang dikembangkan dengan framework **Flutter** (Dart). Aplikasi ini bertindak sebagai antarmuka pengguna untuk menjelajahi katalog komik, membaca chapter (mode *vertical* maupun *paged*), dan mengelola koleksi bacaan *(library)*.

Fokus utama frontend adalah memberikan UI/UX yang dinamis, responsif, stabil saat digunakan dengan koneksi yang tidak menentu (*Offline-First* caching), dan terintegrasi baik dengan Backend FastAPI.

## 2. Tech Stack & Dependensi Utama
- **Flutter SDK**: Framework utama UI.
- **State Management**: **Riverpod** (`flutter_riverpod`). Dipilih karena reaktif, aman, dan memisahkan *business logic* dari UI dengan rapi.
- **Routing**: **GoRouter** (`go_router`) untuk penanganan rute terpusat dan *deep linking*.
- **Networking**: **Dio** (`dio`) sebagai HTTP Client handal untuk komunikasi dengan REST API Backend.
- **Caching & Local Storage**:
  - **Hive** (`hive_flutter`): NoSQL key-value database lokal yang sangat cepat untuk menyimpan metadata aplikasi, state *offline*, history, bookmark, dll.
  - **Flutter Secure Storage**: Menyimpan token kredensial Autentikasi (Supabase Token) secara aman.
- **Image Handling**: **Cached Network Image** (`cached_network_image`) untuk menampilkan gambar komik dengan *caching* berlapis agar menghemat bandwidth data.

## 3. Struktur Direktori `frontend/lib/`
Sesuai dengan *best practices* Flutter, arsitektur aplikasi dirancang secara modular di dalam `lib/src/`:

```text
frontend/
└── lib/
    ├── main.dart               # Entry point utama aplikasi Flutter
    └── src/
        ├── app.dart            # Root Widget (App), konfigurasi material, tema, inisialisasi router
        ├── core/               # Konfigurasi sistem dan kelas penunjang global
        │   ├── constants/      # App text, ukuran, colors, dll.
        │   ├── network/        # Konfigurasi instance Dio & interceptors
        │   ├── theme/          # Konfigurasi ThemeData (Dark/Light mode)
        │   └── utils/          # Fungsi utility global
        ├── features/           # Fitur utama, dipecah menjadi modul mandiri
        │   ├── auth/           # Fitur Autentikasi (Guest mode, Sign In, Supabase integration)
        │   ├── comic/          # Layar detail komik & list chapter
        │   ├── home/           # Halaman utama (Discover, Trending, Continue Reading)
        │   ├── library/        # Halaman koleksi pengguna (Bookmarks, History, Offline Downloads)
        │   ├── onboarding/     # Intro screen untuk pengguna baru
        │   ├── reader/         # Mesin inti pembaca komik (Vertical Scroll & Paged Manga Mode)
        │   ├── search/         # Halaman pencarian dan filter tag
        │   ├── shell/          # Halaman pembungkus utama (Bottom Navigation Bar)
        │   └── splash/         # Animasi awal saat aplikasi dibuka
        ├── models/             # Data class (Entity) dengan method parsing dari/ke JSON API
        ├── repositories/       # Abstraksi data layer (Network API Service vs Local Hive Data)
        ├── routing/            # Deklarasi router tree menggunakan GoRouter
        └── widgets/            # Komponen UI global / reusable (Buttons, Cards, Loaders, Dialogs)
```

## 4. Arsitektur & Pola Desain (Design Patterns)
### 4.1. Data Flow & State Management (Riverpod)
Aplikasi sangat mengandalkan struktur **Layered Architecture**:
1. **UI Layer (`features/`)**: Hanya bertanggung jawab me-render Widget berdasarkan *state*.
2. **Controller/Provider Layer (`features/`)**: Provider dari Riverpod menengahi *UI* dan *Repository*. Menangani *loading*, *success*, dan *error* (menggunakan `AsyncValue`).
3. **Repository Layer (`repositories/`)**: Di sinilah logika pengambilan data terjadi. Jika data tersedia di *Local Cache* (Hive) dan aplikasi offline, kembalikan cache. Jika *online*, ambil dari API melalui Dio, lalu perbarui cache.
4. **Data Layer (`models/`)**: Representasi raw dari data API.

### 4.2. Mekanisme Reader (Membaca Komik)
Fitur *Reader* adalah yang paling kritis di aplikasi ini:
- **Vertical Mode**: Memanfaatkan `ListView.builder` tanpa jarak (padding 0) antar widget gambar (menggunakan *CachedNetworkImage*).
- **Manga Mode (Paged)**: Memanfaatkan `PageView.builder` untuk gestur *swipe* per halaman.
- Keduanya menyimpan posisi (koordinat *scroll* atau indeks *page*) ke *Local Storage* secara periodik (lewat event listener) agar fitur *Continue Reading* akurat saat dibuka kembali.

### 4.3. Offline-First Caching
Mekanisme Offline-First dilakukan secara *hybrid*:
- Pengguna yang masuk sebagai **Guest** menyimpan koleksinya 100% lokal via Hive.
- Jika pengguna melakukan **Login** (mendapatkan Token dari Backend/Supabase), maka dilakukan migrasi (*one-time sync*) ke Cloud DB. Namun, penyimpanan lokal tetap digunakan sebagai sumber utama untuk render UI agar instan dan mengatasi hilangnya koneksi saat membaca.

## 5. Panduan Menjalankan & Mengembangkan
1. **Instalasi Dependencies:**
   ```bash
   cd frontend
   flutter clean
   flutter pub get
   ```
2. **Generasi Kode (Jika ada `build_runner`):**
   (Jalankan ini jika melakukan perubahan pada model yang butuh auto-generasi seperti json_serializable atau freeezy).
   ```bash
   dart run build_runner build -d
   ```
3. **Menjalankan Aplikasi (Mode Debugging):**
   Gunakan emulator, *device* fisik, atau web browser.
   ```bash
   flutter run
   ```
4. **Konfigurasi API Endpoint:**
   Pastikan variabel base URL API (yang terhubung ke backend FastAPI) didefinisikan dengan benar, umumnya melalui environment variables (`.env` di flutter) atau *Constants class* di `lib/src/core/`.

## Catatan Khusus
- Gambar komik yang disajikan bisa jadi memuat *mixed-content* atau diproteksi hotlinking. Jika menemukan gambar rusak (blank screen), periksa *Interceptor* pada *Dio* yang mengirimkan header khusus (seperti referer palsu) saat request gambar atau tanyakan perbaikan *Proxy API* pada spesifikasi *Backend*.
- Jaga performa Render List Reader untuk komik berjumlah banyak (80+ halaman) dengan mengoptimalkan prefetching (*ImageCache*) namun tanpa membebani RAM (jangan _preload_ semua seketika).
