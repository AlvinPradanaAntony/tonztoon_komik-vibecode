# Changelog

Semua perubahan penting pada proyek **TonzToon Komik** akan didokumentasikan di dalam file ini.

**TonzToon Komik** adalah aplikasi pembaca komik lintas platform dan multi-sumber yang dibangun menggunakan Flutter. Aplikasi ini menggunakan backend Python FastAPI untuk pengambilan data langsung (*live scraping*) dan Supabase untuk sinkronisasi *cloud*.

---

## [1.11.0] - 2026-05-25

### Added
- Login email/password kini mendukung identifier berupa email atau username publik.
- Sistem `TonztoonModalDialog` terpadu untuk dialog konfirmasi, notifikasi, helper text, loading action, dan support action.
- Asset ilustrasi dialog baru untuk auth error, setup akun/password, sinkronisasi cloud, logout, hapus data, email, dan profile editing.
- Validasi login baru di frontend untuk field "Email atau username".

### Changed
- Backend auth kini resolve username ke email sebelum melakukan login Supabase password grant.
- Dialog Auth, Settings, Library, shell, dan migrasi guest dipindahkan ke desain modal TonzToon yang konsisten.
- Pesan error login diperjelas dengan aksi reset password langsung dari dialog.
- Reader preferences otomatis direfresh setelah login agar pengaturan akun segera tersinkron.

### Fixed
- Perubahan username setelah pembuatan akun dibatasi agar identitas publik tetap stabil.
- Relation preview account manager kini menyertakan status `mark_read`.
- Preservasi cover storage di scraper diperluas agar tidak mudah tertimpa URL source.

---

<details>
<summary><strong>Riwayat versi sebelumnya</strong></summary>

### [1.10.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.10.0) - 2026-05-24

#### Added
- Status `has_password` pada ringkasan keamanan akun untuk membedakan akun email/password dan akun provider seperti Google.
- Lookup Supabase Auth Admin user untuk membaca provider, identities, dan metadata keamanan yang lebih lengkap.
- Dukungan update username dari frontend melalui endpoint profil yang sudah ada.
- Badge `TERBARU` pada chapter paling atas di halaman detail komik.

#### Changed
- Register, login email/password, dan update password kini menandai user sebagai sudah punya password di app metadata Supabase Auth.
- Halaman Home, Detail Komik, Settings, dan kartu komik dipoles untuk layout carousel, status chapter, rating, dan panel akun yang lebih jelas.
- Security overview kini mengambil provider dari metadata dan identities agar akun multi-provider tampil lebih akurat.
- Sinkronisasi scraper menjaga URL cover yang sudah berada di public object storage, termasuk saat `SUPABASE_URL` tidak tersedia di environment job.

#### Fixed
- Cover yang sudah dimigrasi ke Supabase Storage tidak lagi tertimpa oleh URL source scraper pada sync berikutnya.
- Model dan test auth security overview kini memvalidasi `has_password`.
- Update profil dapat menyimpan username dan memperbarui cache user lokal.

---

### [1.9.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.9.0) - 2026-05-22

#### Added
- Native Google Sign-In untuk frontend mobile melalui `google_sign_in` dan `NativeGoogleAuthClient`.
- Endpoint backend `POST /api/v1/auth/google` untuk menukar Google ID token menjadi sesi Supabase.
- Utilitas `AppError` untuk logging error terpusat, stack trace, dan sanitasi pesan yang ramah pengguna.
- `showAppErrorSnackBar` dan error state Library agar feedback kegagalan lebih konsisten di seluruh UI.

#### Changed
- Auth flow kini menghubungkan token Google native ke backend melalui `AuthRepository.loginWithGoogle`.
- Backend auth service diperkuat dengan validasi konfigurasi admin dan pengecekan email duplikat via Supabase Admin API.
- Auth, Catalog, Comic Detail, Home, Library, Notifications, Reader, Search, Settings, dan `AppAsyncView` memakai pola error handling baru.
- Global Flutter dan platform error kini ditangkap dari `main.dart` untuk meningkatkan observability.
- Workflow `popular-sync` diperbarui agar sinkronisasi scraper berjalan lebih sering.

#### Fixed
- Profil pengguna kini ikut menyinkronkan avatar Google saat login dengan provider Google.
- Pesan error UI kini lebih aman dan seragam, tanpa membocorkan detail teknis mentah ke pengguna.
- Konfigurasi Google OAuth untuk backend dan frontend didokumentasikan di README serta dokumen Supabase auth.

---

### [1.8.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.8.0) - 2026-05-20

#### Added
- Refresh signed cover URL Komikcast otomatis saat proxy gambar mendeteksi URL cover yang kedaluwarsa.
- Skrip `refresh_komikcast_cover_urls.py` untuk memperbarui URL cover Komikcast secara batch dengan checkpoint, dry-run, dan retry/backoff.
- Helper UI `AppResponsive` dan `showAppSnackBar` untuk text scaling responsif dan snackbar konsisten.
- Pagination lanjutan pada halaman section komik, termasuk load more, refresh, loading state, dan error state.

#### Changed
- Branding aplikasi diperbarui menjadi `tonztoon` dengan package id `com.tonzdev.tonztoon` di Android, iOS, macOS, Windows, Linux, dan Web.
- Workflow build release kini menyiapkan signing APK dari GitHub Secrets dan membersihkan file signing setelah build.
- Reader diperhalus dengan restore posisi yang lebih presisi, cache prefetch ber-cooldown, snackbar baru, dan proteksi agar progress tidak tertimpa saat restore.
- Catalog, search, home, detail, library, notifications, settings, dan auth screen disesuaikan untuk layout lebih responsif dan feedback UI yang lebih konsisten.
- Continue reading kini local-first untuk akun login, melakukan refresh cloud di background, dan memberi sinyal refresh setelah login/logout.

#### Fixed
- Logout kini membersihkan data lokal yang terkait user tanpa menghapus cache katalog atau pengaturan global seperti tema.
- Cache genre dapat direfresh dan tetap tersedia saat offline atau API gagal.
- Proxy image dapat menyimpan ulang URL cover Komikcast yang sudah direfresh ke database.
- Import package dan metadata test diperbarui mengikuti rename package Flutter menjadi `tonztoon`.

---

### [1.5.4](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.4) - 2026-05-16

#### Added
- Penyimpanan chapter selesai terpisah melalui tabel `user_completed_chapters` dan payload sinkronisasi `completed_chapters`.
- Dialog migrasi data guest untuk membantu memindahkan progress, koleksi, favorite scenes, download, dan preferensi reader ke akun.
- Metadata lokal untuk membedakan cache progress/preferensi milik akun dengan data guest yang perlu dimigrasikan.
- Test repository dan parsing model untuk completed chapters, migrasi guest, fallback cache, dan preferensi reader.

#### Changed
- Reader kini melacak chapter aktif, posisi halaman vertikal yang benar-benar terlihat, dan chapter selesai tanpa mengubah posisi continue reading.
- Progress lokal dan cloud digabungkan saat membaca state komik, sehingga progress terbaru tetap terlihat saat sinkronisasi cloud gagal.
- Default `mark_read_on_complete` diubah menjadi nonaktif, dan field lama `auto_next` dihapus dari preferensi reader.
- Tampilan Home, Detail Komik, Reader, Library, Notifications, dan Settings disesuaikan dengan status baca selesai serta migrasi data lokal.

#### Fixed
- Data progress milik akun tidak lagi dihitung sebagai data guest saat proses migrasi.
- Completed chapters lokal dapat dipertahankan dan diimpor tanpa menimpa progress continue reading terakhir.
- Riwayat dan notifikasi baca lebih konsisten saat user membaca offline, berpindah chapter, atau kembali login.

---

### [1.5.3](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.3) - 2026-05-15

#### Added
- Upload avatar profil dengan optimasi gambar WebP dan penyimpanan Supabase Storage.
- Ringkasan keamanan akun untuk status email, provider login, dan sesi aktif.
- Sistem notifikasi berbasis repository dengan filter, penanda sudah dibaca, dan navigasi aksi.
- Pane bersama untuk favorite scenes dan offline downloads agar bisa dipakai di halaman Library maupun Settings.

#### Changed
- Form registrasi kini menyimpan nama akun dan username sejak awal pembuatan akun.
- Cache auth dan profil pengguna kini membawa display name, username, dan avatar agar sesi lebih stabil saat restore.
- Halaman Settings/Profile diperluas untuk edit profil, avatar, koleksi tersimpan, favorite scenes, downloads, security, dan push notification coming soon.
- Reader dan halaman detail komik menampilkan serta membaca chapter offline dengan indikator status unduhan.

#### Fixed
- Refresh token API kini memakai satu proses refresh bersama dan melakukan refresh lebih awal sebelum token kedaluwarsa.
- Restore sesi auth lebih toleran terhadap error jaringan dengan fallback ke cache lokal saat token refresh masih tersedia.
- Trigger profil Supabase kini ikut menormalisasi username dari metadata saat user baru dibuat.

---

### [1.5.2](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.2) - 2026-05-11

#### Added
- GitHub Action workflow baru (\deploy-fastapi.yml\) untuk *deployment* otomatis backend FastAPI ke Hugging Face Spaces.

#### Changed
- Restrukturisasi direktori aplikasi Flutter dari \frontend2/tonztoon_comic\ menjadi \frontend\.
- Pembaruan *path* pada GitHub Actions (\build-release.yml\), \.gitignore\, dan \.dockerignore\ untuk menyesuaikan dengan struktur direktori \frontend\ yang baru.

---

### [1.5.1](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.1) - 2026-05-10

#### Added
- Integrasi plugin \package_info_plus\ untuk menampilkan informasi versi aplikasi.
- Penambahan izin \ android.permission.INTERNET\ pada \AndroidManifest.xml\ untuk memastikan akses jaringan berjalan lancar di versi rilis.

#### Changed
- Peningkatan durasi *timeout* pada klien API (Connection: 20s, Send: 20s, Receive: 60s) untuk meningkatkan stabilitas koneksi ke server Hugging Face Spaces.
- Pembaruan \.gitignore\ untuk mengecualikan direktori \ frontend/\ lama.

---

### [1.5.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.5.0) - 2026-05-10

#### Initial Release

#### Added
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

#### Technical
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
