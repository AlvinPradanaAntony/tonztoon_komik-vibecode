# Changelog

Semua perubahan penting pada proyek **TonzToon Komik** akan didokumentasikan di dalam file ini.

**TonzToon Komik** adalah aplikasi pembaca komik lintas platform dan multi-sumber yang dibangun menggunakan Flutter. Aplikasi ini menggunakan backend Python FastAPI untuk pengambilan data langsung (*live scraping*) dan Supabase untuk sinkronisasi *cloud*.

---

## [1.15.3] - 2026-06-09

### Changed
- Reader kini langsung menandai chapter sebelumnya sebagai selesai saat pengguna berpindah melewati batas chapter, selama preferensi `mark read on complete` aktif.
- Halaman detail komik kini menyediakan aksi manual `Sinkronkan status read` untuk mengirim status chapter selesai lokal ke cloud dan source yang terhubung.
- Sinkronisasi status read dapat menandai chapter sebelumnya sebagai selesai tanpa mengubah posisi continue reading saat ini.
- State bookmark multi-source dari detail komik dan hasil penyimpanan kandidat kini dicache secara lokal agar badge serta relasi sumber tetap konsisten saat offline atau fallback lokal.
- Backend library kini mendukung import status completed chapter secara terpisah dari progress baca utama.
- Probing dimensi gambar WebP di backend dibuat lebih ringan dengan membaca header tanpa decoding penuh.
- Sinkronisasi gambar chapter kini memiliki mode khusus dimensi untuk melengkapi metadata width/height pada data yang sudah ada.

---

<details>
<summary><strong>Riwayat versi sebelumnya</strong></summary>

### [1.15.2](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.15.2) - 2026-06-08

#### Changed
- Proses pemindaian kandidat bookmark (multi-source candidate scan) kini mengabaikan sumber komik alternatif yang sudah terhubung, baik pada pemrosesan backend (SQL) maupun repositori frontend.

---

### [1.15.1](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.15.1) - 2026-06-08

#### Changed
- Proses penyajian kandidat bookmark pada dialog kini dikelompokkan berdasarkan komik utama yang di-bookmark.
- Kandidat dalam setiap kelompok diurutkan berdasarkan tingkat kecocokan (confidence) tertinggi.
- Pengurutan kelompok memprioritaskan kelompok dengan kandidat yang otomatis tercentang (kecocokan >= 82%) terlebih dahulu, diikuti dengan skor kecocokan tertinggi.

#### Added
- Widget test untuk memverifikasi struktur pengelompokan, data visual, serta logika pengurutan pada dialog kandidat bookmark.

---

### [1.15.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.15.0) - 2026-06-08

#### Added
- Bookmark multi-source untuk memindai komik serupa dan menghubungkan bookmark utama dengan sumber alternatif yang dipilih.
- Sinkronisasi otomatis status chapter selesai ke komik yang sudah terhubung berdasarkan nomor chapter yang sama.
- Badge sumber terhubung pada daftar bookmark serta status bookmark terhubung pada halaman detail komik.

#### Changed
- Proses pencarian dan penyimpanan hubungan bookmark kini menampilkan kandidat, persentase kecocokan, serta progres sinkronisasi.
- Kartu komik grid kini menampilkan chapter terbaru sebagai badge pada cover serta total views dalam format ringkas.
- Kartu komik list menampilkan total views dan indikator scroll dua arah untuk daftar genre yang panjang.
- Daftar bookmark menampilkan rating, total views, status, serta seluruh sumber terhubung dalam metadata yang dapat digulir.
- Tampilan halaman detail komik disesuaikan untuk navigasi edge-to-edge yang lebih konsisten.
- Kartu, filter, dan indikator notifikasi diperbarui agar status sudah dibaca lebih jelas serta tampil lebih baik pada dark theme.
- Kontras tombol Helpdesk, aksi notifikasi, helper modal, dan efek tombol utama disesuaikan untuk light dan dark theme.

---

### [1.14.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.14.0) - 2026-06-06

#### Added
- Helpdesk di Home dan Settings untuk mengirim ulasan berbintang atau laporan masalah langsung dari aplikasi.
- Pengaturan untuk menampilkan atau menyembunyikan tombol cepat Helpdesk di halaman Home.

#### Changed
- Onboarding didesain ulang dengan ilustrasi dan penjelasan yang lebih jelas untuk fitur multi-source, pustaka, dan download offline.
- Tampilan kartu komik disatukan di Home, katalog, pencarian, dan halaman section agar informasi serta interaksinya lebih konsisten.
- Home memakai AppBar yang responsif terhadap scroll untuk memberi ruang baca lebih luas tanpa menghilangkan akses navigasi.
- Halaman notifikasi kini mendukung pull-to-refresh, filter sistem, serta aksi membersihkan seluruh notifikasi dengan konfirmasi.
- Tampilan kartu autentikasi dan tombol tutup modal dipoles agar lebih konsisten dengan desain aplikasi.

---

### [1.13.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.13.0) - 2026-06-04

#### Added
- Feed `top-ranking` dan `recommendations` per source, lengkap dengan endpoint backend, provider frontend, rail UI, shimmer, dan cache repository.
- Sistem remote push notification Android berbasis Firebase Cloud Messaging untuk device registration, inbox background, token lifecycle, channel notifikasi, dan deep link.
- Tabel `user_push_devices` dan `push_notification_events` untuk manajemen token, audit, dan idempotensi pengiriman notifikasi.
- Endpoint notification untuk device management, admin announcement, dan event update chapter dari scraper.
- Index database `ix_comics_source_top_view_order` untuk mengoptimalkan query ranking berdasarkan view.

#### Changed
- Scraper Komiku kini mengekstrak `total_view`, dan feed source memakai metadata view untuk ranking.
- Workflow build, scraper, dan popular sync diperbarui untuk mendukung konfigurasi Firebase serta pengiriman event push.
- Backfill metadata Kiryuu, refresh cover, sync chapter images, sync cover images, dan sync full library mendapat opsi anti-blocking, limit, checkpoint, graceful shutdown, dan refresh missing only.
- Navigasi notifikasi ditunda sampai bootstrap auth/app siap agar deep link dari push tidak hilang saat startup.
- UI memakai edge-to-edge/system overlay yang lebih konsisten di splash, onboarding, dan notifications screen.

#### Fixed
- Remote push service memperketat pengecekan auth sebelum registrasi token agar token tidak tersimpan untuk sesi yang belum siap.
- Admin account dashboard dan dokumentasi kontrak push notification diperbarui mengikuti endpoint serta payload baru.
- Validasi source stats kini memakai daftar source observable sehingga source cadangan tetap tercatat tanpa diperlakukan sebagai source utama.

---

### [1.12.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.12.0) - 2026-06-02

#### Added
- Sistem update aplikasi OTA dari GitHub Releases, lengkap dengan pengecekan otomatis saat startup, pengecekan manual, dialog update, changelog terpasang, dan instalasi APK Android.
- Source scraper cadangan Kiryuu beserta registry source aktif/cadangan, observability source, dan skrip backfill metadata.
- Pagination untuk bookmarks, history per chapter, dan continue reading, termasuk summary Library serta halaman penuh continue reading.
- Lazy-load image queue Komiku Asia dengan worker background dalam proses FastAPI dan status persiapan chapter di frontend.
- Preferensi push notification end-to-end dari profile backend hingga toggle Settings dan deep link notifikasi.
- Statistik aktivitas source, tanggal rilis chapter terbaru, serta badge `NEW` untuk update komik terkini.
- Dukungan dimensi intrinsik gambar chapter untuk menjaga aspect ratio reader dan mengurangi layout shift.

#### Changed
- Riwayat baca backend kini disimpan per chapter agar daftar aktivitas lebih granular dan mudah dipaginasi.
- Pemrosesan lazy image Komiku Asia dipindahkan dari GitHub Actions ke worker asyncio FastAPI untuk memangkas waktu tunggu pengguna.
- Reader memakai metadata width/height, resize constraint untuk strip resolusi tinggi, dan fallback ratio yang lebih stabil.
- Offline download pane membedakan antrean aktif dan file lokal siap baca, mendukung retry batch gagal, serta mencegah duplikasi chapter.
- Default `mark_read_on_complete` diaktifkan kembali dan pengelolaan notifikasi lokal disatukan dalam `PushNotificationService`.

#### Fixed
- Request chapter Komiku Asia yang belum siap kini mengembalikan status `202 Accepted` dan otomatis dicoba ulang oleh frontend.
- Reader tidak lagi bergantung penuh pada perhitungan fallback ukuran gambar yang dapat menyebabkan pergeseran layout.
- Antrean download offline gagal dapat dilanjutkan kembali dengan progress berdasarkan jumlah gambar.
- API client membaca pesan error backend bertingkat dengan lebih baik.

---

### [1.11.0](https://github.com/AlvinPradanaAntony/tonztoon_komik-vibecode/releases/tag/v1.11.0) - 2026-05-25

#### Added
- Login email/password kini mendukung identifier berupa email atau username publik.
- Sistem `TonztoonModalDialog` terpadu untuk dialog konfirmasi, notifikasi, helper text, loading action, dan support action.
- Asset ilustrasi dialog baru untuk auth error, setup akun/password, sinkronisasi cloud, logout, hapus data, email, dan profile editing.
- Validasi login baru di frontend untuk field "Email atau username".

#### Changed
- Backend auth kini resolve username ke email sebelum melakukan login Supabase password grant.
- Dialog Auth, Settings, Library, shell, dan migrasi guest dipindahkan ke desain modal TonzToon yang konsisten.
- Pesan error login diperjelas dengan aksi reset password langsung dari dialog.
- Reader preferences otomatis direfresh setelah login agar pengaturan akun segera tersinkron.

#### Fixed
- Perubahan username setelah pembuatan akun dibatasi agar identitas publik tetap stabil.
- Relation preview account manager kini menyertakan status `mark_read`.
- Preservasi cover storage di scraper diperluas agar tidak mudah tertimpa URL source.

---

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
