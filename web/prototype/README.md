# Prototype HTML TonzToon Admin

**33 halaman HTML**, termasuk Overview, berdasarkan [PRD 1.4](../../docs/prd_web_admin_monitoring.md) dan [DESIGN.md revisi 12](../../DESIGN.md). Konten awal tersedia langsung dalam HTML; Tailwind CSS menyediakan style bersama. Pengguna mengizinkan JavaScript untuk interaksi prototype pada 25 Oktober 2026. Satu [prototype.js](prototype.js) menambahkan interaksi contoh tanpa framework atau koneksi API backend.

## Membuka prototype

Buka [index.html](index.html) langsung di Chrome modern. HTTP lokal disarankan untuk pengukuran transfer file reader. Dari root repository:

```powershell
rtk proxy python -m http.server 4173 --bind 127.0.0.1
```

Buka [Overview lokal](http://127.0.0.1:4173/web/prototype/). CSS terkompilasi, vendor SimpleBar, dan tiga placeholder reader disertakan; Node tidak diperlukan untuk melihat prototype. Inter memakai fallback font sistem saat font eksternal tidak tersedia. Semua data dan akun berlabel contoh.

## Peta halaman dan cakupan PRD

| Modul | Halaman | Interaksi contoh |
| --- | --- | --- |
| Login | [Login](login.html) | Validasi, simulasi 401/403/sesi kedaluwarsa, pilihan profil izin |
| Monitoring | [Overview](index.html) | Select environment, pill waktu, tab grafik, pencarian/sort/reset endpoint; KPI, grafik, tabel dan popover mengikuti filter; URL/konteks investigasi dipertahankan |
| Endpoint | [Inventaris](endpoints.html), [detail](endpoint-detail.html) | Search, method/group/environment/kelas HTTP/rentang, sort, pagination, grafik bucket, histogram, kontrak route |
| Request | [Log](requests.html), [detail](request-detail.html) | Filter status/outcome/scope/route/durasi/waktu, feed contoh start/pause, buffer, clear lokal, korelasi |
| Runtime | [Log](runtime-logs.html), [detail](runtime-log-detail.html) | Filter level/jenis/logger/instance/waktu/request, buffer, autoscroll, traceback tersanitasi, gap/partial state |
| Health | [Probe](health.html) | Liveness/readiness/coverage, hasil probe contoh, data hilang tetap tidak diketahui |
| Alert | [Insiden](alerts.html), [detail](alert-detail.html) | Filter status, timeline firing/pending/resolved/unknown, investigasi; tanpa rule editor atau mute produksi |
| Katalog | [Komik](comics.html), [detail](comic-detail.html), [editor](comic-edit.html) | Search/filter/sort/page, tambah/edit metadata lokal, source versus override, arsip/pulih |
| Chapter | [Daftar](chapters.html), [detail](chapter-detail.html), [editor](chapter-edit.html) | Identitas komik+nomor chapter, termasuk pecahan; tambah/edit URL JSON, validasi, arsip/pulih |
| Genre | [Genre](genres.html) | Search/filter, tambah/edit modal lokal, keunikan slug |
| Source | [Registry](sources.html), [detail](source-detail.html) | Search, status source aktif/backup, metadata readonly dan link komik/endpoint |
| Akun | [Daftar](accounts.html), [detail](account-detail.html), [editor](account-edit.html), [library](account-library.html) | Akun nonadmin, tambah/edit lokal, ban/aktifkan; library baca saja dan data pribadi disamarkan |
| Helpdesk | [Daftar](helpdesk.html), [detail](helpdesk-detail.html) | Filter kategori/status, note dan perpindahan status lokal dengan preview |
| Audit | [Daftar](audit.html), [detail](audit-detail.html) | Filter aktor/aksi/hasil/waktu/request, diff aman, event simulasi perubahan sesi |
| Preview Komik | [Feed](comic-preview.html), [detail/chapter](preview-detail.html), [reader](preview-reader.html) | Feed/search/source, chapter lengkap, navigasi chapter, load/decode file lokal, retry/stop/reset/inspector |
| Flow | [Alur data](data-flow.html) | 13 node, 15 edge, search/domain, inspector node/edge, overlay pengukuran contoh, zoom/pan/fit/list |
| ERD | [Model data](data-model.html) | Empat ERD PRD, 27 tabel, 21 relasi FK; search tabel/kolom, existing/usulan, inspector, zoom/list |

Semua halaman memakai logo, dua tema, token, surface berlapis, sidebar 80/240 px, drawer, dan navigasi bersama. Diagram merupakan viewer readonly HTML/SVG; React Flow digunakan nanti pada aplikasi Next.js sesuai PRD.

## Mencoba alur

Pada Overview, coba **5 menit / 15 menit / 1 jam / 24 jam**, **Production / Staging**, lalu tab **Latensi / Status HTTP**. KPI dan tabel grafik berubah. Staging tanpa data menampilkan metrik belum tersedia; tidak meminjam status sehat Production. Cari route, ubah urutan, buka detail, lalu kembali ke filter semula. Cutoff mengikuti jam simulasi dan seluruh angka berlabel contoh lokal.

1. Buka Katalog, cari komik lalu buka detail. Edit judul, tekan **Periksa perubahan**, lalu konfirmasi. Judul sumber tetap terpisah dari override. Perubahan contoh muncul pada daftar dan audit sesi.
2. Dalam editor, pilihan hasil simpan contoh menyediakan validasi gagal, konflik, atau hasil belum pasti. Draft dapat dipulihkan; hasil belum pasti harus direkonsiliasi sebelum dianggap berhasil. Tambah komik/chapter memakai identitas unik.
3. Buka Request atau Log runtime. Mulai demo bersama, jeda tampilan, tambahkan event, periksa detail, dan bersihkan tampilan. Clear tidak menghapus backend. Buffer lokal dibatasi 1.000 event.
4. Buka Preview Komik, pilih source/komik, cari 12.5, lalu baca chapter. **Periksa seluruh page chapter ini** menguji tiga SVG placeholder lokal. Pilih skenario untuk attempt berikutnya, retry, periksa inspector dan timeline. HTTP aktual file lokal dibedakan dari error simulasi.
5. Buka Flow/ERD. Cari node/tabel/kolom, pilih untuk inspector, coba zoom/fit/pan atau alternatif daftar. Rancangan migration harus disertakan secara eksplisit; chapters.images tetap JSONB, bukan tabel baru.
6. Buka **Opsi pratinjau** di bawah halaman untuk normal/loading/kosong/error/stale/denied/partial dan profil izin. **Reset data contoh** menghapus perubahan lokal sesi, bukan data backend.

## Data browser dan izin contoh

Session storage menyimpan perubahan contoh, draft aman, audit simulasi, profil izin, konteks preview, dan preferensi tema/sidebar. Menutup sesi browser mengakhiri data tersebut. Ketika storage ditolak, halaman memakai fallback memori. Login/password/email tidak disimpan dalam draft, URL, diff, atau audit contoh. Clipboard yang ditolak menyediakan dialog salin manual.

Tema diterapkan sebelum tampilan pertama: setiap head mempunyai meta color-scheme, style critical background, lalu bootstrap inline sinkron sebelum styles.css. Bootstrap membaca kunci tema existing; prototype.js tetap defer dan hanya menyelaraskan kontrol/runtime. Perubahan tema sistem tetap dipantau. Transisi dinonaktifkan selama inisialisasi, lalu dipulihkan setelah dua frame; halaman tidak disembunyikan untuk menutupi FOUC. Pertahankan head ini ketika membuat halaman berikutnya.

Profil izin mengubah menu serta akses halaman langsung untuk demonstrasi. Ini bukan otorisasi aman: seluruh HTML contoh dapat dibaca. Tidak ada token autentikasi, promosi admin, hard delete, transaksi, telemetry, request produksi, atau pengiriman pesan eksternal.

Reader memakai tiga file [placeholder lokal](assets/reader-page-1.svg), bukan gambar komik asli. Melalui HTTP lokal ia mengukur status, MIME, body bytes, durasi dan decode. Pada file:// ia mengukur decode tanpa mengarang status HTTP. Concurrency maksimum tiga, lazy load/prefetch hanya file lokal, sesi lama dibatalkan, blob URL dibersihkan. Angka transfer lokal bukan benchmark backend/proxy. Reader tidak mengubah bookmark/progress akun.

## Build stylesheet

Dari web/prototype:

```powershell
rtk proxy npm ci
rtk proxy npm run build
rtk proxy node --check prototype.js
```

Gunakan `rtk proxy npm run watch:css` saat mengedit. Edit [styles.input.css](styles.input.css); [styles.css](styles.css) adalah hasil compiler. Build menyalin distribusi/lisensi SimpleBar 6.3.3 dan mengompilasi Tailwind CSS 4.3.3. @source memindai semua HTML dan prototype.js. Mapping class status memakai nama utility lengkap. Tidak ada CLI desain, framework, atau skrip pemeriksa desain tambahan.

## SimpleBar dan fallback

Autohide desktop/drawer memakai vendor lokal melalui HTML API data-simplebar, data-simplebar-auto-hide="true" dan data-simplebar-aria-label. Header/footer tidak ikut bergulir. JavaScript SimpleBar dan prototype.js dapat dinonaktifkan: konten awal, tautan halaman, checkbox tema/sidebar, details, serta popover tetap tersedia; pencarian/form/simulasi perlu JavaScript.

API Tailwind, SimpleBar, constraint validation, dialog, fetch/abort dan image decode diperiksa melalui Context7. Rujukan: [Tailwind source detection](https://tailwindcss.com/docs/detecting-classes-in-source-files), [SimpleBar](https://github.com/Grsmto/simplebar/tree/master/packages/simplebar#readme), [MDN dialog](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/dialog), [MDN image decode](https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/decode).

## Konsistensi dan bukti

Gunakan [DESIGN.md](../../DESIGN.md) sebagai satu acuan. Tambahkan HTML dengan shell yang sama, pilih susunan berdasarkan tugas, dan gunakan komponen/token existing. Hindari menyalin empat KPI Overview ke setiap modul. Interaksi contoh tetap pada prototype.js; aplikasi sesungguhnya dibangun di Next.js.

Revisi 12 (26 Oktober 2026) menerapkan daily driver Anti-slop + Taste pada kontrol bersama: navigasi aktif netral, tombol radius 8 px, tab grafik bergaris bawah, segmented waktu netral, dan teks minimum 11 px. Pengguna memilih penyesuaian ini setelah konflik dengan house style Taste dijelaskan. [Aturan alur desain](../../.agents/rules/ui-design-flow.md) membedakan scaffolding desain, scaffolding teknis, dan pengembangan UI; migrasi prototype ke framework dengan fondasi existing tetap daily driver. Bukti terbaru: [sebelum dark](screenshots/taste-revision-12/before-dark.jpg), [sesudah light](screenshots/taste-revision-12/after-light.jpg), [sesudah dark](screenshots/taste-revision-12/after-dark.jpg), [mobile light](screenshots/taste-revision-12/after-mobile-light.jpg), dan [mobile dark](screenshots/taste-revision-12/after-mobile-dark.jpg). Cakupan pengujian terbaru berada pada bagian revisi 12 di [QA](QA.md); screenshot dan angka pengujian revisi sebelumnya di bawah merupakan riwayat.

[QA](QA.md) dan [Delivery Gate](../../docs/admin_design_review.md) mencatat pemeriksaan versi ini serta batas yang belum diuji. [Screenshot modul](screenshots/) mencakup sebelas halaman pada kedua tema, reader mobile, serta state Overview latensi dan Staging. Delapan screenshot Overview diperbarui: [light](preview-light.png), [dark](preview-dark.png), [collapsed light](preview-collapsed-light.png), [collapsed dark](preview-collapsed-dark.png), [mobile light](preview-mobile-light.png), [mobile dark](preview-mobile-dark.png), [drawer light](preview-drawer-light.png), [drawer dark](preview-drawer-dark.png).

## Demo terhubung revisi 10

Buka panel **Demo lokal terhubung** di atas konten. Pada mobile, tekan judul panel untuk membuka kontrol.

1. Pilih **Latensi reader tinggi**, lalu **Jalankan skenario**. Insiden melewati pending ke firing berdasarkan observasi. Buka Request log dari Overview, pilih request, lalu runtime terkait dan endpoint. ID dan metrik berasal dari sesi yang sama.
2. Coba **HTTP 5xx meningkat**, **API tidak terjangkau**, atau **Telemetry terputus**. API down tidak mengarang access log; probe independen tetap gagal. Telemetry gap menahan observed_at, menurunkan coverage, dan menjaga insiden sebagai unknown.
3. Pilih **Normal / pulih**, lalu **Jalankan skenario** untuk memajukan 390 detik jam demo. Pemulihan mengikuti rolling window dan hold, bukan sekadar mengganti badge.
4. **Mulai demo** menghasilkan event tiap dua detik nyata, setara 30 detik jam demo. Navigasi/reload tab yang sama mempertahankan sesi. **Jeda demo** menghentikan generator; **Jeda tampilan** pada log hanya menahan daftar/buffer. Kirim request atau tambah lifecycle event, lanjutkan tampilan, clear lalu tampilkan riwayat.
5. Simpan perubahan katalog/akun/helpdesk, buka audit, lalu request dan runtime operasi yang sama. Konflik/validasi gagal menghasilkan observasi 409/422; payload form/credential tidak dimasukkan ke telemetry.
6. Buka Preview → komik → chapter → reader. Attempt gambar lokal, kegagalan dan retry dapat dilihat di request/runtime melalui Run ID. HTTP lokal aktual tetap dibedakan dari status skenario.

Baseline awal: generator dijeda, 1.000 request historis demo, 600 di 15 menit terakhir. Request/runtime/probe masing-masing maksimum 1.000; rolling window dan eviction dapat mengurangi jumlah terlihat. Coverage membedakan retensi dari ingest loss. Overview menghitung reader; scope admin_preview/admin_operation tersedia pada request log. Filter range/environment/run/operation dan link kembali membantu investigasi.

Generator berhenti saat tab tersembunyi dan catch-up maksimal sepuluh tick ketika kembali. Session storage berlaku per tab; storage yang ditolak hanya mempertahankan memori halaman. Reset demo menghapus simulasi, perubahan, draft dan audit lokal dengan konfirmasi. Tidak ada backend yang dipanggil; demo ini bukan bukti SSE, auth server, scraper, readiness database, proxy atau transaksi produksi.
