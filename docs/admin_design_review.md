# Delivery Gate desain web admin TonzToon

Tanggal QA revisi 10: **25 Oktober 2026**. Cakupan QA revisi 10: **demo terhubung pada 33 halaman HTML/Tailwind** serta dokumentasi [DESIGN.md](../DESIGN.md). Focus ring dan flow sebelumnya dipertahankan. [PRD 1.5](prd_web_admin_monitoring.md) menentukan perilaku produk dan implementasi Next.js; tambahan kontrak styling dan mode Terminal produksi dicatat terpisah di bawah, terakhir 26 Oktober 2026.

Hasil: **PASS untuk prototype lokal dan dokumentasi dalam cakupan QA**. Empat blok gate di bawah menilai deliverable ini. Tidak mengklaim otorisasi server, API, transaksi, proxy, telemetry atau deployment telah selesai.


## Delivery Gate revisi 10: demo terhubung

**PASS dalam cakupan demo lokal.** Empat blok dinilai kembali untuk perubahan ini:

- **Hard Gate PASS:** 90 assertion alur demo, 1.794 regresi kontrol dan 528 smoke/layout/axe; request/runtime/popup tidak lagi bergantung daftar statis. Data tetap berlabel demo, status unknown tidak dianggap sukses, tanpa aset/identitas baru.
- **Purpose-Gate PASS:** panel simulasi menyediakan pemicu terpusat; ring parent dan surface existing dipakai untuk konsistensi. Jam demo dan pemisahan pause generator/tampilan menjelaskan perubahan data. Retensi dan ingest loss dibedakan agar angka tidak menyesatkan.
- **Liveliness PASS:** ENERGY 2 / RHYTHM 2 / MOTION 1 dipertahankan; identitas biru/navy/charcoal, route monospace, dan alur investigasi TonzToon tetap dominan. Tidak menambah dekorasi atau animasi baru.
- **Craftsmanship/Quality PASS:** request-runtime-insiden/endpoint, operasi-audit, serta Preview-run terhubung melalui ID nyata dalam sesi lokal. Flow yang belum diukur ditandai, database readiness tidak diklaim. Fokus diperiksa 329 assertion; kontras ring minimum 4,96:1. Build CSS/vendor dan sintaks JavaScript lulus; screenshot dua tema ditinjau.

[QA revisi 10](../web/prototype/QA.md) mencatat rincian, screenshot dan batas. [DESIGN.md](../DESIGN.md) serta [README](../web/prototype/README.md) mendokumentasikan panel, skenario, jam, buffer, korelasi dan persistensi sesi. Tidak ada skrip desain/QA baru di repository. Angka pengujian di bagian lama berikut merupakan arsip revisi sebelumnya, bukan bukti baru.


## Bukti

- [Peta 33 halaman](../web/prototype/README.md) mencakup login, monitoring, request/runtime, health/alert, katalog/chapter/genre/source, akun/library, helpdesk/audit, Preview Reader, Flow dan empat ERD.
- [QA tema revisi 9](../web/prototype/QA.md): 945 assertion browser dan 132 pengamatan first contentful paint pada 33 halaman dengan empat kombinasi tema/preferensi, termasuk script aplikasi ditahan. Tambahan 83 pemeriksaan bootstrap/stylesheet terlambat/file:// lulus. Background dan tema benar sebelum runtime, tanpa menyembunyikan konten; build CSS dan sintaks JavaScript lulus.
- Regresi fokus dijalankan ulang: 327 assertion pada 33 halaman/dua tema, 18 pasangan kontras minimum 4,96:1, mobile/teks 200%/forced-colors dan axe saat fokus lulus.
- Riwayat regresi revisi 7: 2.897 assertion fungsi lulus, termasuk 1.736 assertion seluruh halaman dan 228 khusus Overview. Seluruh suite fungsi tidak dijalankan ulang untuk perubahan stylesheet fokus ini.
- Revisi 9 mengulang 528 assertion smoke (33 halaman, dua tema, lima lebar dan axe), serta 228 flow Overview. Fokus desktop/Overview mobile/teks 200%/forced-colors diulang; rincian dan batas suite historis dibedakan pada QA.
- [28 screenshot modul/state](../web/prototype/screenshots/) dan delapan screenshot Overview diperbarui. State tambahan menunjukkan grafik latensi dan Staging tanpa data; capture desktop menunggu shell stabil.
- Anti-slop DURING beserta modul UI/human/responsive/copy diterapkan. UI UX Pro Max digunakan untuk data table, error recovery dan pola data padat; palette/font rekomendasi yang tidak sesuai identitas ditolak.
- Context7 memverifikasi Tailwind source detection/container queries, SimpleBar HTML API, constraint validation/dialog, fetch/abort dan image decode. Pada perbaikan ini MDN button/aria-pressed dipakai untuk native keyboard dan selection state. Tidak menambah dependency atau CLI desain.
- Semua konten awal berada pada HTML. Interaksi memakai satu prototype.js; bootstrap kecil inline pada head hanya menetapkan tema sebelum stylesheet. Tidak ada app.js, framework, module shell/UI atau generator/pemeriksa desain tambahan.
- Hasil QA versi statis lama tidak dipakai sebagai bukti versi interaktif baru.

## Hard Gate

| Aturan | Hasil dan bukti |
| --- | --- |
| R-02 Copy | PASS: bahasa Indonesia operasional; pencarian source HTML/JS tidak menemukan em dash atau TODO tersembunyi |
| R-03 Responsive | PASS: 33 halaman/lima lebar/dua tema tanpa page overflow pada run smoke baru; fokus desktop serta Overview 375 px/teks 200% juga lulus |
| R-17 Angka | PASS: snapshot historis dan metrik berlabel contoh; HTTP/bytes/decode reader hanya hasil file lokal |
| R-18 Testimonial | PASS: tidak ada testimonial atau foto identitas rekaan |
| R-23 Aset | PASS: logo existing; tiga SVG reader jelas berlabel placeholder; navigasi mengikuti modul PRD |
| R-24 Navigasi | PASS: tautan/aset lokal pada 33 halaman serta dokumen diverifikasi; konteks kembali diuji |
| R-25 Kontras | PASS: revisi 9 mengulang 18 pasangan ring/surface, minimum 4,96:1; axe pada kedua tema lulus. Palette tidak berubah; riwayat revisi 7: teks 5,34:1 dan kontrol/grafik 3,51:1 |
| R-26 Interaksi | PASS: select environment, empat pill waktu, tab grafik dan search/sort Overview mengubah hasil; seluruh opsi filter daftar dan pemilih record berulang diuji pada 33 halaman; matriks click-through pada QA |
| R-27 State | PASS: normal/loading/kosong/error/stale/denied/partial serta konflik/draft/hasil belum pasti tersedia dan diuji |
| R-28 FAQ | PASS: tidak menambah FAQ generik |
| R-32 Keyboard | PASS: ring mengikuti parent kontrol komposit, tidak menggandakan outline internal atau menambah tab stop; input/tombol/Tab diuji pada 33 halaman dua tema. Riwayat modal/drawer/diagram ada pada QA revisi 7 |
| R-33 Source | PASS: perubahan source melalui patch; CSS terkompilasi dan vendor disalin tanpa memodifikasi distribusi |
| R-34 Tema | PASS: dua tema pada semua halaman, state dan modal; token dipakai bersama |
| R-35 Verifikasi | PASS: build/sintaks, 945 assertion tema/132 first paint, 83 pemeriksaan tambahan, regresi 528 smoke/228 Overview/327 fokus, axe dan screenshot pemulihan tema; suite historis dibedakan pada QA |
| R-36 Klaim | PASS: simulasi izin, audit, mutation dan feed tidak dinyatakan sebagai implementasi keamanan/backend |
| R-37 Direction | PASS: meneruskan arah pengguna, DESIGN.md dan dials ENERGY 2 / RHYTHM 2 / MOTION 1 |
| R-38 Konten | PASS: data/akun/insiden/run contoh diberi label; ERD ditranskripsikan dari PRD, usulan dibedakan |

## Purpose-Gate

| Aturan | Hasil dan alasan |
| --- | --- |
| R-01 Warna | PASS: solid biru untuk aksi/selection, navy secondary, hijau/amber/merah untuk status |
| R-04 Ikon | PASS: vocabulary SVG existing diperluas menurut objek log/flow/schema; bukan dekorasi generik |
| R-06 Tipografi | PASS: Inter mempertahankan identitas, tabular untuk angka; monospace untuk ID/route/schema |
| R-07 Background | PASS: lapisan page/canvas/panel/isi membantu membedakan konteks dan data |
| R-08 Panah | PASS: dipakai untuk navigasi atau relasi flow/schema yang mempunyai arah |
| R-09 Badge | PASS: menyatakan status, coverage, existing/usulan, atau data contoh |
| R-10 Glass | PASS: tidak menggunakan glass global |
| R-12 Shadow | PASS: elevasi dibatasi pada canvas/dialog; panel data tetap flat |
| R-13 Glow | PASS: tidak menambah glow |
| R-14 Card | PASS: daftar/editor/reader/viewer mengikuti tugas; empat KPI hanya relevan pada Overview |
| R-19 Motion | PASS: feedback maksimal 150 ms dan sidebar 180 ms; reduced motion diperiksa |
| R-22 Ilustrasi | PASS: tidak ada ilustrasi generik; SVG reader hanya alat diagnosis placeholder berlabel |

## Liveliness

| Pemeriksaan | Hasil dan bukti |
| --- | --- |
| Dials | PASS: ENERGY 2 / RHYTHM 2 / MOTION 1, tanpa animasi dekoratif |
| Konsistensi dials | PASS: surface tenang, density data terukur, selection langsung |
| Focal point | PASS: daftar untuk investigasi, form untuk perubahan, reader untuk page, inspector untuk diagnosis |
| Whitespace | PASS: token 4/8 px, inset 4 px, isi 16/20 px, antarpanel 24 px |
| Aksen | PASS: primary biru pada aksi/selection, status semantik terpisah |
| Motif identitas | PASS: TonzToon, pasangan source/slug, route template dan bahasa operasi backend |
| Design Read | PASS: konsol operasional berdasarkan Overview existing, dinyatakan pada DESIGN.md sebelum perluasan halaman |

## Craftsmanship dan Quality Locks

| Aturan | Hasil dan bukti |
| --- | --- |
| C-1 Intentionality | PASS: alasan warna/type/surface/radius/motion tersedia pada DESIGN.md |
| C-2 Completeness | PASS: tidak ada lagi pengecualian kontrol Overview statis; konten HTML langsung dan alur lokal diperiksa, fungsi produksi tetap dibatasi jelas |
| C-3 Content | PASS: modul/field/status/empat ERD mengikuti PRD; tidak menambah halaman pengisi |
| C-4 Resilience | PASS: fokus dua tema, Tab, ukuran tetap, Overview mobile/teks 200%/forced-colors lulus; state/storage/file:// dan reduced motion merupakan riwayat revisi 7 pada QA |
| C-5 Evidence | PASS: hasil lokal dipisahkan dari integrasi yang belum dijalankan; QA lama tidak diwariskan |
| R-05 Struktur | PASS: tabel, editor, reader dan viewer memakai susunan sesuai keputusan pengguna |
| R-11 Radius | PASS: shell 28 px, panel 24 px, isi/input 16 px, kontrol pill, ikon lingkaran |
| R-15 CTA | PASS: Periksa perubahan, Arsipkan komik, Periksa seluruh page, Fit view menyebut tindakan/objek |
| R-16 Bahasa | PASS: copy operasional tanpa klaim pemasaran |
| R-20 Identitas | PASS: source/slug, diagnosis reader dan investigasi backend membentuk komposisi |
| R-21 Tema | PASS: tema sesi diterapkan sebelum stylesheet, first paint dipantau pada 132 navigasi; toggle, reload, perubahan sistem dan fallback storage/tanpa JavaScript lulus |
| R-29 Palette | PASS: 26 peran dalam dua tema dipertahankan; tidak ada palette per halaman |
| R-30 Orisinalitas | PASS: referensi pengguna diterapkan pada kebutuhan TonzToon, bukan menyalin layout produk lain |
| R-31 Alasan | PASS: keputusan dan kontrak komponen terdokumentasi bersama source yang dipakai |

## Batas penerimaan

Prototype merupakan hasil HTML/Tailwind dengan interaksi lokal. Form/login tidak mengirim field ke URL saat JavaScript tidak tersedia. Izin contoh hanya mengubah UI; tidak mengamankan data HTML. Feed merupakan buffer/simulasi, bukan SSE. Reader menguji tiga placeholder, bukan source/proxy produksi. Flow/ERD readonly HTML/SVG, bukan introspeksi database atau migration terpasang.

Belum diuji: aplikasi Next.js, server auth/RBAC, transaksi/idempotency backend, korelasi end-to-end produksi, scraper/proxy/Storage, gambar komik panjang, beban/memory produksi, deployment, Firefox/Safari, perangkat fisik dan screen reader manual. Drawer prototype memakai popover nonmodal; drawer modal produksi memerlukan implementasi tersendiri.

## Tambahan spesifikasi mode Terminal PRD 1.5, 26 Oktober 2026

Hasil: **PASS pada tingkat spesifikasi dokumen**. Permintaan pengguna memperluas FR-14/FR-15 pada [PRD 1.5](prd_web_admin_monitoring.md#19-log-runtime-dan-integrasi-backend-yang-dikonfirmasi): viewer output FastAPI/Uvicorn realtime dalam mode Terminal, berdampingan dengan mode Terstruktur. [DESIGN.md](../DESIGN.md) diselaraskan hanya pada kontrak komponen produksi. Prototype revisi 12, token/shell, renderer Data Flow/ERD, dan empat ERD dipertahankan.

- **Hard Gate PASS (dokumen):** mode Terminal secara eksplisit baca saja dan memakai output sumber tersanitasi. State koneksi/histori/gap, izin, redaksi, control sequence, batas buffer, keyboard dan mobile ditetapkan dalam FR-14/FR-15 beserta acceptance. Tidak ada contoh output rekaan atau klaim backend/browser sudah diuji.
- **Purpose-Gate PASS (dokumen):** monospace/whitespace untuk membaca format console dan traceback; warna untuk severity dengan label; perluas panel untuk investigasi. Tidak menambahkan terminal dekoratif, prompt command, animasi ketikan, atau aset baru.
- **Liveliness PASS (spesifikasi):** output runtime menjadi focal point, identitas/shell TonzToon serta ENERGY 2 / RHYTHM 2 / MOTION 1 dipertahankan. Aliran event berasal dari collector; UI tidak mengarang aktivitas saat sumber diam atau gagal.
- **Craftsmanship/Quality PASS (dokumen):** dua mode berbagi dataset/filter/cursor/subscription dan identitas event. Clear lokal, deduplikasi, urutan per sumber, provenance console, pencarian buffer versus histori, pause, reconnect dan eviction dijelaskan. Definition of Done menuntut perbandingan dengan console backend uji serta pengujian viewer yang sebenarnya.

Context7 me-resolve Uvicorn lalu mengambil `/websites/uvicorn_dev` untuk logger `uvicorn.error`/`uvicorn.access`, konfigurasi sink stdout/stderr, dan format console. Stream asal tidak diasumsikan sebagai severity; tampilan tetap tunduk pada redaksi dan kemampuan capture deployment. Tidak ada dependency terminal emulator atau endpoint shell yang ditambahkan.

Validasi revisi ini lulus: 50 tautan lokal valid pada tiga dokumen, code fence seimbang, 21 bagian PRD/21 FR unik, 8 diagram Mermaid termasuk 4 ERD, delapan bagian DESIGN.md tetap utuh, serta kontrak Terminal/console_text/capture_kind/control sequence tersedia. Build, browser, capture stdout/stderr, SSE/reconnect, sanitasi runtime, latensi dan penggunaan memori belum dijalankan. PASS QA prototype historis tidak menjadi bukti implementasi mode Terminal produksi.

## Tambahan spesifikasi styling produksi PRD 1.4

Hasil: **PASS pada tingkat spesifikasi**. Ketentuan baru berlaku pada aplikasi nyata `admin-web/`: scaffold resmi Next.js, Tailwind, daisyUI dev dependency/plugin dengan class semantik, serta stylesheet CSS modern untuk token dan domain. Prototype HTML/Tailwind dengan satu `prototype.js` tetap dalam cakupan terpisah; tidak ada package atau source prototype yang diubah oleh revisi dokumen ini.

- **Hard Gate PASS (dokumen):** instruksi instalasi diberi status rencana, source framework diambil melalui Context7, field/overlay tetap memerlukan semantik/fokus/izin, dan acceptance kedua tema serta keyboard ditetapkan. Tidak ada klaim library terpasang atau UI produksi lulus browser.
- **Purpose-Gate PASS (dokumen):** daisyUI mengurangi pembuatan ulang kontrol dan utility berulang; CSS custom terbatas pada token/domain. Node/card dan dashed arrow menjelaskan arah serta aktivitas yang terukur, tanpa membuat trace atau throughput palsu.
- **Liveliness PASS (spesifikasi):** identitas TonzToon dipertahankan. Permintaan animasi pengguna menjadi exception MOTION 2 hanya pada Data Flow produksi; halaman/prototype lain mengikuti dials yang berlaku. Putar/Jeda, sumber stale, reduced motion, dan mode demonstrasi berlabel ditentukan.
- **Craftsmanship/Quality PASS (dokumen):** pemisahan renderer konsisten: Data Flow custom DOM/SVG, ERD React Flow. Scoped CSS, class semantik, stylesheet sumber, mapping tema, posisi dinamis, dan pembatasan override vendor ditetapkan untuk menghindari duplikasi/drift.

Context7 digunakan untuk `/vercel/next.js`, `/websites/daisyui`, dan `/tailwindlabs/tailwindcss.com`: scaffold, plugin/tema daisyUI, CSS-first token/layer, serta custom styles. UI UX Pro Max mendukung kontrol pause dan reduced motion; rekomendasi gerak umum tidak menggantikan permintaan fungsional pengguna. FR-19 sampai FR-21 serta bagian 12/16/17/18/21 PRD diperbarui; DESIGN.md mempertahankan token dan delapan bagian utamanya.

Pemeriksaan struktur/tautan lulus: 39 tautan lokal pada tiga dokumen valid, code fence seimbang, 21 bagian PRD dan 21 functional requirement unik, 8 diagram Mermaid termasuk 4 ERD, serta delapan bagian DESIGN.md dipertahankan. Pemeriksaan ini tidak menjalankan compiler CSS, renderer, atau browser produksi.

Belum dijalankan pada revisi ini: scaffold/install daisyUI atau React Flow, build CSS aplikasi Next.js, browser flow custom/ERD, audit dependency baru, atau perubahan backend. Bukti QA demo lokal sebelumnya tidak menjadi bukti integrasi stack produksi. Tidak ada tooling pemeriksa desain baru yang ditambahkan.

## Riwayat spesifikasi Preview Komik PRD 1.3

Catatan berikut dipertahankan dari review spesifikasi sebelumnya. Angka pemeriksaan dokumennya merupakan hasil saat revisi PRD 1.3 disusun, bukan pengujian ulang reader pada konversi HTML ini.

Hasil: PASS pada tingkat spesifikasi, bukan PASS reader/runtime. Pengguna telah memilih alur API nyata dengan lazy-load/prefetch. FR-16 sampai FR-18 menetapkan feed/search, detail, chapter lengkap, URL gambar, reader melalui jalur proxy, diagnosis HTTP/body/decode, dan korelasi run/request/log. Efek cache/gambar backend dibedakan dari penulisan progress/bookmark yang tidak menjadi bagian preview.

Source router Sources/Search, payload chapter, helper URL gambar, dan endpoint image proxy diperiksa. Kontrak array feed, pagination search, daftar chapter penuh, serta URL yang sudah diproxy/public Storage dibedakan. Dokumentasi Next.js Image diambil melalui Context7 untuk `unoptimized` dan callback pemuatan/error. UI UX Pro Max digunakan untuk loading feedback dan error recovery; rekomendasi animasi tidak menggantikan MOTION 1 proyek.

Gate dokumen: alasan reader/inspector tertulis; palette/shell existing dipertahankan; tidak ada aset/angka produksi baru; URL sensitif dan akses log mempunyai izin terpisah; state parsial/gagal/belum diuji ditetapkan; resep responsive/keyboard serta acceptance tercatat. Empat ERD tetap dipertahankan, tanpa tabel preview persisten yang belum dibutuhkan. Anti-slop DURING dipakai pada spesifikasi.

Validasi struktur revisi ini lulus: 45 tautan lokal pada empat dokumen valid, code fence seimbang, 20 bagian PRD berurutan, 18 functional requirement unik, 8 diagram Mermaid termasuk 4 ERD, serta delapan bagian resmi DESIGN.md tetap utuh. Hasil ini merupakan pemeriksaan dokumen, bukan pengujian renderer gambar/diagram atau API.

Belum dijalankan pada pekerjaan revisi ini: request live ke backend produksi, build/browser reader, uji proxy/decode gambar, lazy-load/prefetch aktual, benchmark, atau perubahan source prototype/backend. Bukti QA Overview existing tidak diperluas menjadi bukti keberhasilan Preview Komik.

## Revisi 12: alur skill dan pilot Overview, 26 Oktober 2026

Aturan prosedur kini dipusatkan pada [ui-design-flow.md](../.agents/rules/ui-design-flow.md): scaffolding desain memakai Anti-slop + UI/UX Pro Max setelah keputusan fondasi; daily driver memakai Anti-slop + Taste, termasuk migrasi prototype ke framework dengan fondasi existing. Fondasi yang kurang, klasifikasi yang meragukan, atau konflik arahan memicu pertanyaan dengan kelebihan/kekurangan setiap opsi dan rekomendasi beralasan; pekerjaan yang bergantung pada keputusan menunggu jawaban. Keputusan sebelumnya digunakan kembali untuk lingkup yang sama. Mode Anti-slop diputuskan terpisah.

Pengguna memilih DURING, lalu memilih penyesuaian pill/tab dan tipografi mengikuti Taste setelah konflik dengan kontrak existing dijelaskan. [DESIGN.md revisi 12](../DESIGN.md) mencatat source dan dampak bersama: active navigation netral, tab bergaris bawah, filter waktu segmented netral, tombol radius 8 px dan teks minimum 11 px. Identitas/dials, logo, logika sidebar dan simulasi dipertahankan.

**Hasil pilot:** build dan syntax check lulus; inspector Taste app pada lima lebar menghasilkan **0 FAIL, 1 WARN**; **120 pemeriksaan browser** pada dua kelompok lulus; 16 pasangan teks/background hasil render lulus checker kontras dengan minimum 6,63:1. Warning proporsi metadata di bawah 13 px dipertahankan dengan alasan fungsi yang tercatat, tanpa menonaktifkan aturan inspector. Screenshot sebelum/sesudah, kritik app screen, hasil per kontrol, pemeriksaan lintas halaman representatif, dan batas verifikasi tersedia pada [QA revisi 12](../web/prototype/QA.md#revisi-12-pilot-alur-anti-slop--taste-26-oktober-2026).

Delivery Gate ini terbatas pada perubahan kontrol/tipografi dan pilot Overview. Pengujian seluruh modul, axe, storage ditolak, browser lain, reset yang dikonfirmasi, dan aplikasi/backend produksi tidak diulang. PASS historis pada bagian sebelumnya bukan bukti pengujian ulang bagian tersebut.

## Skeleton shimmer konten, 29 Oktober 2026

Semua sepuluh halaman console kini mempunyai fallback `PageSkeleton` pada batas Suspense existing, menggantikan teks loading Overview dan fallback kosong halaman monitoring/detail. Tiga komposisi memakai primitive `Skeleton` reusable: Overview (ringkasan dan grafik), daftar (toolbar dan baris), serta detail (pasangan label/nilai). Shell dan batas navigasi tetap terpisah. Tidak ada delay atau state loading buatan; data kosong/gagal tetap memakai state aktual halaman. Tidak ada fallback loading route umum yang menutupi komposisi khusus halaman.

- **Hard Gate PASS (lingkup skeleton):** server produksi lokal hasil build final diuji melalui Edge. Sembilan kombinasi tiga bentuk dengan light 1440, dark 360, dan dark reduced motion 360 lulus: varian yang tampil sesuai route, bodyTop=0, tanpa overflow horizontal, dan placeholder tetap di dalam padding parent. Skeleton memiliki aria-busy/status dan bentuk dekoratif aria-hidden, tanpa kontrol yang bisa difokuskan.
- **Purpose-Gate PASS:** shimmer line/surface 1,5 detik hanya menandai konten pending; reduced motion menghasilkan animation-name=none. Placeholder mengikuti struktur konten dan token bersama, tanpa persentase, angka, atau data rekaan.
- **Liveliness PASS:** screenshot final Overview desktop, daftar mobile dan detail mobile ditinjau. Temuan awal grid melampaui padding panel diperbaiki dengan track minmax(0,1fr) serta batas lebar placeholder. Shell, identitas, surface dan ENERGY 2 / RHYTHM 2 / MOTION 1 tetap mengikuti DESIGN.md.
- **Craftsmanship/Quality PASS:** build final termasuk TypeScript dan prerender 13 halaman exit 0; ESLint TSX yang diubah exit 0. Pada runtime produksi dengan JavaScript, skeleton hilang setelah Overview, Endpoint, dan detail Endpoint siap; navigasi client ke Health selesai tanpa skeleton tersangkut.

Bukti sesi: `%TEMP%/check-tonztoon-skeleton.cjs` dan `%TEMP%/tonztoon-skeleton-{overview,list,detail}-{theme}-{width}-{motion}.png`. Pengujian visual fallback menonaktifkan JavaScript untuk mempertahankan HTML fallback prerender selama hydration belum tersedia; pengujian penyelesaian memakai JavaScript aktif. Browser produksi memakai port 3002. Pemeriksaan ini tidak membuktikan integrasi fetch backend; data monitoring masih fixture existing. Seluruh kontrol, pembaca layar nyata dan browser selain Edge tidak diaudit ulang.

## Pengelompokan Suspense navigasi, 29 Oktober 2026

Revisi ini menggantikan batas per link pada implementasi awal di bawah. `NavigationMenu` menjadi renderer bersama untuk menu aktif maupun fallback netral. `RouteNavigation` membaca pathname sekali per kelompok menu; dua pemanggilan pada shell menghasilkan satu batas navigasi desktop dan satu batas navigasi mobile. Batas breadcrumb tetap terpisah. Tidak ada batas Suspense pada setiap link. DESIGN.md mencatat kontrak terbaru.

- **Hard Gate PASS (lingkup pengelompokan):** browser Edge membuka langsung detail `/endpoints/reader` light 1440 dan `/requests/missing` dark 360; breadcrumb/aria-current benar, bodyTop=0, tanpa overflow horizontal maupun teks loading shell. Drawer mobile dapat dibuka dan ditutup dengan Escape; tanpa JavaScript shell/sidebar/link tetap dirender.
- **Purpose-Gate PASS:** seluruh link pada satu navigasi menunggu pathname yang sama dan ditampilkan bersama; fallback menggunakan renderer menu yang sama tanpa status aktif, sehingga tidak memerlukan boundary per link atau markup menu terpisah.
- **Liveliness PASS:** screenshot desktop light dan mobile dark hasil pengujian ulang ditinjau; shell, surface, hierarki, identitas dan ENERGY 2 / RHYTHM 2 / MOTION 1 tetap sesuai kontrak.
- **Craftsmanship/Quality PASS:** build produksi exit 0 termasuk TypeScript, 13 halaman dan route detail partial prerender; lint shell exit 0. Regresi progress navigasi light desktop, dark mobile, dan reduced motion lulus dengan request tujuan ditahan serta klik ulang route yang sama; indikator bersih sesudah commit.

Bukti sesi memakai ulang `%TEMP%/check-tonztoon-shell.cjs`, `%TEMP%/check-tonztoon-navigation.cjs` dan screenshot `tonztoon-shell-{light-1440,dark-360}.png`. Pemeriksaan browser berjalan pada server dev; build produksi diuji terpisah. Seluruh kontrol aplikasi/backend dan browser lain tidak diaudit ulang.

## Shell tanpa fallback layar penuh, 29 Oktober 2026

`(console)/layout.tsx` kini merender AdminShell langsung. `usePathname` dipindahkan dari shell ke leaf `ActiveNavigationLink` dan `CurrentPageLabel`, dengan Suspense lokal: fallback link netral mempertahankan menu yang bisa digunakan dan breadcrumb menyediakan ruang label tanpa teks loading. Header/sidebar/footer/konten tidak ikut menunggu pathname. Kontrak DESIGN.md diselaraskan.

- **Hard Gate PASS (lingkup shell):** Edge membuka langsung `/endpoints/reader` light 1440 dan `/requests/missing` dark 360. Response tidak mengandung teks fallback lama, breadcrumb dan aria-current benar, bodyTop=0, tanpa overflow horizontal. Drawer mobile dibuka dan ditutup dengan Escape. Tanpa JavaScript, shell/sidebar/link tetap tersedia pada detail dinamis.
- **Purpose-Gate PASS:** batas async ditempatkan pada pembacaan URL yang memerlukannya, sesuai dokumentasi Next.js Cache Components. Tidak ada preload/delay buatan, teks loading pengganti seluruh shell, atau dekorasi tambahan.
- **Liveliness PASS:** screenshot detail desktop dan state resource tidak ditemukan pada mobile ditinjau; shell, tipografi, surface, identitas dan ENERGY 2 / RHYTHM 2 / MOTION 1 dipertahankan.
- **Craftsmanship/Quality PASS:** build produksi exit 0, termasuk TypeScript dan prerender 13 halaman serta empat route detail partial prerender; ESLint kedua TSX exit 0. Regresi progress navigasi lulus pada light desktop, dark mobile dan reduced motion: muncul ketika request ditahan, hilang sesudah commit dan klik ulang route selesai tanpa indikator tersangkut.

Bukti sesi: `%TEMP%/check-tonztoon-shell.cjs`, `%TEMP%/tonztoon-shell-light-1440.png`, `%TEMP%/tonztoon-shell-dark-360.png`, serta skenario progress sesi sebelumnya yang dijalankan ulang. Percobaan browser detail pertama timeout selama kompilasi awal; pengulangan setelah route dikompilasi lulus. Browser menggunakan server dev; build produksi diperiksa terpisah, tidak dijalankan sebagai server produksi. Seluruh kontrol, backend, dan browser selain Edge tidak diaudit ulang.

## Linear progress navigasi Next.js, 29 Oktober 2026

Satu `NavigationProgressProvider` pada root layout menggabungkan status pending dari `NavigationLink`, wrapper native Next.js Link. Empat pemakai Link existing memakai wrapper yang sama: starter, shell, Overview, dan halaman monitoring. `useLinkStatus` mengikuti lifecycle router termasuk cleanup saat link dilepas; tidak ada monkey patch history/fetch, dependency tambahan, atau timer penyelesaian rekaan. Indikator indeterminate fixed 3 px memakai accent, role progressbar berlabel `Memuat halaman`, dan tidak mengambil fokus. Navigasi prefetched/instan dapat melewati pending. Filter query via router.replace dan back/forward native tidak ditambahkan indikator tersendiri.

- **Hard Gate PASS (lingkup indikator):** Edge headless menjalankan navigasi Overview ke Endpoint dengan request tujuan ditahan. Bar terlihat selama pending, hilang sesudah commit, dan kembali bersih sesudah klik ulang route yang sama. Dua tema diperiksa pada desktop 1440 dan mobile 360; role/label, tinggi 3 px, top=0, position=fixed dan tanpa overflow horizontal terukur.
- **Purpose-Gate PASS:** gerak segmen linear menandai penantian navigasi nyata, tanpa persentase atau indikasi keberhasilan palsu. Track accent 15% dan fill accent mengikuti token kedua tema.
- **Liveliness PASS:** screenshot light desktop dan dark mobile mempertahankan shell, hierarki, serta ENERGY 2 / RHYTHM 2 / MOTION 1 TonzToon. Satu aksen tipis cukup untuk feedback tanpa mengubah layout.
- **Craftsmanship/Quality PASS:** typecheck dan ESLint seluruh TSX yang diubah exit 0. Uji reduced motion mengukur animation-name=none selama pending dan indikator hilang setelah commit. Seluruh API Link diteruskan, termasuk ref/handler/prefetch; native router menentukan status selesai.

Bukti sesi: `%TEMP%/tonztoon-progress-light-1440-no-preference.png`, `%TEMP%/tonztoon-progress-dark-360-no-preference.png`, `%TEMP%/tonztoon-progress-light-1440-reduce.png`; skenario browser `%TEMP%/check-tonztoon-navigation.cjs`. Screenshot ditinjau untuk posisi, ketebalan, warna, dan tidak adanya layout shift. Build produksi, seluruh kontrol existing, kegagalan jaringan dan browser selain Edge tidak diuji ulang dalam patch ini.

## Background shell Next.js, 29 Oktober 2026

Lingkup: satu utility `flow-root` pada `.tt-admin` di `web/src/components/admin/shell.tsx`. Margin vertikal panel desktop 16 px sebelumnya collapse melewati shell sampai body. Edge headless pada Overview 1440 x 900 mengukur body mulai pada y=16, sehingga background root putih terlihat di luar body abu-abu. Formatting context baru menahan margin di dalam shell; body mulai pada y=0 dan mencakup tinggi dokumen. Jarak panel dan token warna mengikuti DESIGN.md, ENERGY 2 / RHYTHM 2 / MOTION 1.

- **Hard Gate PASS (perubahan background):** runtime Edge pada light/dark, lebar 360, 375, 768, 1024, 1440 serta landscape 844 x 390 menghasilkan bodyTop=0, bodyBottom sesuai tinggi dokumen dalam pembulatan subpixel, dan tanpa overflow horizontal. Toggle sidebar desktop dan pembukaan drawer mobile berhasil.
- **Purpose-Gate PASS:** `flow-root` mencegah margin collapse tanpa memotong overflow atau mengganti jarak panel. Tidak ada teknik dekoratif baru.
- **Liveliness PASS:** screenshot light desktop dan dark mobile mempertahankan identitas, hierarki Overview, surface, serta dials existing; strip background di atas sudah hilang.
- **Craftsmanship/Quality PASS (lingkup patch):** ESLint `src/components/admin/shell.tsx` exit 0; dua tema dan enam viewport diperiksa pada aplikasi Next.js nyata. Source berubah hanya pada formatting context shell.

Bukti screenshot sebelum/sesudah sesi berada di `%TEMP%/tonztoon-bg-before.png`, `%TEMP%/tonztoon-bg-{light,dark}-{width}.png`. Pemeriksaan ini bukan audit seluruh kontrol atau backend; build produksi, seluruh route, dan browser selain Edge tidak dijalankan ulang. Indikator issue Next.js dev terlihat pada screenshot sesudah; penyebabnya tidak diaudit dalam perbaikan background ini.
