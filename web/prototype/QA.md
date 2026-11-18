# QA prototype HTML TonzToon Admin

Tanggal: **25 Oktober 2026**. Cakupan: **33 halaman HTML**, Tailwind CSS dan prototype.js berdasarkan [PRD 1.3](../../docs/prd_web_admin_monitoring.md) serta [DESIGN.md revisi 10](../../DESIGN.md). Semua perubahan, feed dan izin merupakan contoh lokal. Reader menguji file placeholder lokal. Revisi 10 menambahkan sesi simulasi yang terhubung. Bukti revisi lama dipisahkan di bawah.


## Simulasi terhubung revisi 10

**PASS: 90 assertion browser alur demo (82 alur utama + 8 kasus tepi)**, tanpa exception. Pengujian Chromium terpasang melalui HTTP lokal membuktikan:

- Baseline 1.000 request, generator dijeda; hitungan KPI dan p95 cocok dengan event mentah pada 5/15/60/1440 menit, jumlah endpoint reader cocok dengan KPI.
- Latensi tinggi melewati pending/firing dan pulih sesudah rolling window/hold; HTTP 5xx menghasilkan insiden; API down mencatat probe gagal/liveness tanpa mengarang access log.
- Gap mempertahankan observed_at terakhir, mencatat ingest loss, membuat insiden metrik unknown dan pipeline firing; pemulihan tidak langsung memalsukan resolved.
- Request → runtime → detail memiliki ID yang sama; lifecycle tidak dipaksa mempunyai request ID. Jeda tampilan membekukan daftar, buffer bertambah, resume memuat event unik, clear dan riwayat tidak menghapus sesi.
- Start/pause, navigasi dan reload mempertahankan sesi; pause menghentikan generator. Environment Staging menghasilkan data sendiri. Batas 1.000 request/runtime/probe dan eviction diuji melalui burst.
- Simpan katalog → audit → request → runtime menyimpan Operation ID; konflik menghasilkan 409 dan draft tetap tersedia. Telemetry tidak mengumpulkan nilai field form.
- Preview feed → komik → reader memuat/decode tiga file lokal, menghasilkan attempt dalam request/runtime dengan Run ID yang sama; skenario HTTP 503 tercatat terpisah dari HTTP lokal aktual.
- Storage ditolak menampilkan batas persistensi dan tetap dapat menjalankan insiden di memori halaman. Panel mobile tidak membuat overflow.
- Delapan kasus tepi memeriksa panel mobile terbuka/reduced motion, popup tanpa overflow, probe unknown pada gap, catch-up dibatasi sepuluh tick, konfirmasi reset dibatalkan, dan reset sukses. Perbaikan reset mencegah pagehide menulis kembali sesi yang telah dihapus. Batas catch-up diuji dengan jam tersimpan yang dimundurkan; ini tidak mengukur throttling OS/browser.

**PASS: 1.794 assertion regresi kontrol**, pada 33 halaman × light/dark: pencarian/filter/reset, sort/pagination, pilihan resource, dialog, state dan pemulihan. Harness disesuaikan untuk daftar insiden/audit yang sekarang dimulai kosong dan pagination riwayat yang melebihi fixture lama. Angka tetap dari revisi sebelumnya tidak dipakai sebagai ekspektasi simulasi baru.

**PASS: 528 assertion smoke/layout/axe** pada 33 halaman, dua tema, lima lebar 360/375/768/1024/1440 px. **PASS: 329 assertion fokus**, 18 pasangan kontras ring/surface minimum 4,96:1. Build vendor/CSS dan node --check lulus. Semua harness berada di direktori sementara tooling, bukan tambahan skrip repository.

Screenshot sesi demo: [Overview/latensi](screenshots/demo-overview-latency-light.png), [popup request](screenshots/demo-request-popup-light.png), [health API down](screenshots/demo-health-down-light.png), [runtime dark](screenshots/demo-runtime-down-dark.png), [mobile dark](screenshots/demo-overview-mobile-dark.png). Capture menuntaskan transisi CSS sebelum mengambil gambar. Review visual memeriksa hierarki panel, badge status, input/button, dan reflow pada dua tema.

Batas: ini end-to-end **demo browser lokal**, bukan integrasi backend. Belum membuktikan SSE, server auth/RBAC, transaksi/idempotency, scraping/proxy/Storage produksi, database readiness, browser/perangkat lain, screen reader manual, beban/memori produksi. Catch-up tab tidak aktif dibatasi sepuluh tick sesuai implementasi; pengujian browser di atas tidak mengukur throttling berbagai OS/browser. Hasil FOUC revisi 9 di bawah merupakan bukti historis; bootstrap tidak diubah dalam revisi 10.

## Arsip QA sebelum simulasi terhubung


## Tema dan FOUC revisi 9

**PASS: 945 assertion browser**, mencakup 33 halaman × tema sistem light/dark × preferensi pembalikan false/true. Script aplikasi sengaja ditahan saat memeriksa root/body background, color-scheme, konten terlihat dan transisi startup. **132 pengamatan first contentful paint** mempunyai tema serta background yang benar sebelum script aplikasi dilanjutkan. Setelah aplikasi berjalan, tema dan checkbox tetap sinkron tanpa berpindah palette saat hidrasi.

Reload setelah toggle, perubahan tema sistem, storage ditolak, nilai JSON rusak dan fallback CSS tanpa JavaScript lulus. **83 pemeriksaan tambahan** terdiri dari 66 pemeriksaan kesamaan/urutan/sintaks bootstrap pada 33 HTML serta 17 pemeriksaan browser: stylesheet yang ditunda, background critical sebelum CSS, transisi kembali setelah startup, pembukaan file:// dan toggle, serta tanpa exception.

Build CSS/vendor dan node --check prototype.js lulus. Bootstrap tidak memerlukan dependency/script eksternal baru, tidak menyembunyikan body, dan tidak memakai timer untuk menutupi kedipan. Regresi ulang: **528 assertion smoke** (33 halaman, dua tema, lima lebar dan axe) serta **228 assertion flow Overview** lulus. Bukti tampilan setelah pemulihan: [light](screenshots/theme-restored-light.png), [dark](screenshots/theme-restored-dark.png). Pengamatan paint merupakan uji browser lokal; tidak mencakup browser/perangkat lain atau antarmuka browser sebelum dokumen mulai dimuat.

## Regresi fokus pada revisi 9

**PASS: 327 assertion browser baru**, tanpa exception. Seluruh 33 halaman diperiksa dalam light/dark untuk kontrol komposit yang tersedia, input biasa, tombol keyboard, dan overflow saat fokus. Ring pembungkus berukuran 3 px/offset 3 px, inner outline tidak muncul, Tab tidak terperangkap, dan ukuran komponen tidak berubah.

Pemeriksaan tambahan Overview mencakup klik mouse pada select/search, checkbox tema dengan ring pada pembungkus ikon, lebar 375 px, teks 200%, axe saat fokus mobile pada kedua tema, dan forced-colors. **18 pasangan kontras ring/surface** dihitung dari warna hasil render; minimum **4,96:1**. Build CSS/vendor lulus.

Empat screenshot fokus: [search light](screenshots/focus-search-light.png), [search dark](screenshots/focus-search-dark.png), [environment light](screenshots/focus-environment-light.png), [environment dark](screenshots/focus-environment-dark.png). Review visual memastikan ring mengikuti batas rounded/pill, mencakup ikon/dot, dan tidak lagi membentuk kotak kedua pada input/select internal.

Bagian berikut menyimpan bukti fungsi revisi 7. Rangkaian lengkap 2.897 assertion tidak dijalankan ulang untuk revisi 9; subset 528 smoke dan 228 flow Overview dijalankan ulang seperti dicatat di atas. Hasil historis lainnya tidak diklaim sebagai run baru.

## Riwayat regresi fungsi revisi 7

| Kelompok | Hasil | Cakupan |
| --- | --- | --- |
| Smoke halaman | PASS, **528 assertion** | 33 halaman, light/dark, lebar 360/375/768/1024/1440 px; H1, overflow halaman, exception dan axe |
| Fungsi seluruh halaman | PASS, **1.736 assertion** | 33 halaman pada dua tema; seluruh opsi filter SELECT daftar, hasil/empty state, search Enter/reset, sort, ukuran/page, pemilih record berulang, dialog dan tujuh state/pemulihan |
| Overview interaktif | PASS, **228 assertion** | Light/dark pada 375/1440 px; empat pill waktu, Production/Staging, tiga grafik, jumlah bucket/endpoint/KPI, search/sort/reset, sembilan popover, keyboard, URL/reload/back |
| Regresi record dan konteks | PASS, **40 assertion** | Kedua tema; isolasi form/draft, parent chapter, arsip/pulih/restore status, create/reload, edit/link genre baru, diff audit berulang, rentang/environment Health, korelasi dan kategori helpdesk |
| Interaksi utama | PASS, **114 assertion** | Kedua tema; login, filter/sort/page/back, form/validasi/diff, konflik/draft, hasil belum pasti, perubahan lokal, audit, feed dan profil izin |
| Reader dan diagram | PASS, **80 assertion** | Kedua tema; feed/source/chapter pecahan, decode, retry/stop, payload invalid, flow inspector/zoom/pan/list, empat ERD |
| Resilience | PASS, **78 assertion** | Filter monitoring tambahan, konsistensi bucket/histogram, sidebar/tooltip/persistensi/drawer, modal/keyboard/axe, landscape, teks 200% termasuk Overview, reduced motion, storage ditolak, file:// |
| Kasus tambahan | PASS, **38 assertion** | Kedua tema; chapter lokal baru, komik tanpa chapter, skenario 404/413/503/504/body HTML/stream/missing/dimensi, konteks kembali feed/chapter |
| Kontrol dan state | PASS, **46 assertion** | Kedua tema; clipboard ditolak, focus trap modal, timer feed/clear, probe contoh, tujuh state dan axe, reset seluruh draft, Escape drawer |
| Tanpa JavaScript | PASS, **9 assertion** | Konten awal dan layout file:// pada Overview/Katalog/ERD/Reader; submit login tidak menulis kredensial ke URL |
| Struktur | PASS, **140 pemeriksaan** | ID unik, satu prototype.js per halaman, aset/tautan lokal, dokumen, delapan bagian DESIGN.md, PRD 1.3 dipertahankan |
| Kontras | PASS, **70 pasangan** | Minimum teks **5,34:1**; minimum kontrol/grafik **3,51:1**, dua tema |
| Build/sintaks | PASS | npm run build menyalin SimpleBar dan mengompilasi Tailwind; node --check prototype.js |

Total **2.897 assertion browser** pada revisi 7, tanpa exception JavaScript pada run yang lulus. Kelompok pada tabel dijalankan saat perbaikan fungsi Overview dan flow lintas halaman. Pemeriksaan struktur dan kontras dilaporkan terpisah. Hasil 102 assertion versi statis, 402/427 versi terdahulu dan total 889 versi sebelum perbaikan bukan bukti bahwa kontrol Overview dahulu berfungsi.

Playwright **1.64.1**, Chrome terpasang, axe-core **4.14.0**. Axe memakai tag WCAG 2 A/AA, 2.1 AA, 2.2 AA pada 33 halaman dalam dua tema; modal preview dan tujuh state Katalog diperiksa terpisah dalam dua tema. Empat pemindaian tambahan pada Overview Latensi/Staging dalam light/dark juga bersih. Axe bukan sertifikasi WCAG. Pemindaian tidak membuktikan setiap kombinasi role/state/perangkat.

## Click-through

| Kontrol atau alur | Hasil yang diperiksa |
| --- | --- |
| Logo/sidebar/drawer | Tujuan nyata, menu aktif, 80/240 px; logo sama dan drawer tanpa border |
| Collapse/expand | Pilihan lebar absolut pulih setelah reload dan perubahan breakpoint |
| Tooltip rail | Muncul saat fokus keyboard di luar host scroll, Escape menutup |
| SimpleBar desktop/drawer | Satu instance per host, autoHide aktif, header/footer tetap |
| Menu mobile / tutup / Escape | Drawer terbuka/tertutup; breakpoint menutup dan mengembalikan fokus terlihat |
| Tema | Checkbox membalik tema, pilihan pembalikan tersimpan pada sesi |
| Environment Overview | Select native mengubah Production/Staging; Staging menampilkan nol sampel, quantile/availability belum tersedia, tanpa insiden Production |
| Pill waktu Overview | 5/15/60/1440 menit memperbarui KPI, periode, grafik/tabel, endpoint dan popover; satu aria-pressed aktif dan URL pulih setelah reload |
| Tab grafik Overview | Trafik & 5xx, Latensi, Status HTTP mengganti seri, judul, unit, legend dan kolom tabel; Enter/Space memakai button native |
| Tabel endpoint Overview | Search/sort/reset bekerja, hasil kosong memiliki recovery, kembali ke prioritas memulihkan urutan awal |
| Search/filter/reset | Hasil lokal berubah, debounce search, filter SELECT langsung, reset dan URL pulih |
| Sort/pagination/ukuran halaman | Urutan DOM, jumlah hasil, batas halaman dan tautan detail konsisten |
| Kembali ke daftar/detail/feed | Konteks source, pencarian, range dan chapter dipertahankan |
| Endpoint | Environment/range/kelas HTTP, delapan route, detail, bucket/histogram menjumlah ke total sampel; tanpa trafik tetap unknown |
| OpenAPI error | Inventaris historis tetap terlihat; error tidak disamarkan sebagai sukses |
| Request/runtime start/pause/tambah/latest/clear | Buffer lokal bekerja; clear hanya tampilan, event baru dapat dibuka; lifecycle tanpa request ID tidak mengarang korelasi |
| Insiden | Firing/pending/resolved/unknown, timeline contoh dan tautan investigasi sesuai jenis |
| Health | Liveness/readiness dan coverage dibedakan; belum diukur tidak menjadi sehat |
| Login | Validasi, 401/403/kedaluwarsa, profil akun/auditor menuju modul yang diizinkan |
| Detail komik/account/source/request/runtime/audit | Pemilih record mengubah identitas dan detail; link antarhalaman terarah |
| Periksa perubahan | Diff lama-baru terbuka pada dialog modal; Escape mengembalikan fokus |
| Simpan lokal | Perubahan muncul pada detail/daftar/audit sesi; submit ganda dicegah |
| Validasi/konflik/draft | Validasi tidak menyimpan; konflik mempertahankan draft; draft dapat dipulihkan |
| Hasil belum pasti | Tidak langsung dinyatakan sukses; rekonsiliasi menyelesaikan simulasi |
| Tambah komik/chapter/genre/akun | Identitas unik diperiksa; record lokal masuk daftar; nomor chapter pecahan dipertahankan |
| Arsip/pulih/ban/aktifkan | Konfirmasi menyebut resource/dampak dan memperbarui status lokal |
| Helpdesk | Preview note/status dan audit lokal, tanpa pengiriman pesan eksternal |
| Data pribadi | Password/email login tidak masuk sessionStorage/diff/audit; email contoh disamarkan |
| Profil izin | Menu dan halaman langsung mengikuti profil contoh; hidden link korelasi tidak dibuka ulang oleh role |
| State | Normal/loading/kosong/error/stale/denied/partial dapat dipilih dan dipulihkan |
| Feed Preview | Latest/popular/search mengubah konteks contoh, filter source dan detail sesuai identitas |
| Reader | File lokal decode 800 × 1120, HTTP/MIME/bytes/durasi lokal terpisah, concurrency maksimum tiga |
| Retry/stop/reset/chapter/lompat page/inspector | Attempt tercatat, batal tidak menjadi sukses, chapter berasal dari metadata, riwayat gagal dipertahankan |
| Error gambar | Corrupt/body HTML/timeout/stream dan kode simulasi tidak dianggap respons proxy produksi |
| Flow | Node/domain search, edge/node inspector, overlay pengukuran, zoom/pan/fit/reset/list |
| ERD | Empat tab, 27 tabel, 21 relasi FK, field/constraint/JSONB, existing versus usulan, pencarian kolom dan alternatif list |
| Copy | Clipboard API dengan fallback dialog salin manual bila ditolak; tidak mengklaim copy berhasil sebelum selesai |

Kontrol Overview kini interaktif. Pemeriksaan manual melalui Chrome DevTools mengonfirmasi klik **5 menit** menghasilkan **8.134 request contoh**; memilih **Staging** menghasilkan **0 request**, availability **Belum tersedia**, dan insiden Production tersembunyi. Tidak ada request monitoring ke backend.

## Responsive dan visual

Semua 33 halaman diperiksa pada lima lebar dalam dua tema tanpa horizontal overflow halaman. Tabel, kode panjang, dan diagram mempunyai area scroll lokal. Pemeriksaan landscape **812 × 375** dan teks **200%** dilakukan pada Overview, Katalog, Editor Komik, Reader, Flow, ERD, dan Log runtime; hasil ini tidak diperluas menjadi pengujian 200% pada setiap halaman.

**36 screenshot diperbarui**: [28 screenshot modul/state](screenshots/) dan delapan screenshot Overview (desktop expanded/collapsed, mobile, drawer pada dua tema). Tambahan state memperlihatkan [grafik latensi](screenshots/overview-latency-dark.png) dan [Staging tanpa data](screenshots/overview-staging-dark.png). Review visual memeriksa surface dua tema, tabel/form, reader dan diagram terhadap DESIGN.md. Capture desktop menunggu lebar shell stabil sebelum mengambil gambar.

## Perbaikan yang diverifikasi

- Tampilan select/pill/tab/pencarian/urutan Overview diganti kontrol native dengan hasil data lokal, bukan pengecualian visual statis.
- Total bucket dan endpoint cocok dengan KPI; konteks environment/rentang bertahan saat investigasi, dan Health tidak meminjam hasil Production untuk Staging.
- Enter menerapkan pencarian langsung pada form dengan banyak input; urutan prioritas dipulihkan setelah sort lain.
- Pemilih source/endpoint/request memperbarui tautan terkait setiap kali diganti, tanpa memberi filter resource pada navigasi sidebar global.
- Form komik tidak membawa field draft record sebelumnya; editor chapter menyimpan ke parent terpilih, dan chapter baru pulih sebagai mode edit setelah reload.
- Status chapter berubah setelah arsip/pulih; arsip parent terlihat pada chapter; restore komik mengembalikan status sebelum arsip.
- Genre baru dapat diedit serta membuka filter relasinya; diff audit dipulihkan setelah berganti record; pesan/rating helpdesk sesuai kategorinya.
- Search blur tidak lagi mengurutkan ulang baris saat klik link detail.
- Source title terpisah dari override; pilihan record dan judul akun lokal konsisten.
- Chapter baru dapat dipilih reader; komik baru tanpa chapter tidak mengarang metadata.
- Total bucket/histogram sesuai sampel; quantile tanpa fixture tidak disalin dari endpoint lain.
- Pergantian sesi reader membatalkan pekerjaan lama dan membersihkan blob URL; callback lama tidak mengurangi counter sesi baru.
- Link kembali reader memulihkan pencarian chapter dan source/feed.
- Modal memakai dialog native, focus restore dan diff aman; form mutation/login memakai method dialog agar tidak mengirim field melalui URL saat JavaScript tidak tersedia.

## Batas bukti

Tidak ada request ke backend produksi dalam pengujian browser. Login, role, mutation, audit, buffer/feed, insiden dan kondisi error adalah simulasi lokal. Reader hanya mengambil placeholder SVG yang disertakan; hasilnya tidak membuktikan proxy, Storage, source scraper, gambar komik panjang, korelasi end-to-end produksi, memory produksi, SSE, retensi, atau transaksi backend.

Belum diuji: Next.js, otorisasi server, deployment, browser Firefox/Safari, screen reader manual, perangkat fisik/keyboard layar, performa beban dan jaringan produksi. Drawer native prototype nonmodal; focus trap drawer produksi masih bagian implementasi Next.js. Fallback storage hanya hidup pada halaman ketika browser menolak penyimpanan.

Tidak ada skrip QA/desain tambahan di repository. Harness browser dipakai dari direktori sementara tooling; laporan ini dan screenshot menjadi bukti deliverable. [Delivery Gate](../../docs/admin_design_review.md) mencatat keputusan desain serta batas penerimaannya.

## Revisi 12: pilot alur Anti-slop + Taste, 26 Oktober 2026

Pengguna memilih Anti-slop **DURING** untuk sesi ini dan, setelah konflik dijelaskan, memilih **redesain pill/tab dan tipografi mengikuti Taste**. Keputusan berlaku pada kontrol bersama prototype dan kontrak `DESIGN.md`, bukan izin untuk mengganti framework atau menjalankan UI/UX Pro Max. Pemeriksaan ini menguji source revisi 12; hasil 33 halaman pada bagian sebelumnya tetap merupakan riwayat revisi lama.

### Perubahan dan review visual

- Navigasi desktop/drawer aktif memakai line/foreground dan radius 8 px. Filter waktu memakai segmented netral dengan border pilihan; tab grafik memakai garis dasar/indikator. Tombol aksi radius 8 px, primary foreground/canvas, secondary surface/foreground. Badge status tetap berbentuk pill karena membawa status/data.
- Teks brand-sub, eyebrow, tag dan count navigasi minimum 11 px; label metrik 14 px, deskripsi metrik/header panel 13 px. Route/ID memakai generic monospace sistem dengan ukuran relatif minimum 11 px; warning face kode yang tidak dimuat telah hilang.
- Tujuh pertanyaan kritik app screen diperiksa: konteks API dan observasi reader terlihat pada judul/KPI; tepi panel sejajar; hue tetap pada data/status, sementara pilihan memakai surface netral; angka KPI cocok dengan rincian; nol dibedakan dari nilai belum tersedia; legenda mengikuti seri; navigasi mobile terlipat dan data/tabel memiliki akses scroll lokal. Review ini tidak mengklaim redesain seluruh susunan dashboard.
- Capture awal full-page yang mengambil margin shell di tengah transisi tidak dipakai sebagai bukti desktop final. Capture final menunggu shell stabil: sidebar dan margin shell sama-sama 240 px pada kedua tema. Tidak ada perubahan logika sidebar untuk memperbaiki artefak capture tersebut.

Screenshot: [sebelum dark](screenshots/taste-revision-12/before-dark.jpg), [sesudah light](screenshots/taste-revision-12/after-light.jpg), [sesudah dark](screenshots/taste-revision-12/after-dark.jpg), [mobile light](screenshots/taste-revision-12/after-mobile-light.jpg), [mobile dark](screenshots/taste-revision-12/after-mobile-dark.jpg).

### Pemeriksaan yang dijalankan

- `rtk proxy npm run build` dan `rtk proxy node --check prototype.js`: lulus. Stylesheet disusun dengan Tailwind CSS 4.3.3, vendor SimpleBar 6.3.3 tetap dari dependency existing. Sintaks custom CSS/`@apply` diperiksa melalui Context7 sebelum perubahan.
- Inspector Taste `--app` pada **1440, 1024, 768, 375, 360 px**: **0 FAIL, 1 WARN** pada tema dark sistem. Harness terpisah memeriksa kedua tema pada kelima lebar tersebut, tanpa overflow halaman atau teks di bawah 11 px. Inspector memakai tinggi 225 px pada lebar 360; harness tambahan memakai 360 x 900 agar pemeriksaan mobile tidak bergantung pada tinggi bawaan inspector.
- **82/82 pemeriksaan utama** dan **38/38 pemeriksaan tambahan** lulus. [Hasil utama](screenshots/taste-revision-12/interaction-report.json) dan [hasil tambahan](screenshots/taste-revision-12/extra-report.json) menyimpan hasil setiap pemeriksaan, termasuk cakupan halaman dan tema.
- **16 pasangan teks/background** hasil computed style browser, pada dua tema, dihitung ulang menggunakan `antislop-human/contrast-check.py`: seluruhnya lulus 4.5:1, minimum **6,63:1**. Sampel mencakup navigasi aktif, filter waktu, tab, primary/secondary, brand-sub, label metrik, dan snapshot. [Rincian kontras](screenshots/taste-revision-12/contrast-report.json). Ini pengukuran sampel komponen berubah, bukan klaim seluruh pixel/state lulus audit aksesibilitas.
- KPI request, jumlah endpoint, dan jumlah bucket masing-masing **600** pada baseline yang diperiksa, cocok pada kedua tema. Angka tersebut adalah observasi demo sesi pengujian, bukan fixture permanen atau metrik produksi. [Rincian konsistensi data](screenshots/taste-revision-12/data-check.json).

| Kontrol / kondisi | Hasil pemeriksaan |
| --- | --- |
| Rentang 5/15/60/1440 menit | Klik memperbarui `aria-pressed`, pilihan aktif, dan URL. |
| Tab traffic/latency/status | Klik memperbarui pilihan dan URL; grafik tetap berfungsi. |
| Environment | Keyboard memilih Staging; grafik menunjukkan sampel tidak tersedia, lalu kembali Production. |
| Pencarian dan reset | Input/Enter menerapkan pencarian kosong hasil; reset menghapus query. |
| Urutan endpoint | Pilihan Route A-Z diterapkan dan dicatat pada URL. |
| Snapshot, health, request, endpoint | Popover terbuka; Escape menutup. Lima detail endpoint juga diuji dengan tombol tutup. |
| Data grafik | Disclosure membuka dan menutup tabel data. |
| Sidebar dan tema | Collapse 80 px/expand 240 px serta toggle tema bolak-balik berfungsi. |
| Keyboard | Tab menunjukkan outline; Space mengaktifkan pilihan grafik; Escape menutup popover/drawer. |
| State data | Loading, empty, error, stale, denied, partial ditampilkan dan dapat dipulihkan. |
| Profil izin | Profil accounts menolak akses Overview; profil all memulihkannya. Profil catalog memang mempunyai izin monitoring dan tidak digunakan sebagai fixture penolakan. |
| Demo lokal | Step memajukan jam; start/pause berubah sesuai aksi; skenario berjalan; pembatalan konfirmasi reset mempertahankan sesi. Reset yang dikonfirmasi menghapus sesi tidak diuji ulang. |
| Responsive | Kedua tema pada lima lebar, landscape 844 x 390, dan pembesaran teks 200% pada viewport 720 x 500 tanpa overflow halaman. |
| Reduced motion | Konten tampil; drawer terbuka dengan durasi transisi 0 s. |
| Fallback tanpa JavaScript | Kedua tema pada desktop menampilkan layout tanpa overflow dan tab minimal 44 px. Ini bukan pengujian seluruh interaksi tanpa JavaScript. |
| Dampak lintas halaman | Endpoint, daftar komik, detail komik, dan login diperiksa desktop/mobile pada kedua tema tanpa overflow. Pengujian fungsi modul lengkap tidak diulang. |
| Runtime | Tidak ada exception JavaScript pada halaman/skenario yang diperiksa. |

### Delivery Gate dan batas

Hard Gate, Purpose-Gate, Liveliness, dan Craftsmanship diperiksa pada **perubahan kontrol/tipografi serta pilot Overview**: arah desain dan alasan perubahan tercatat, kontrol yang diperiksa berfungsi, data tetap berlabel simulasi, kontras sampel lulus, kedua tema dan responsive diuji. Dials `ENERGY 2 / RHYTHM 2 / MOTION 1`, logo, dan motif resource dipertahankan.

Warning Taste tersisa: **48% blok teks berada di bawah 13 px**. Ukuran 11-12 px dipertahankan untuk metadata, label sekunder, badge dan sumbu grafik sebagaimana diizinkan jalur app screen; label metrik dan tab utama memakai 14 px. Tidak ada aturan inspector yang dinonaktifkan untuk menghasilkan hasil ini.

Belum diuji ulang: seluruh interaksi 33 halaman, axe otomatis, screen reader, Firefox/Safari, storage ditolak, reset yang dikonfirmasi, integrasi/backend, dan aplikasi framework produksi. Hasil ini tidak membuktikan autentikasi/otorisasi server, telemetry, SSE, deployment, atau fungsi bisnis produksi. Perubahan berkas panduan diperiksa terpisah sebagai dokumen.
