# PRD — TonzToon Web (Next.js)

| Atribut | Nilai |
| --- | --- |
| Versi dokumen | 0.1 |
| Tanggal | 24 Oktober 2026 |
| Status | Draft kebutuhan produk berdasarkan jawaban pemilik produk dan audit kode repo |
| Produk | Frontend web pembaca manga, manhwa, dan manhua TonzToon |
| Bahasa | Bahasa Indonesia |
| Platform utama | Browser desktop/laptop; tetap responsif di tablet dan ponsel |
| Lokasi implementasi | `web/`, berdampingan dengan `frontend/` Flutter dan `backend/` FastAPI |
| Tahap pekerjaan saat ini | PRD saja; instalasi framework dan implementasi dilakukan pada tahap berikutnya |

## 1. Ringkasan produk

TonzToon Web memungkinkan pembaca menemukan komik dari beberapa source, membaca melalui browser, mengelola pustaka, dan melanjutkan bacaan lintas perangkat. Pengguna dapat langsung membaca sebagai guest. Login bersifat opsional untuk menyinkronkan progress, bookmark, koleksi, panel favorit, riwayat, dan preferensi reader melalui backend yang sudah ada.

Pengalaman web mengikuti kemampuan dan alur frontend Flutter di repo, dengan tata letak yang dirancang untuk layar desktop, mouse, keyboard, URL yang dapat dibagikan, dan navigasi browser. Frontend Flutter tetap dipertahankan. Backend FastAPI tetap menjadi sumber data; web tidak membuat scraper, database katalog, atau sistem autentikasi pengganti.

### 1.1 Keputusan yang sudah dikonfirmasi

| ID | Keputusan pemilik produk |
| --- | --- |
| D-01 | Target pembaca Indonesia; antarmuka Bahasa Indonesia. |
| D-02 | Web-first dengan referensi fitur dan alur dari frontend mobile dalam repo. |
| D-03 | Guest didukung; login opsional dengan sinkronisasi antarperangkat. |
| D-04 | Cakupan versi pertama mendekati Flutter, termasuk login, koleksi, dan panel favorit. |
| D-05 | Next.js menjadi frontend tambahan dalam `web/`; Flutter tetap dipertahankan. |
| D-06 | Pekerjaan saat ini PRD dahulu. Deployment dan URL backend diputuskan kemudian. |
| D-07 | Scaffolding harus melalui instalasi framework resmi terbaru, bukan membuat file scaffold secara manual oleh agent. |
| D-08 | Dokumentasi framework menggunakan Context7. |

### 1.2 Rekomendasi yang masih dapat disesuaikan

- Nama dan identitas visual mengikuti TonzToon yang sudah ada, termasuk warna oranye, biru, serta tema terang/gelap.
- Offline/PWA penuh dan web push ditempatkan sesudah MVP. Ini merupakan pembagian tahap berdasarkan pilihan cakupan “mendekati Flutter”, bukan penghapusan permanen fitur mobile.
- Semua fitur P0 dan P1 di bawah termasuk target MVP. P1 dikerjakan setelah alur membaca inti stabil; hambatan integrasi dicatat secara terbuka sebelum rilis.

## 2. Masalah, tujuan, dan ukuran keberhasilan

### 2.1 Masalah pengguna

1. Pembaca membutuhkan akses komik dari browser tanpa memasang aplikasi.
2. Judul yang sama dapat tersedia pada beberapa source; source dan identitas bacaan harus jelas.
3. Reader harus nyaman untuk webtoon vertikal maupun manga per halaman.
4. Progress, bookmark, koleksi, dan panel favorit perlu dapat dipakai kembali ketika berpindah perangkat.
5. Gangguan koneksi atau source tidak boleh menyebabkan progress yang sudah tersimpan lokal hilang.

### 2.2 Tujuan MVP

- Menyediakan alur lengkap: beranda → katalog/pencarian → detail → reader → simpan progress → lanjut baca.
- Menyediakan pustaka guest dan pustaka akun dengan pemisahan data yang jelas.
- Mendukung pustaka terorganisasi melalui bookmark, koleksi, panel favorit, dan riwayat.
- Menggunakan endpoint yang benar-benar tersedia dan mematuhi batasannya.
- Menyediakan pengalaman desktop yang nyaman dan akses responsif melalui ponsel.

### 2.3 Kriteria keberhasilan

| Area | Kriteria penerimaan |
| --- | --- |
| Membaca | Guest dapat membuka chapter dari URL langsung tanpa login. |
| Resume | Setelah refresh atau buka ulang, posisi pulih pada item gambar yang sama; selisih vertikal maksimal sekitar satu viewport setelah gambar selesai ditata. |
| Sinkronisasi | Dengan akun sama, progress yang berhasil disimpan dapat dilanjutkan di web/perangkat lain, termasuk Flutter. |
| Pustaka | Bookmark, koleksi, dan panel favorit bertahan setelah reload dan muncul pada akun yang sama di perangkat lain setelah refresh. |
| Jaringan | Gagal menyimpan ke cloud ditandai; checkpoint lokal tetap tersedia dan tidak diklaim sudah tersinkron. |
| UX desktop | Navigasi, filter, dialog, dan kontrol reader dapat dipakai dengan keyboard. |
| Integrasi | Tidak ada fitur MVP yang bergantung pada endpoint backend fiktif. |

Target performa dan skenario uji ada di bagian 11 dan 13. Semua angka merupakan target penerimaan, belum hasil pengukuran aplikasi web.

## 3. Pengguna dan alur utama

| Persona | Kebutuhan utama |
| --- | --- |
| Pembaca harian | Rilis terbaru, bookmark, indikator chapter selesai, dan lanjut baca. |
| Pembaca maraton | Reader vertikal/per halaman, navigasi chapter, binge mode, dan prefetch terbatas. |
| Pengelola pustaka | Koleksi, filter bookmark, riwayat, panel favorit, serta source alternatif yang dipilih sendiri. |
| Pengguna lintas perangkat | Login opsional, migrasi guest, sinkronisasi progress, dan preferensi reader. |

Alur utama:

1. **Guest pertama kali:** buka beranda → pilih komik → lihat detail → baca → progress dan pustaka tersimpan lokal.
2. **Melanjutkan bacaan:** buka beranda/pustaka → pilih Lanjut Baca → pulihkan chapter dan posisi.
3. **Login dan migrasi:** login → tampil ringkasan data guest → pilih impor atau lewati → tampil hasil per kategori.
4. **Mengelola pustaka:** bookmark komik → masukkan ke koleksi → buka kembali melalui pustaka.
5. **Panel favorit:** pilih gambar dalam reader → simpan dengan catatan opsional → buka dari tab Panel Favorit pada chapter dan gambar yang sama.
6. **Source terganggu:** tampil pesan dan retry → pengguna dapat memilih source lain yang sudah tersedia; perpindahan tidak dilakukan otomatis hanya karena judul mirip.

## 4. Cakupan dan kesetaraan fitur Flutter

| Fitur referensi Flutter | Target web | Prioritas |
| --- | --- | --- |
| Beranda, rekomendasi, rilis terbaru, populer, top ranking, pemilih source | Termasuk, memakai endpoint yang tersedia; susunan desktop | P0 |
| Katalog gabungan/per source, genre, filter, sort, pencarian | Termasuk dengan batas kontrak pencarian saat ini | P0 |
| Detail, metadata, daftar chapter, Baca/Lanjut Baca | Termasuk | P0 |
| Reader vertikal, per halaman, LTR/RTL, progress, prev/next | Termasuk | P0 |
| Bookmark, continue reading, riwayat | Lokal untuk guest; cloud untuk akun | P0 |
| Email/username login, register, konfirmasi email, reset password, logout | Termasuk | P0 |
| Sinkronisasi lintas perangkat dan migrasi guest | Termasuk | P0 |
| Koleksi dan panel favorit | Termasuk | P1 |
| Tema, preferensi reader, binge mode, auto-scroll | Termasuk | P1 |
| Profil, avatar, ringkasan keamanan akun, waktu baca | Termasuk sesuai endpoint dan batas sinkronisasinya | P1 |
| Hubungkan bookmark antar-source dan sinkronkan chapter selesai | Termasuk dengan konfirmasi relasi oleh pengguna | P1 |
| Google login | Target MVP; aktivasi menunggu konfigurasi OAuth web tervalidasi | P1 |
| Lapor masalah/review aplikasi melalui helpdesk | Termasuk; bukan komentar publik komik | P1 |
| Download chapter/batch dan pembacaan offline penuh | Backlog tahap berikutnya; memerlukan penyimpanan browser dan pengujian tersendiri | P2 |
| PWA installable dan notifikasi web push | Backlog; web push belum didukung kontrak backend saat ini | P2 |
| Pembaruan aplikasi native, izin perangkat native, pengelola akun admin | Di luar frontend web pembaca | Di luar cakupan |

Komentar publik, voting rating komik, langganan berbayar, pembayaran, iklan, rekomendasi AI, dan upload komik belum masuk MVP. Endpoint untuk komentar/voting/pembayaran tidak ditemukan pada audit ini. Monetisasi tetap menjadi keputusan produk terbuka.

## 5. Arsitektur informasi dan pengalaman web

### 5.1 Navigasi dan URL

| Halaman | URL frontend yang diusulkan | Isi utama |
| --- | --- | --- |
| Beranda | `/` | Rekomendasi, Lanjut Baca, rilis terbaru, populer, top ranking |
| Katalog | `/catalog` | Grid komik, source, filter, sort, pagination |
| Pencarian | `/search?q=...&source=...&page=...` | Hasil judul/alias; source opsional |
| Detail | `/comic/[source]/[slug]` | Metadata, tindakan pustaka, chapter |
| Reader | `/reader/[source]/[slug]/[chapter]` | Reader tanpa shell katalog yang mengganggu |
| Pustaka | `/library?tab=bookmarks` | Tab bookmark, koleksi, panel favorit, riwayat |
| Detail koleksi | `/library/collections/[id]` | Nama dan isi koleksi |
| Lanjut Baca | `/library/continue-reading` | Daftar progress terakhir |
| Login/register | `/auth` | Pilihan login, daftar, dan lanjut sebagai guest |
| Verifikasi email | `/auth/callback` | Memproses konfirmasi melalui kontrak backend |
| Lupa/reset password | `/auth/forgot-password`, `/auth/reset-password` | Permintaan dan penyelesaian pemulihan |
| Pengaturan | `/settings` | Tema, reader, data lokal, dan bantuan |
| Profil/keamanan | `/settings/profile`, `/settings/security` | Profil, avatar, informasi sesi |

Path frontend berbeda dari path API. Tidak boleh menavigasi pengguna ke `detail_url` API sebagai halaman web.

### 5.2 Tata letak dan interaksi

- Desktop memakai navigasi persisten, pencarian yang mudah dijangkau, area konten lebar terbatas, dan filter di panel samping. Detail dapat memakai dua kolom untuk metadata dan chapter.
- Grid menyesuaikan lebar viewport; cover mempertahankan rasio dan judul tidak memaksa overflow.
- Pada tablet/ponsel, filter menjadi drawer/dialog dan kolom ditumpuk. Target viewport verifikasi: 360, 768, 1280, dan 1440 piksel.
- Label utama: Beranda, Katalog, Cari, Pustaka, Pengaturan, Lanjut Baca, Koleksi, Panel Favorit, Riwayat.
- Tema mengikuti sistem pada kunjungan awal, lalu mengikuti pilihan tersimpan. Acuan warna Flutter: oranye `#FF9D00`, biru `#3A86FF`, dan latar gelap `#0A0F1A`; kontras teks tetap harus diuji.
- Navigasi Back/Forward memulihkan query, filter, halaman katalog, dan posisi scroll. Link dapat dibuka di tab baru.
- Reader menyediakan lebar baca yang dapat diatur, kontrol tampil/sembunyi, dan fullscreen jika didukung browser. Overlay tidak mengubah posisi gambar.
- Onboarding berupa pengenalan ringan yang dapat dilewati. Deep link tidak dipaksa melewati splash/onboarding.

## 6. Kebutuhan fungsional dan acceptance criteria

### FR-01 — Beranda dan source (P0)

**Kebutuhan:** menampilkan source dari API, rekomendasi, rilis terbaru, populer, ranking, dan continue reading. Source awal menggunakan pilihan tersimpan yang masih aktif, atau source aktif pertama dari API.

**Penerimaan:** source tidak di-hardcode; source nonaktif tidak dapat dipilih untuk permintaan baru. Jika `is_unstable=true`, tampil indikator kondisi source. Section gagal dapat di-retry sendiri. Tidak mengambil seluruh feed dari semua source sekaligus ketika beranda dibuka. Continue reading disembunyikan jika tidak ada data. Rekomendasi diberi label biasa dan tidak diklaim sebagai personalisasi AI.

### FR-02 — Katalog dan pencarian (P0)

**Kebutuhan:** katalog gabungan/per source, filter source/type/status/genre, sort, pagination, dan pencarian judul/alias.

**Penerimaan:** filter dan halaman disimpan dalam URL; perubahan filter kembali ke halaman 1. Query pencarian di-trim, panjang 1–200 karakter, debounce sekitar 300 ms, dan permintaan usang dibatalkan/diabaikan. Query kosong menampilkan arahan pencarian tanpa mengirim request yang akan ditolak API. Empty state berbeda dari error.

Pencarian global hanya memakai `q`, `page`, dan `page_size`; pencarian per source memakai endpoint source-scoped. Filter genre/status/type pada katalog tidak dikirim ke endpoint pencarian karena belum didukung. UI tidak mengklaim filter global jika hanya menyaring satu halaman hasil di browser. Pencarian author/artist dan kombinasi search + filter penuh merupakan gap backend jika kelak diwajibkan.

### FR-03 — Detail dan daftar chapter (P0)

**Kebutuhan:** cover, judul, alias, sinopsis, author, artist, tipe, status, genre, rating, view, source, jumlah chapter, dan waktu update sesuai data. CTA Baca/Lanjut Baca, Bookmark, serta Koleksi saat P1 tersedia.

**Penerimaan:** field kosong mendapat fallback dan tidak direkayasa. Rating tampil sebagai data source, tanpa tombol voting. Chapter terbaru tampil di atas; tersedia urutan terbalik, pencarian nomor chapter lokal, dan lompat ke chapter terakhir dibaca. Baca pertama membuka chapter bernomor terkecil yang tersedia, bukan asumsi selalu chapter 1.

Endpoint chapter mengembalikan seluruh daftar tanpa pagination server. Untuk daftar panjang, frontend melakukan windowing/virtualisasi atau penampilan bertahap setelah satu request, tanpa mengirim parameter pagination yang tidak didukung. Badge selesai memakai data completed, bukan menganggap seluruh chapter sebelum progress pasti sudah dibaca. `total_images=0` dapat berarti gambar belum dimuat backend, bukan bukti chapter kosong.

### FR-04 — Reader vertikal (P0)

**Kebutuhan:** mode default vertikal, gambar berurutan tanpa celah, kontrol sementara, navigasi chapter, dan retry gambar.

**Penerimaan:** gambar mengikuti urutan `page`, proporsi asli dipertahankan, margin/padding antar gambar nol, dan teks komik tidak terpotong. Dimensi API dipakai untuk reservasi ruang jika tersedia. Saat dimensi kosong, pemuatan gambar tidak mereset scroll. Gambar dekat viewport diprioritaskan; prefetch awal 3–5 gambar ke depan dengan concurrency terbatas, lalu disesuaikan hasil pengukuran. Tidak memuat seluruh chapter berikutnya tanpa batas.

Tap/klik area baca menampilkan kontrol; kontrol dapat hilang setelah sekitar 3 detik tanpa aktivitas, tetapi tetap terlihat saat fokus keyboard berada di kontrol atau dialog terbuka. Retry satu gambar tidak mengulang seluruh sesi reader. Payload kosong menampilkan state tersendiri dan tidak menandai chapter selesai.

### FR-05 — Mode per halaman dan navigasi (P0)

**Kebutuhan:** pergantian vertikal/per halaman, LTR/RTL, prev/next chapter, pemilih chapter, dan keyboard.

**Penerimaan:** perpindahan mode mempertahankan gambar aktif. Tombol panah mengikuti arah baca yang dipilih, tombol navigasi memiliki label, dan shortcut tidak aktif ketika pengguna mengetik pada input. Swipe tersedia pada perangkat sentuh. Prev/next ditentukan dari daftar chapter aktual, termasuk nomor pecahan; dilarang menghitung `chapter + 1`.

Pada chapter terakhir, Next dinonaktifkan dengan keterangan jelas. Browser zoom tetap dapat digunakan. Gambar sangat panjang dalam mode per halaman tetap dapat digulir tanpa pemotongan konten.

### FR-06 — Progress, riwayat, dan continue reading (P0)

**Kebutuhan:** checkpoint lokal pada guest maupun akun; sinkronisasi ke `/library/progress/*` untuk akun.

**Penerimaan:** simpan chapter, mode, indeks gambar, offset/page index, jumlah gambar, status selesai, dan waktu lokal checkpoint. Simpan lokal maksimal sekitar 1 detik setelah posisi berubah stabil; upload akun dibatasi sekitar sekali per 5 detik saat ada perubahan, serta diusahakan ketika berpindah chapter atau halaman disembunyikan. Keberhasilan upload saat tab ditutup tidak dijamin, sehingga checkpoint tidak bergantung pada request terakhir tersebut.

Restore lintas ukuran layar mengutamakan indeks gambar yang valid; offset piksel hanya bantuan pada layout yang sesuai. Indeks disepakati zero-based untuk `page_index`/`last_read_page_item_index`/panel favorit, sedangkan `images[].page` one-based. Mapping diverifikasi dengan frontend Flutter dalam uji integrasi. Indeks usang di-clamp ke rentang gambar yang tersedia.

Riwayat akun diperbarui melalui PUT progress; tidak ada endpoint POST history baru. Continue reading berisi progress terakhir per komik; riwayat dapat memuat beberapa chapter komik yang sama. Chapter ditandai selesai hanya saat akhir konten benar-benar dijangkau dan kebijakan `mark_read_on_complete` diaktifkan, atau melalui tindakan eksplisit.

### FR-07 — Autentikasi opsional (P0; Google P1)

**Kebutuhan:** register, login email/username + password, konfirmasi email, reset password, restore session, dan logout melalui API yang ada.

**Penerimaan:** guest tetap dapat membaca dan memakai pustaka lokal. Login gagal tidak menghapus data guest. Register dengan `email_confirmation_required=true` menampilkan instruksi verifikasi dan tidak dianggap sudah login. Callback memakai URL web yang dikonfigurasi dan kontrak token verification backend. Setelah login, pengguna kembali ke tujuan internal yang valid.

Refresh session dilakukan satu kali secara terkoordinasi untuk request paralel. Jika refresh invalid, aplikasi meminta login ulang dan mempertahankan checkpoint akun di namespace akun tersebut. Tidak ada loop refresh. Google login harus memperoleh Google ID token web yang valid untuk ditukar melalui `/auth/google`; jangan menganggap endpoint tersebut menyediakan URL redirect OAuth. Konfigurasi origin/client ID dan pertukaran token web harus dibuktikan sebelum tombol diaktifkan.

### FR-08 — Bookmark dan pustaka (P0)

**Kebutuhan:** daftar/toggle bookmark, filter tipe/status, sort, ubah status bookmark, dan tab pustaka.

**Penerimaan:** guest menggunakan penyimpanan lokal; akun menggunakan API. Perubahan akun menampilkan pending lalu sukses/gagal, dengan rollback jika UI memakai optimistic update. Cegah request ganda akibat klik berulang. `PATCH .../status` yang sukses dengan `204` tidak dipaksa dibaca sebagai JSON.

Pilihan `sort=latest` pada endpoint bookmark berarti hanya bookmark dengan chapter baru, bukan semua bookmark dengan urutan terbaru. Label web harus “Ada chapter baru”. Opsi daftar keseluruhan tidak memakai filter tersebut. Badge chapter baru hanya tampil jika dapat ditentukan dari data aktual. Data antar-source tetap memakai identitas yang berbeda.

### FR-09 — Koleksi (P1)

**Kebutuhan:** buat, ganti nama, hapus, lihat isi, dan masukkan satu komik ke beberapa koleksi.

**Penerimaan:** nama nonkosong, whitespace dinormalisasi, maksimal 120 karakter, dan konflik `409` ditampilkan pada input. Pengaturan membership dari detail memakai endpoint set membership dengan `collection_ids`. Array kosong berarti menghapus seluruh membership komik tersebut. Hapus koleksi tidak menghapus komik dari katalog atau progress. Setelah respons membership `204`, state terkait diperbarui/refetch.

### FR-10 — Panel favorit (P1)

**Kebutuhan:** simpan gambar dari reader dengan catatan opsional; tampilkan dan hapus di pustaka.

**Penerimaan:** sediakan tombol/menu yang juga dapat dipakai keyboard, selain long-press. Identitas panel meliputi source, slug, chapter, dan indeks gambar. Membuka panel mengarahkan ke posisi gambar, tanpa otomatis menyatakan chapter selesai. URL gambar rusak mendapat fallback. Endpoint daftar saat ini memakai `limit` maksimal 200 tanpa pagination; jika pustaka melebihi batas, tampilkan batas tampilan, bukan klaim semua data sudah dimuat.

### FR-11 — Preferensi dan kontrol reader lanjutan (P1)

**Kebutuhan:** tema, mode default, LTR/RTL, mark read, binge mode, auto-scroll aktif/nonaktif, dan kecepatan.

**Penerimaan:** preferensi guest tersimpan lokal; akun tersinkron memakai reader preferences. Binge mode OFF tidak berpindah chapter otomatis. Saat ON, perpindahan otomatis di akhir chapter hanya terjadi sekali dan tidak mengulang di chapter terakhir. Auto-scroll hanya untuk mode vertikal, kecepatannya mengikuti rentang API 0.5–2.25, berhenti saat interaksi scroll manual atau tab disembunyikan, dan dapat dijeda dengan keyboard. Hormati preferensi reduced motion.

### FR-12 — Profil, keamanan, dan waktu baca (P1)

**Kebutuhan:** username, nama tampilan, avatar, ringkasan keamanan sesi, dan total waktu baca.

**Penerimaan:** baca/tulis profil serta unggah avatar memakai endpoint backend. Validasi ukuran/tipe file mengikuti kontrak aktual ketika implementasi. Keamanan hanya menampilkan kemampuan endpoint yang tersedia; jangan menjanjikan daftar/revoke semua perangkat atau penghapusan akun mandiri melalui endpoint admin.

Waktu baca menghitung reader aktif dan terlihat, berhenti saat tab tersembunyi atau tidak ada aktivitas lebih dari sekitar 2 menit, lalu dilanjutkan saat pengguna aktif kembali. POST delta bersifat penambahan dan belum memiliki idempotency key; request dengan hasil timeout ambigu tidak di-replay otomatis. UI menyatakan total cloud sebagai hasil yang telah dikonfirmasi; keterbatasan akurasi durasi dicatat.

### FR-13 — Relasi bookmark multi-source (P1)

**Kebutuhan:** cari kandidat source alternatif, pilih relasi, simpan, dan sinkronkan status chapter selesai.

**Penerimaan:** scan dijalankan atas tindakan pengguna, bukan setiap bookmark dibuat. Kemiripan judul tidak langsung menggabungkan data. Pengguna mengonfirmasi kandidat. Ikuti batch kandidat/link sekitar 5 item dan completed-sync maksimal 10 grup per request; default UI 5 grup. Tampilkan progress fase penyimpanan dan sinkronisasi. Posisi scroll, riwayat, dan continue reading tidak disalin antar-source.

Frontend baru tetap dapat membaca relasi yang sudah dibuat Flutter. Aksi hapus source alternatif harus membedakan relasi linked dan bookmark utama. Completed chapter panel menggunakan endpoint batch maksimal 5.000 item, bukan satu request untuk setiap chapter.

### FR-14 — Bantuan dan kondisi gagal (P1)

**Kebutuhan:** form laporan gambar/chapter bermasalah dan review aplikasi melalui helpdesk, untuk guest maupun akun.

**Penerimaan:** sertakan konteks source/komik/chapter yang sesuai schema tanpa token atau informasi sesi. Tampilkan sukses hanya setelah server mengonfirmasi. Halaman admin dan daftar laporan internal tidak ditampilkan pada web pembaca. Semua halaman memiliki loading, empty, error, dan retry yang sesuai; tidak menutup seluruh halaman hanya karena satu section gagal.

## 7. Kontrak integrasi API yang sudah ada

Base path backend: `/api/v1`. Semua path pada tabel ini relatif terhadap base tersebut. Bukti utama adalah kode router dan schema saat audit, bukan asumsi dari PRD mobile.

### 7.1 Endpoint publik

| Kebutuhan | Method dan path | Kontrak penting |
| --- | --- | --- |
| Source | `GET /sources` | List, termasuk `id`, `label`, `enabled`, jumlah katalog, dan `is_unstable`. |
| Katalog gabungan | `GET /comics` | `page`, `page_size` 1–100, `source`, `type`, `status`, `genre`, `sort`; response envelope pagination. |
| Katalog source | `GET /sources/{source}/comics` | Filter katalog; response envelope pagination. |
| Rilis terbaru | `GET /sources/{source}/comics/latest` | List; `page`, `page_size` maksimal 100; filter sesuai route, tanpa status. |
| Statistik rilis | `GET /sources/{source}/comics/latest/stats` | `period_days` 1–30; gunakan hanya jika statistik ditampilkan. |
| Populer | `GET /sources/{source}/comics/popular` | List; pagination dan filter sesuai route. |
| Rekomendasi | `GET /sources/{source}/comics/recommendations` | List; `limit` 1–12, `pool_size` 4–50; bukan personalisasi user. |
| Ranking | `GET /sources/{source}/comics/top-ranking` | List maksimal 10; filter `type`. |
| Search global/source | `GET /search`, `GET /sources/{source}/search` | `q`, `page`, `page_size` maksimal 50; title/alternative_titles. |
| Genre | `GET /genres`, `GET /genres/{slug}/comics` | Daftar genre; list komik genre memakai pagination maksimal 50 tanpa envelope total. |
| Detail | `GET /sources/{source}/comics/{slug}` | Metadata, `id`, `genres`, `total_chapters`; banyak field nullable. |
| Chapter list | `GET /sources/{source}/comics/{slug}/chapters` | List lengkap, descending chapter; tidak menerima pagination. |
| Reader | `GET /sources/{source}/comics/{slug}/chapters/{number}` | `source_name`, `chapter_number`, `images`, `total`; gambar punya `page`, `url`, `width?`, `height?`. |
| Gambar | `GET /images/proxy?url=...` | Bytes gambar; varian cover `width` 160–1440 dan `quality` 60–95. |
| Helpdesk | `POST /helpdesk/submissions` | Guest atau akun; payload mengikuti schema helpdesk. |

Sort katalog yang tersedia: `latest`, `popular`, `total_view`, `rating_high`, `az`, `za`, `relevance`. Pilihan UI hanya memakai nilai yang benar-benar didukung masing-masing route. Katalog/genre dapat memakai `/comics?genre=...` agar tetap memperoleh total pagination.

### 7.2 Endpoint autentikasi

| Method dan path | Fungsi |
| --- | --- |
| `POST /auth/register` | Register; mendukung `email_redirect_to`. |
| `POST /auth/login` | Login memakai `identifier` atau `email` dan `password`. |
| `POST /auth/google` | Pertukaran Google `id_token`, dengan access token/nonce opsional. |
| `POST /auth/refresh`, `POST /auth/logout` | Refresh session dan revoke sesi saat logout. |
| `POST /auth/email/verify` | Verifikasi `email` dan `token_hash`. |
| `POST /auth/password/forgot` | Permintaan email recovery; sukses `202` bukan error. |
| `POST /auth/password/recovery/verify` | Verifikasi recovery dan buat session reset. |
| `POST /auth/password/update` | Update password memakai bearer sesi yang valid. |
| `GET /auth/me`, `GET /auth/security` | Identitas terverifikasi dan ringkasan keamanan. |
| `GET/PATCH /auth/profile`, `POST /auth/profile/avatar` | Profil dan unggah avatar. |

### 7.3 Endpoint pustaka akun

Seluruh endpoint berikut membutuhkan `Authorization: Bearer <access_token>` dari sesi Supabase yang divalidasi backend.

| Kebutuhan | Method dan path |
| --- | --- |
| Counter pustaka | `GET /library/summary` |
| State detail | `GET /library/state/{source}/comics/{slug}` |
| Continue reading | `GET /library/progress/continue-reading?page=1&page_size=...` |
| Progress | `GET /library/progress/{source}/comics/{slug}`; `PUT /library/progress/{source}/comics/{slug}/chapters/{number}` |
| Chapter selesai | `POST /library/completed-chapters/batch` |
| Bookmark | `GET /library/bookmarks`; `PUT/DELETE /library/bookmarks/{source}/comics/{slug}` |
| Status bookmark | `PATCH /library/bookmarks/{source}/comics/{slug}/status` |
| Relasi source | `GET /library/bookmark-links/candidates`; `POST /library/bookmark-links`; `POST /library/bookmark-links/completed-sync`; `DELETE /library/bookmark-links/{source}/comics/{slug}` |
| Koleksi | `GET/POST /library/collections`; `GET/PATCH/DELETE /library/collections/{id}` |
| Membership koleksi | `PUT /library/comics/{source}/{slug}/collections`; `PUT/DELETE /library/collections/{id}/comics/{source}/{slug}` |
| Panel favorit | `GET/POST /library/favorite-scenes`; `DELETE /library/favorite-scenes/{id}` |
| Riwayat | `GET /library/history?page=...&page_size=...` |
| Preferensi | `GET/PUT /library/reader-preferences` |
| Waktu baca | `GET/POST /library/reading-time` |
| Impor guest | `POST /library/sync/import` |

`GET /library/summary` pada schema saat audit hanya menjanjikan `counts` dan `reading_time_seconds`. Contoh dalam dokumen library lama memuat embedded continue reading/preferences; frontend web harus mengambil data tersebut dari endpoint khusus dan tidak bergantung pada field contoh yang tidak ada pada schema aktual.

Envelope error memakai `message`, kadang disertai `detail`, `code`, atau `errors`. Parser juga harus menangani respons non-JSON dari proxy/gateway dan sukses `204` tanpa body. List polos tidak diperlakukan sebagai envelope `items`.

### 7.4 Aturan identitas dan URL

- Identitas komik: pasangan `(source_name, slug)`; identitas chapter menambahkan `chapter_number`. Slug sama di source berbeda tidak berarti satu record.
- Nomor chapter dapat pecahan. Gunakan representasi stabil dari nilai API untuk URL/key; encode segmen path dan query dengan benar.
- `detail_url` dan URL proxy dari API dapat absolut. Bangun navigasi frontend dari identitas; hanya normalisasi URL data ke origin backend yang telah dikonfigurasi. Jangan meneruskan URL arbitrer sebagai target fetch BFF.
- Jangan membungkus ulang URL yang sudah menunjuk `/images/proxy`. Parameter URL gambar di-encode sekali.
- Frontend tidak mengakses DB, service-role key, atau endpoint admin/scraper untuk memenuhi alur pembaca.

## 8. Data lokal, sinkronisasi, dan migrasi

### 8.1 Kepemilikan data

| Data | Guest | Login |
| --- | --- | --- |
| Katalog/detail/chapter | Backend; cache tampilan opsional | Sama |
| Progress/continue reading | Penyimpanan browser lokal | Checkpoint lokal per akun dan state cloud |
| Bookmark/koleksi/panel favorit/riwayat | Lokal | API sebagai sumber data; cache tampilan per akun |
| Preferensi reader | Lokal | Lokal + sinkronisasi API |
| Tema | Lokal | Lokal; schema cloud saat ini tidak menyediakan field tema |
| Token sesi | Tidak ada | Dikelola lapisan sesi server web; tidak dicampur dengan storage pustaka |

IndexedDB direkomendasikan untuk state guest/checkpoint dan antrean progress; localStorage cukup untuk preferensi kecil seperti tema. Tidak perlu memilih library penyimpanan tambahan sebelum implementasi. Schema lokal harus berversi dan memiliki key guest/akun yang terpisah. Jika storage ditolak/penuh, tampilkan bahwa perubahan hanya tersedia selama sesi berjalan.

### 8.2 Kebijakan sinkronisasi

1. Reading progress selalu membuat checkpoint lokal sebelum mencoba cloud. Untuk satu identitas, antrean hanya menyimpan checkpoint terbaru, sehingga scroll tidak menghasilkan antrean tak terbatas.
2. Bookmark/koleksi/panel favorit akun bersifat online-write pada MVP. Saat offline, tampilkan cache jika ada dan jelaskan bahwa perubahan akun memerlukan koneksi. Jangan menampilkan mutation gagal sebagai sukses permanen.
3. Saat membuka di perangkat lain, ambil state cloud terbaru. Data privat tidak disimpan dalam cache bersama Next.js/CDN.
4. API PUT progress tidak menerima versi konflik/client timestamp. Karena itu MVP tidak menjanjikan merge otomatis berdasarkan waktu antarperangkat. Sebelum replay checkpoint tertunda setelah reconnect, fetch cloud; jika cloud berubah sejak baseline lokal, minta pengguna memilih posisi perangkat ini atau posisi akun untuk komik terkait.
5. Jika perubahan benar-benar bersamaan pada dua perangkat, write terakhir yang diterima backend dapat menang. Penyelesaian konflik atomik memerlukan perubahan kontrak backend dan berada di luar pekerjaan frontend ini.
6. Logout membersihkan sesi dan cache tampilan akun dari UI, lalu kembali ke namespace guest. Checkpoint tertunda akun tidak diimpor ke guest atau akun lain; namespace privat hanya dapat dipulihkan setelah akun yang sama login kembali.

### 8.3 Migrasi guest

- Setelah login dan hanya bila ada data guest, tawarkan impor dengan jumlah data dan pilihan kategori atau lewati. Jangan mengunggah otomatis tanpa pilihan pengguna.
- Bandingkan progress akun dan guest; konflik posisi harus ditunjukkan karena payload import tidak membawa timestamp resolusi konflik.
- Gunakan `/library/sync/import`; patuhi batas schema: maksimal 2.000 item per kategori, 200 koleksi, 1.000 komik per koleksi, dan 10.000 total item per snapshot. Jika perlu dibagi, tampilkan hasil per batch dan kategori.
- Simpan catatan migrasi lokal per akun/snapshot, dan bersihkan hanya item yang telah dikonfirmasi berhasil. Jika hasil request tidak diketahui akibat timeout, rekonsiliasi dengan cloud sebelum mengulang.
- MVP tidak mengimpor `reading_time_seconds` guest; kirim nilai 0. Implementasi import saat ini menjumlahkan durasi sehingga replay dapat menghitung ganda. Migrasi durasi memerlukan keputusan idempotensi terpisah.
- File offline tidak menjadi bagian migrasi MVP. Data di browser berbeda tidak otomatis dapat diakses tanpa akun.

## 9. Rancangan teknis Next.js

### 9.1 Stack dan prinsip

- Next.js stable terbaru pada waktu implementasi, App Router, TypeScript, Tailwind CSS, dan ESLint melalui generator resmi.
- Server Components untuk halaman katalog/detail publik; Client Components untuk reader, state browser, filter interaktif, dan pustaka guest.
- Lapisan adapter API bertipe memisahkan bentuk respons backend dari model tampilan. Mapping snake_case tidak dilakukan berulang dalam komponen.
- Route Handlers web menjadi lapisan BFF terbatas untuk sesi dan request akun. Ini bukan penambahan kontrak backend FastAPI atau implementasi ulang business logic.
- Routing, URL query, dan native fetch dipakai terlebih dahulu. Library state/query tambahan dipilih bila ada kebutuhan konkret dan dokumentasinya diambil melalui Context7.
- Deployment memerlukan runtime yang mendukung Next.js server/Route Handlers sesuai rancangan ini. Static export murni memerlukan rancangan sesi/data yang berbeda.

### 9.2 Scaffolding resmi — wajib pada tahap implementasi

Pada audit 24 Oktober 2026, registry npm mengembalikan `next@latest=16.4.3` dan `create-next-app@latest=16.4.3`, keduanya dengan engine Node.js `>=20.9.0`. Angka tersebut adalah snapshot, bukan versi yang harus dipaksakan ketika implementasi dimulai. Gunakan Node.js LTS yang masih didukung dan memenuhi engine versi aktual.

Urutan wajib:

1. Periksa Node.js/npm yang tersedia dan `npm view next@latest version engines --json` serta `npm view create-next-app@latest version engines --json`.
2. Ambil dokumentasi instalasi/CLI yang berlaku melalui Context7; periksa `create-next-app@latest --help` untuk opsi aktual sebelum menjalankan generator.
3. Jalankan generator resmi dari root repo ke direktori baru `web/`, dengan instalasi dependency aktif. Contoh perintah untuk opsi yang diverifikasi pada audit ini:

```powershell
rtk proxy npx --yes create-next-app@latest web --typescript --tailwind --eslint --app --src-dir --import-alias '@/*' --use-npm --disable-git --yes
```

4. `--disable-git` menjaga agar `web/` tidak menjadi repo Git terpisah. Jika `web/` sudah berisi pekerjaan pengguna, periksa dan integrasikan tanpa menimpa isinya.
5. Biarkan generator membuat `package.json`, lockfile, konfigurasi TypeScript/Next.js/ESLint/Tailwind, dan starter app. Agent hanya menyesuaikan hasil generator sesudah instalasi selesai. Dilarang mengganti tahap ini dengan membuat berkas scaffold secara manual atau memakai `--skip-install`.
6. Catat command, versi Node/npm/Next/React/generator yang benar-benar terpasang, serta hasil instalasi. Pertahankan lockfile untuk build reproduktif. Jangan memasukkan canary/RC tanpa keputusan khusus.
7. Jalankan starter hasil generator sebelum mengubah fitur, kemudian validasi lint, typecheck, production build, dan tampilan browser. Pada versi modern, gunakan ESLint CLI sesuai scaffold; jangan mengasumsikan `next lint` tersedia.

Perintah di atas **belum dijalankan** pada tahap PRD ini, sesuai keputusan D-06. Jika akses registry/install gagal pada tahap implementasi, laporkan kegagalan dan jangan menggantinya dengan scaffold buatan agent.

### 9.3 Struktur implementasi yang diusulkan

```text
web/                         # dibuat create-next-app terlebih dahulu
  src/app/                   # route publik, akun, dan Route Handlers web
  src/components/            # komponen UI bersama
  src/features/              # catalog, comic, reader, library, auth, settings
  src/lib/api/               # adapter endpoint, DTO, error mapping
  src/lib/session/           # sesi server web dan forwarding bearer
  src/lib/storage/           # namespace guest/akun, checkpoint, migrasi schema
  public/                    # aset brand yang sesuai lisensi proyek
```

Struktur ini rencana organisasi setelah generator selesai, bukan file scaffold yang dibuat pada tahap PRD.

### 9.4 Konfigurasi, sesi, dan deployment

- `BACKEND_API_BASE_URL`: server-only, sudah mencakup `/api/v1`; kandidat development `http://127.0.0.1:8000/api/v1`. URL produksi belum ditentukan.
- `PUBLIC_SITE_URL`: origin web untuk metadata/canonical dan callback; belum ditentukan.
- `NEXT_PUBLIC_GOOGLE_CLIENT_ID`: hanya jika Google login web diaktifkan; client ID bukan secret. Jangan menyalin client ID mobile tanpa verifikasi audience/origin.
- Sesi direkomendasikan memakai cookie identifier opaque `HttpOnly`, `Secure` di production, dan kebijakan SameSite yang sesuai callback. Token backend disimpan pada lapisan sesi server, bukan localStorage. Media penyimpanan sesi server/TTL dipilih sesuai hosting sebelum implementasi auth; serverless/multi-instance memerlukan penyimpanan bersama yang sesuai.
- Route Handler untuk mutation memvalidasi origin/CSRF, meneruskan bearer server-side, dan membatasi upstream ke path backend yang diizinkan. Tidak membuat open proxy.
- Akses JSON melalui server/BFF mengurangi kebutuhan CORS langsung. Jika browser mengakses backend lintas origin, origin produksi harus ditambahkan pada konfigurasi backend; kode CORS saat audit hanya mengizinkan localhost/127.0.0.1 dan `null`.
- Origin gambar harus dapat dijangkau browser melalui HTTPS atau jalur same-origin yang terkontrol. Backend internal saja tidak cukup jika payload masih berisi URL gambar internal yang dipakai browser.
- Backend membutuhkan konfigurasi redirect email/recovery dan Google untuk origin web. Perubahan konfigurasi ini merupakan dependency integrasi, tanpa membangun auth backend baru.
- Simpan secret hanya pada server/runtime. Service-role key, JWT secret, dan database URL tidak boleh muncul dalam bundle web atau variabel `NEXT_PUBLIC_*`.

### 9.5 Fetch, cache, dan gambar

- Kebijakan cache ditentukan eksplisit, tidak mengandalkan default framework. Kandidat TTL: source/genre 300 detik, katalog/detail/feed publik 60 detik. Nilai ini dapat disesuaikan setelah pengukuran freshness dan beban.
- Progress, session, profil, pustaka akun, dan semua mutation memakai `no-store` serta respons privat. Data akun tidak boleh masuk cache publik.
- Payload chapter mula-mula diambil secara dinamis karena backend dapat melakukan lazy image loading. Loading yang lama menampilkan “Menyiapkan chapter”; error `503` menyediakan retry terbatas/manual, bukan loop request.
- Cover menggunakan proxy backend yang sudah mendukung resize. Hindari dua lapisan optimasi tanpa manfaat terukur. Bila memakai `next/image`, tetapkan host/path `remotePatterns` yang sempit dan perlakukan query proxy dinamis dengan sengaja.
- Gambar chapter mempertahankan kualitas/rasio; gunakan `<img>` terkontrol atau `Image` dengan `unoptimized` bila sesuai. Default image optimizer Next.js tidak meneruskan header autentikasi; jangan menganggapnya dapat mengambil gambar privat secara otomatis.
- Timeout awal yang diusulkan: 15 detik untuk JSON biasa dan 60 detik untuk payload reader yang mungkin memuat gambar secara lazy. Verifikasi terhadap batas hosting sebelum ditetapkan. Timeout menampilkan opsi retry dan tidak menghapus checkpoint.

## 10. Gap, dependency, dan risiko integrasi

| Temuan terverifikasi | Dampak | Penanganan PRD |
| --- | --- | --- |
| Web belum memiliki scaffold Next.js | Belum ada aplikasi web yang bisa di-build | Generator resmi pada tahap berikutnya; belum dilakukan sekarang. |
| Search hanya judul/alias, tanpa filter katalog | UX search berbeda dari katalog | Pisahkan kontrol; jangan menjanjikan search author atau filter server yang tidak tersedia. |
| Daftar chapter tidak dipaginasi server | Payload besar pada judul panjang | Windowing render frontend; ukur payload; perubahan API terpisah jika dibutuhkan. |
| Summary schema lebih kecil daripada contoh dokumen library | Risiko data `undefined` di beranda | Ikuti schema kode dan endpoint khusus. |
| PUT progress tidak memiliki mekanisme versi konflik | Write serentak dapat saling menimpa | Checkpoint lokal, rekonsiliasi sebelum replay, dan batasan last-write yang jelas. |
| Import waktu baca bersifat penambahan | Retry dapat menghitung ganda | Tidak mengimpor durasi guest pada MVP. |
| Google endpoint menukar ID token, bukan redirect OAuth web | Tidak otomatis siap dipakai browser | Validasi token web, client ID, origin, dan konfigurasi provider. |
| Konfigurasi CORS baru untuk lokal | Browser produksi dapat ditolak | BFF/same-origin dan verifikasi konfigurasi deployment. |
| URL gambar dapat absolut/internal | Halaman terbuka tetapi gambar gagal | Normalisasi origin yang diizinkan dan uji dari browser deployment. |
| Favorite scenes memakai limit maksimal 200 | Belum ada akses paginasi semua panel | Nyatakan batas tampilan; pagination penuh memerlukan pekerjaan backend terpisah. |
| Downloads API hanya intent/status | Status cloud tidak membuktikan file ada di browser | Offline penuh P2; file/manifest browser harus diverifikasi lokal. |
| PushPlatform hanya `android` | Web push tidak bisa memakai kontrak ini | P2 dengan perubahan backend; jangan mendaftarkan web sebagai Android. |

Belum dilakukan request ke backend hidup pada tahap ini. Audit memverifikasi ketersediaan dan bentuk endpoint dari kode; konektivitas, data aktual, OAuth web, latensi scraper, dan perilaku lintas perangkat tetap memerlukan pengujian saat implementasi.

## 11. Kebutuhan nonfungsional

| ID | Kebutuhan dan target |
| --- | --- |
| NFR-01 | Desktop-first dan responsif tanpa overflow horizontal halaman pada viewport target; gambar reader boleh memakai kontrol zoom browser. |
| NFR-02 | Target halaman katalog/detail: LCP ≤2,5 detik, CLS ≤0,1, INP ≤200 ms pada persentil 75 setelah ada data lapangan. Sebelum rilis gunakan lab profile yang dicatat, minimal desktop dan emulasi jaringan ponsel. |
| NFR-03 | Daftar chapter diuji dengan minimal 2.000 item dan reader dengan minimal 100 gambar, termasuk gambar tinggi dan dimensi kosong. Tidak ada fetch/render tanpa batas atau kehilangan posisi. |
| NFR-04 | Aksesibilitas mengacu WCAG 2.2 AA: fokus terlihat, dialog terkelola, label kontrol, target interaksi memadai, kontras, reduced motion, dan navigasi keyboard. |
| NFR-05 | Halaman publik memiliki title/description, canonical per source/slug, metadata berbagi, serta respons 404 yang benar. Halaman akun/pustaka tidak diindeks; kebijakan indeks reader diputuskan sebelum rilis publik. |
| NFR-06 | Scope data akun terisolasi pada server, cache, dan storage browser. Sinopsis dirender sebagai teks atau disanitasi bila kelak menerima markup. |
| NFR-07 | Bahasa Indonesia konsisten, format waktu `id-ID`, dan informasi source terlihat. Timestamp API dihormati sebagai waktu ber-offset, bukan string lokal tanpa zona. |
| NFR-08 | Browser target: Chrome, Edge, Firefox desktop dan Safari, plus Chrome Android/Safari iOS versi stabil yang relevan saat implementasi. Catat versi aktual ketika diuji. |
| NFR-09 | Log error mencatat endpoint kategori/status dan konteks yang diperlukan tanpa password, bearer token, refresh token, atau isi callback rahasia. |
| NFR-10 | Cache tampilan bukan jaminan offline penuh. Saat koneksi putus, sampaikan mana data lokal dan mana tindakan yang perlu jaringan. |

## 12. Pengukuran produk

Metrik yang diusulkan: keberhasilan buka chapter, kegagalan gambar, waktu dari klik Baca sampai gambar pertama terlihat, keberhasilan restore checkpoint, keberhasilan sync, dan penyelesaian alur bookmark/koleksi/panel favorit.

Sebelum provider analitik dipilih, ukur melalui pengujian dan logging yang telah disanitasi. Integrasi analitik eksternal dan target retensi tidak diasumsikan sudah disetujui. Jangan mencatat judul/riwayat baca yang terikat identitas akun tanpa keputusan privasi produk yang jelas.

## 13. Rencana implementasi dan validasi

| Tahap | Hasil yang dapat diperiksa | Gate |
| --- | --- | --- |
| 0. Produk | PRD ini, cakupan, daftar gap, keputusan deployment/backend yang masih terbuka | Tidak memasang scaffold pada tahap PRD. |
| 1. Instalasi | `web/` dari `create-next-app@latest`, dependencies terpasang, versi/command tercatat | Starter berjalan di browser dan production build berhasil. |
| 2. Alur publik | Shell desktop, beranda, katalog, search, detail, chapter list | Memakai API nyata; loading/empty/error/404 teruji. |
| 3. Reader dan guest | Dua mode reader, prev/next, checkpoint, bookmark, riwayat lokal | Reload/deep link, chapter pecahan, gambar gagal, resize, dan keyboard lolos. |
| 4. Akun dan sync | Auth email, sesi web, pustaka akun, continue reading, migrasi | Dua akun terisolasi; dua perangkat termasuk Flutter; refresh/recovery/logout dan konflik sync teruji. |
| 5. Fitur P1 | Koleksi, panel favorit, preferensi lanjutan, profil, relasi source, helpdesk, Google setelah konfigurasi valid | Skenario fitur dan kegagalan masing-masing lolos. |
| 6. Kesiapan rilis | Deployment staging dan review UX/performa/aksesibilitas | URL, gambar HTTPS, session store, callback auth, dan hosting runtime tervalidasi. |

Skenario acceptance minimum saat implementasi:

1. Browse → detail → baca chapter → refresh → lanjut pada gambar yang sama sebagai guest.
2. Bookmark/koleksi/panel favorit lokal bertahan setelah reload; storage ditolak/penuh menampilkan status yang jujur.
3. Login akun A → impor guest → buka di browser kedua/Flutter → lihat data yang telah dikonfirmasi tersimpan.
4. Logout A → login B → tidak ada data A tampil sebagai data B atau guest.
5. Koneksi terputus saat membaca → checkpoint tetap ada → reconnect merekonsiliasi cloud sebelum replay.
6. Chapter 10, 10.5, 11 dapat dinavigasi dalam kedua arah; pergantian vertical/paged dan resize menjaga gambar aktif.
7. `401` memicu satu refresh; `404`, `409`, `422`, `503`, `504`, gambar gagal, respons non-JSON, dan sukses `204` ditangani sesuai konteks.
8. Jika cloud memiliki bookmark linked dari Flutter, web memahami relasinya dan tidak membuat penggabungan otomatis baru.
9. Import timeout tidak menghapus guest atau menggandakan reading time; completed-sync tidak menyalin posisi scroll.
10. Pencarian query panjang/cepat dan pergantian filter tidak menampilkan hasil request lama sebagai hasil terkini.
11. Semua alur utama dapat dioperasikan dengan keyboard; reader, dialog, dan form memiliki fokus yang masuk akal.
12. Validasi memakai backend hidup dengan data representatif. Mock/fixture boleh untuk pengujian terarah, tetapi tidak menjadi bukti bahwa integrasi produksi telah selesai.

Lint, typecheck, dan production build wajib sesudah implementasi. Unit test dipusatkan pada mapping identitas, chapter pecahan, checkpoint/konflik, dan migrasi yang rawan kehilangan data; browser test mencakup alur membaca dan akun. PRD ini sendiri tidak membutuhkan menjalankan suite Flutter/backend.

## 14. Keputusan terbuka dan pertanyaan lanjutan

Pertanyaan dasar telah dijawab dan dicatat pada D-01 sampai D-06. Hal berikut sengaja belum dikunci agar tidak mengarang keputusan infrastruktur atau produk:

| ID | Pertanyaan | Kapan dibutuhkan |
| --- | --- | --- |
| Q-01 | URL backend development/staging/production dan contoh komik/chapter yang dapat dipakai menguji integrasi? | Sebelum integrasi API hidup. |
| Q-02 | Hosting web: Vercel, server/container sendiri, atau platform lain; domain publiknya apa? | Sebelum menetapkan session store, timeout, callback, dan deployment. |
| Q-03 | Apakah Google login harus aktif pada rilis pertama, dan siapa yang menyediakan konfigurasi OAuth web? | Sebelum menyelesaikan auth P1. |
| Q-04 | Apakah download offline/PWA perlu dinaikkan ke MVP, atau tetap tahap berikutnya sebagaimana pembagian awal? | Sebelum mengubah cakupan atau estimasi. |
| Q-05 | Apakah akan ada iklan, donasi, premium, atau tetap tanpa monetisasi untuk rilis awal? | Sebelum rancangan final ruang promosi dan peluncuran. |
| Q-06 | Apakah halaman reader perlu diindeks mesin pencari, dan apakah ada halaman kebijakan/kontak publik yang wajib? | Sebelum rilis publik dan sitemap/robots final. |

## 15. Referensi dan bukti audit

### 15.1 Repo

- [Ringkasan aplikasi](../README.md) dan [PRD mobile](../prd_tonztoon.md).
- [Walkthrough frontend](walkthrough_frontend.md), [tema Flutter](../frontend/lib/src/core/app_theme.dart), dan [fitur Flutter](../frontend/lib/src/features/).
- [Router aggregator](../backend/app/api/router.py), [katalog](../backend/app/api/v1/comics.py), [source/reader](../backend/app/api/v1/sources.py), [search](../backend/app/api/v1/search.py), dan [genre](../backend/app/api/v1/genres.py).
- [Schema source](../backend/app/schemas/source.py), [schema chapter](../backend/app/schemas/chapter.py), [schema komik](../backend/app/schemas/comic.py).
- [Router auth](../backend/app/api/v1/auth.py), [schema auth](../backend/app/schemas/auth.py), dan [panduan auth](../backend/docs/supabase_auth_setup.md).
- [Router library](../backend/app/api/v1/library.py), [schema library](../backend/app/schemas/library.py), [service library](../backend/app/services/library_service.py), dan [kontrak library](../backend/docs/library_api_contract.md).
- [Proxy gambar](../backend/app/api/v1/images.py), [error API](../backend/app/api/errors.py), [helpdesk](../backend/app/api/v1/helpdesk.py), [CORS/backend bootstrap](../backend/app/main.py).
- [Kontrak push](../backend/docs/push_notification_api_contract.md) dan [schema notifikasi](../backend/app/schemas/notification.py).

Jika dokumentasi lama dan kode berbeda, router/schema aktual menjadi acuan untuk tahap implementasi, lalu kontrak diverifikasi kembali terhadap OpenAPI backend hidup.

### 15.2 Dokumentasi framework dan versi

Context7: library `/vercel/next.js`, dipilih setelah `resolve-library-id`; kueri terpisah untuk instalasi resmi/CLI, fetch dan cache data backend, serta konfigurasi gambar remote. Hasil merujuk dokumentasi resmi dan kode Next.js, sebagian pada branch canary. Karena itu opsi generator dan versi stable tetap harus diverifikasi saat instalasi; tidak semua default branch canary boleh diasumsikan berlaku pada stable yang terpasang.

- [Dokumentasi resmi instalasi](https://github.com/vercel/next.js/blob/canary/docs/01-app/01-getting-started/01-installation.mdx).
- [Referensi create-next-app](https://github.com/vercel/next.js/blob/canary/docs/01-app/03-api-reference/06-cli/create-next-app.mdx).
- [Referensi fetch/cache](https://github.com/vercel/next.js/blob/canary/docs/01-app/03-api-reference/04-functions/fetch.mdx).
- [Referensi Image/remotePatterns](https://github.com/vercel/next.js/blob/canary/docs/01-app/03-api-reference/02-components/image.mdx).
- [Self-hosting dan cache privat](https://github.com/vercel/next.js/blob/canary/docs/01-app/02-guides/self-hosting.mdx).
- Versi registry diverifikasi melalui `npm view next@latest version engines --json` dan `npm view create-next-app@latest version engines --json` pada 24 Oktober 2026. Ini verifikasi metadata, bukan bukti framework telah diinstal atau aplikasi telah diuji.
