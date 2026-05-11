# Changelog

Semua perubahan penting pada proyek **TonzToon Komik** akan didokumentasikan di dalam file ini.

**TonzToon Komik** adalah aplikasi pembaca komik lintas platform dan multi-sumber yang dibangun menggunakan Flutter. Aplikasi ini menggunakan backend Python FastAPI untuk pengambilan data langsung (*live scraping*) dan Supabase untuk sinkronisasi *cloud*.

---

## [1.5.2] - 2026-05-11

### Added
- GitHub Action workflow baru (\deploy-fastapi.yml\) untuk *deployment* otomatis backend FastAPI ke Hugging Face Spaces.

### Changed
- Restrukturisasi direktori aplikasi Flutter dari \frontend2/tonztoon_comic\ menjadi \frontend\.
- Pembaruan *path* pada GitHub Actions (\build-release.yml\), \.gitignore\, dan \.dockerignore\ untuk menyesuaikan dengan struktur direktori \frontend\ yang baru.

---

<details>
<summary><strong>Riwayat versi sebelumnya</strong></summary>

### [1.5.1](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.1) - 2026-05-10

### Added
- Integrasi plugin \package_info_plus\ untuk menampilkan informasi versi aplikasi.
- Penambahan izin \ android.permission.INTERNET\ pada \AndroidManifest.xml\ untuk memastikan akses jaringan berjalan lancar di versi rilis.

### Changed
- Peningkatan durasi *timeout* pada klien API (Connection: 20s, Send: 20s, Receive: 60s) untuk meningkatkan stabilitas koneksi ke server Hugging Face Spaces.
- Pembaruan \.gitignore\ untuk mengecualikan direktori \ frontend/\ lama.


### [1.5.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.0) - 2026-05-10

#### 🎉 Initial Release

##### Added
- Multi-source comic reader (MangaKatana, Kiryuu, dll)
- Onboarding screen dengan 3 halaman pengenalan fitur
- Autentikasi pengguna via Supabase (login & register)
- Halaman Home dengan daftar komik terbaru dan populer
- Fitur pencarian komik lintas sumber
- Halaman Detail Komik dengan info lengkap (sinopsis, genre, author, status)
- Reader komik berbasis viewer gambar dengan navigasi chapter
- Navigasi antar chapter (sebelumnya / berikutnya) langsung dari reader
- Sorting urutan chapter (Ascending / Descending)
- Fitur Perpustakaan (Library) untuk menyimpan komik favorit
- Riwayat baca otomatis tersimpan via Hive (local storage)
- Progress baca tersimpan dan ditampilkan di home screen (Continue Reading)
- Download chapter untuk dibaca offline
- Notifikasi update chapter terbaru (Dummy)
- Pengaturan aplikasi (theme, dll)
- Backend FastAPI dengan lazy loading dan background prefetch image
- Deployment backend ke Hugging Face Spaces via Docker

##### Technical
- Flutter 3.x dengan arsitektur Riverpod
- Hive sebagai local database (settings, auth, progress, library, cache)
- Scrapling-based live scraping on-demand
- Supabase sebagai database dan auth backend
- GitHub Actions untuk sync data komik otomatis

</details>


<!-- 
PANDUAN PENULISAN CHANGELOG
============================
Format setiap entry:
## [X.Y.Z] - YYYY-MM-DD

### Added     -> Fitur baru
### Changed   -> Perubahan pada fitur yang sudah ada
### Fixed     -> Bug fix
### Removed   -> Fitur yang dihapus
### Security  -> Perbaikan celah keamanan

Checklist release:
1. Update frontend/pubspec.yaml ke version: X.Y.Z+N
2. Tambahkan entry CHANGELOG.md dengan header ## [X.Y.Z] - YYYY-MM-DD
3. Buat dan push tag git dengan format vX.Y.Z

Catatan:
- Body GitHub Release mengambil versi terbaru dan satu blok <details> riwayat versi sebelumnya.
- Simpan hanya 1 versi sebelumnya di dalam blok <details>, lengkap dengan link release/tag.
-->
