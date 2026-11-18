# Progres frontend fase 2

> Checkpoint historis ini telah digantikan oleh [laporan penyelesaian fase 2](admin_frontend_phase2_completion.md), 30 Oktober 2026. Shell/Overview sebelumnya juga dikoreksi pada [laporan fidelitas UI](admin_ui_fidelity_review.md). Status dan gap di bawah menggambarkan 28 Oktober, bukan keadaan terkini. Frontend fase 2 kini selesai; integrasi fase 3 belum dimulai.

Tanggal: 28 Oktober 2026. Status: **fase 2 masih berjalan, belum memenuhi kriteria selesai seluruh 33 halaman**. Pengguna sudah mengizinkan fase frontend; fase 3 belum dimulai. Laporan ini adalah checkpoint implementasi shell, pilot Overview, dan rute monitoring awal.

## Source dan cakupan

Implementasi baru:

- [Shell](../web/src/components/admin/shell.tsx): layout console, logo existing, sidebar 80/240 px, preferensi sesi, drawer mobile, breadcrumb, selector tema, skip link.
- [Overview](../web/src/components/admin/overview.tsx): filter URL, rentang, grafik SVG/tabel alternatif, dialog snapshot/insiden/endpoint/cakupan, pencarian dan urutan endpoint, state pemulihan.
- [Monitoring](../web/src/components/admin/monitoring-page.tsx): daftar/detail endpoint, request, runtime; Health; daftar/detail alert. Terminal/Terstruktur merupakan snapshot baca saja.
- [Fixture monitoring](../web/src/lib/demo/monitoring.ts): sumber data bertipe terpisah dari tampilan; tidak mengakses API.
- Stylesheet `admin.css` pada checkpoint ini kemudian diganti utility Tailwind dan komponen reusable; lihat [laporan refaktor](admin_tailwind_refactor.md) serta [style token/integrasi terkini](../web/src/styles/).

Komponen Button, Input, Select, Badge, Table, Alert, Panel, Dialog dan Drawer existing digunakan kembali. Perubahan sebelumnya pada Tabs, Toast, varian Button dan backdrop Dialog dipertahankan. Tidak memasang dependency baru dan tidak mengubah DESIGN.md pada checkpoint ini. Halaman pemeriksaan komponen tetap di `/`, dengan tautan menuju `/overview`.

| Rute | Hasil pada checkpoint ini | Sisa pekerjaan frontend |
| --- | --- | --- |
| /overview | Pilot shell, filter/state, grafik request dan 5xx, tabel, dialog dan korelasi | Samakan penuh simulator/event, histogram per bucket, status HTTP lengkap dan evaluasi seluruh metrik/rentang |
| /endpoints, /endpoints/[id] | Inventaris/search, snapshot count/error/p95, tautan request | Histogram, OpenAPI, filter/pagination/sort lengkap |
| /requests, /requests/[id] | Request contoh tersanitasi, pencarian, pause, korelasi runtime | Feed berbatas, pagination/filter penuh, gap/timeout/reconnect dan state lengkap |
| /runtime-logs, /runtime-logs/[id] | Terminal/Terstruktur, severity/search, pause, salin, korelasi | Autoscroll, traceback, inspector lengkap, state transport dan simulasi buffer/eviction |
| /health | Pemisahan layanan/DB/pipeline/browser dan coverage historis | Riwayat probe, slot unknown/gap, pilihan periode/environment lengkap |
| /alerts, /alerts/[id] | Insiden firing historis, ambang/hold/pemulihan, tautan endpoint | Filter status, timeline dan evaluator pending/resolved/unknown |
| Login, katalog/chapter/genre/source, akun/library, helpdesk/audit | Belum dimigrasikan | Seluruh task 2.2 login, 2.3 |
| Preview Komik, reader, Data Flow, ERD | Belum dimigrasikan | Seluruh task 2.4 |

Sepuluh route monitoring tersedia; ini bukan pernyataan bahwa sepuluh halaman sudah memenuhi seluruh P0 PRD. Menu sementara hanya menautkan rute yang tersedia. Kelompok Data/Preview/Model ditambahkan ketika halaman terkait siap, agar tidak ada tautan menuju route kosong.

## Data contoh dan perbedaan prototype

Angka baseline diambil dari HTML Overview prototype: 24.400 request, 141 respons 5xx, p95 842 ms, availability 174/177. Lima endpoint berjumlah sama dengan total tersebut. Lima belas bucket juga berjumlah 24.400/141. Snapshot historis memiliki cutoff 24 Oktober 2026, 10:42 UTC+7.

Pada checkpoint ini belum memigrasikan simulator terhubung dari prototype.js. Lima menit memakai lima bucket terakhir; pembagian per endpoint memakai proporsi baseline dengan sisa pembulatan dialokasikan ke baris terakhir. Rentang 1 jam/24 jam mengulang fixture, berlabel agregasi ulang. Total tabel/grafik/KPI diperiksa konsisten, tetapi alokasi ini bukan agregat telemetry nyata. Quantile dan probe tetap baseline 15 menit, diberi keterangan di UI; histogram per bucket tidak direka. Tab Latensi menyediakan tabel quantile baseline, bukan grafik dengan angka buatan. Tab Status HTTP saat ini menampilkan 5xx saja. Kekurangan ini tetap terbuka pada todo Overview.

Staging tidak mempunyai fixture. Data tidak tersedia tidak diubah menjadi nol atau sehat. State denied menyembunyikan metrik; stale tidak menyatakan insiden pulih; partial diberi pemberitahuan. Semua halaman menjelaskan bahwa tidak ada SSE/polling/backend terhubung. Pause hanya mengubah state tampilan snapshot, bukan menghentikan feed produksi.

## Verifikasi yang dijalankan

| Pemeriksaan | Hasil dan batas |
| --- | --- |
| npm run lint | PASS, exit 0 setelah perbaikan pemulihan preferensi sidebar |
| npm run typecheck | PASS, next typegen + tsc --noEmit, exit 0 |
| npm run build | PASS, route baru terbentuk, hasil produksi dijalankan di 127.0.0.1:3101 |
| Invarian fixture Node | PASS: total bucket = total endpoint pada 5/15/60/1440 menit, errors <= count |
| Prototype | 103 berkas, hash sama dengan baseline; tidak dimodifikasi |
| Console browser | Tidak ada error/warning pada pemeriksaan akhir aplikasi |

Hash prototype: `9118b2e6daedc5bf487d088e8e3f678cdc67cd12015b332738f15cf5ab331e12`.

Browser aktual menggunakan Chromium in-app terhadap build produksi. Screenshot final dan [pengukuran](screenshots/admin-frontend-phase2/measurements.json) disimpan dalam [folder bukti](screenshots/admin-frontend-phase2/). Matrix terang/gelap: 360, 375, 768, 1024 dan 1440 CSS px. Tidak ada overflow horizontal halaman. Tabel minimum 640 px bergeser di region lokal berlabel/focusable, bukan dipadatkan menjadi kolom satu huruf. Grafik juga memakai region scroll lokal. Screenshot awal yang menangkap transisi saat resize diganti dengan screenshot final dalam emulasi reduced motion.

- Sidebar default terukur 80 px pada 1024 dan 240 px pada 1440. Toggle memindahkan canvas bersamaan; pilihan collapsed bertahan setelah reload.
- Drawer 360 px: membuka, Shift+Tab membungkus ke tautan terakhir, Escape menutup dan fokus kembali ke Menu.
- Filter environment Staging menampilkan tanpa data. Kembali Production memulihkan snapshot.
- State loading/empty/error/denied menyembunyikan metrik; stale/partial mempertahankan snapshot dengan pemberitahuan. Pemulihan kembali ke contoh normal bekerja.
- Rentang 5/15 menit, tab Latensi/Status HTTP/Trafik, search tanpa hasil, reset pencarian, urut request terbanyak, serta data grafik dicoba.
- Dialog snapshot/cakupan/insiden bekerja dengan Escape. Tautan insiden → endpoint reader → request → runtime berhasil, membawa environment/range.
- Runtime: pause/resume, filter ERROR, pencarian tanpa hasil, mode Terstruktur/Terminal, dan salin log dicoba. Clipboard berhasil dengan pesan konfirmasi.
- Semua tautan navigasi monitoring dibuka; heading/rute sesuai.
- Landscape 844×390 tanpa overflow halaman. Reduced motion diemulasi untuk pemeriksaan/screenshot; emulasi dipulihkan setelah pengujian.

Kontras dari sampel computed RGB yang terukur: minimum terang 4.76:1, gelap 7.32:1. Nilai Oklab hover tidak dihitung pada pemindaian RGB ini dan ditandai unmeasured pada JSON. Komposit status gelap diperiksa terpisah memakai contrast-check.py: warning 9.99:1, success 7.79:1, error 5.42:1. Seri grafik light 4.25:1 terhadap putih memenuhi batas grafik 3:1. Ini bukan audit aksesibilitas lengkap seluruh halaman/hover. Zoom teks 200%, forced colors, screen reader, engine lain dan state storage ditolak belum diuji pada checkpoint ini.

## Kritik render dan gerbang tahap ini

Arah daily driver tetap ENERGY 2 / RHYTHM 2 / MOTION 1, Inter dan palette existing. Tidak melakukan draw arah baru. Focal point Overview adalah gangguan lalu empat KPI; panel grafik/health mempunyai tugas berbeda; tabel menyediakan jalur investigasi. Warna hanya menyatakan data/status/fokus. Tidak ada aset baru, statistik produksi rekaan, atau navigasi palsu.

Temuan render yang diperbaiki: tabel ponsel terlalu sempit sehingga route menjadi kolom huruf; kini region lokal dengan lebar minimum. Baris group endpoint kini terpisah dari route. Panel grafik tidak dipaksa setinggi health sehingga tidak ada ruang kosong internal yang disengaja untuk menyamakan tinggi.

| Gerbang terbatas | Status |
| --- | --- |
| R-03, R-34: reflow/tema Overview | PASS pada matrix final, tanpa overflow halaman |
| R-17, R-18, R-23, R-36, R-38: bukti dan aset | PASS: fixture berlabel, logo existing, tanpa klaim backend aktif |
| R-24: navigasi | PASS: menu hanya rute yang dibangun dan sudah dibuka |
| R-25: kontras | PASS untuk pasangan yang diukur di atas; audit hover/seluruh state tetap terbuka |
| R-26, R-27, R-32: interaksi/state/keyboard | PASS pada kontrol dan skenario yang dicatat; cakupan P0 lengkap belum selesai |
| R-33, R-35: source/runtime | PASS: TSX/CSS ditulis langsung, build produksi dan browser dijalankan |
| Liveliness dan craftsmanship | Arah existing dipertahankan; perbaikan berdasarkan screenshot; tidak menyatakan pilot sebagai penerimaan produk |

**Delivery Gate fase 2 keseluruhan masih terbuka**, karena banyak halaman dan interaksi belum dibangun/diuji. Tidak meminta persetujuan fase 3 pada checkpoint ini. Pekerjaan frontend berikutnya adalah melengkapi monitoring dan login, kemudian editor data, preview/reader dan kedua renderer diagram sesuai todo yang sudah disetujui.
