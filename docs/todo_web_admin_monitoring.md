# Todo implementasi TonzToon Admin

Tanggal penyusunan: 26 Oktober 2026. Acuan produk: [PRD 1.5](prd_web_admin_monitoring.md). Acuan desain: [DESIGN.md revisi 12](../DESIGN.md). Referensi migrasi: [prototype](../web/prototype/README.md).

## Aturan pelaksanaan dan persetujuan

- Kerjakan berurutan: perencanaan → starter proyek → frontend → integrasi backend → pengujian penerimaan.
- Sebelum memulai setiap fase berikutnya, laporkan hasil fase sebelumnya, bukti verifikasi, perubahan berkas, serta batas/masalah yang masih ada, kemudian **tanyakan konfirmasi pengguna dan tunggu jawabannya**. Selesainya suatu fase tidak otomatis mengizinkan fase berikutnya.
- Konfirmasi berlaku untuk fase yang disebutkan. Jika satu fase memerlukan beberapa sesi, lanjutkan tugas dalam fase itu tanpa menganggapnya sebagai izin untuk fase berikutnya.
- Centang task hanya setelah pekerjaan dan verifikasi yang disebutkan benar-benar selesai. Catat pekerjaan parsial dan pengujian yang terhalang; jangan menyamakannya dengan lulus.
- Pilihan Anti-slop sesi ini: **during**, dikonfirmasi pengguna. Pilihan ini tidak disimpan sebagai preferensi global. Migrasi dengan fondasi existing memakai Anti-slop + Taste Skill jalur app screen, sesuai [aturan desain](../.agents/rules/ui-design-flow.md).
- Pemeriksaan yang relevan dilakukan selama tiap fase. Fase pengujian akhir mencakup integrasi lintas modul, ketahanan, performa, dan staging.
- Penerapan migration pada database bersama/produksi serta deployment memiliki checkpoint persetujuan tersendiri setelah perubahan dan bukti lokal siap ditinjau.

## Ringkasan status

| Fase | Hasil | Status | Konfirmasi untuk mulai |
| --- | --- | --- | --- |
| 0. Perencanaan | Todo, cakupan, dependensi, dan kriteria selesai | Disetujui | Permintaan awal |
| 1. Starter proyek | Scaffold resmi di root `web/`, dependency, konfigurasi, dan build dasar | Selesai; [laporan](admin_starter_phase1.md) | Disetujui pengguna, lokasi `web/` |
| 2. Frontend dari prototype | Seluruh halaman dan interaksi P0 dengan sistem desain existing | Selesai untuk frontend contoh terisolasi; [laporan dan Delivery Gate](admin_frontend_phase2_completion.md) | Fase 2 disetujui pengguna 28 Oktober 2026; kelanjutan penuh diminta 30 Oktober |
| 3. Integrasi backend | Sesi/RBAC, API nyata, telemetry/log, worker, mutation, dan preview | Belum dimulai | Setelah laporan fase 2 |
| 4. Pengujian penerimaan | Bukti end-to-end, keamanan, performa, pemulihan, dan kesiapan staging | Belum dimulai | Setelah laporan fase 3 |

## Fase 0: perencanaan

- [x] Baca versi PRD saat ini, kontrak desain, aturan proyek, dan peta prototype.
- [x] Inventarisasi 33 halaman HTML untuk migrasi frontend.
- [x] Periksa keberadaan fondasi backend admin pada source saat ini.
- [x] Susun urutan tugas, batas data contoh/API nyata, dan kriteria selesai per fase.

Catatan baseline dari inspeksi source:

- Pada baseline perencanaan, `web/` hanya berisi `prototype/`. Pengguna menyetujui fase 1 dan menetapkan starter langsung di root `web/`, menggantikan rencana lokasi `admin-web/`.
- Prototype memiliki 33 halaman HTML dengan data contoh dan interaksi dalam satu `prototype.js`. Implementasi Next.js akan menggunakan komponen React dan state aplikasi yang sesuai.
- Source backend sudah memuat [router admin](../backend/app/admin/router.py), [monitoring](../backend/app/admin/monitoring.py), [admin-data](../backend/app/admin/data.py), [security](../backend/app/admin/security.py), telemetry/storage/editorial, migration, dan skrip operasional. Router utama sudah menyertakan router admin dengan feature flag `ADMIN_CONSOLE_ENABLED`.
- Tersedia [SQL admin console](../backend/sql/20261025_admin_console.sql), [migration](../backend/alembic/versions/20261025_admin_console.py), [worker](../backend/scripts/admin_worker.py), [supervisor](../backend/scripts/admin_supervisor.py), serta tes admin. Semuanya perlu diperiksa dan diuji terhadap PRD 1.5 sebelum dinyatakan memenuhi kebutuhan.
- Status PRD yang menyebut monitoring/manajemen baru belum diimplementasikan perlu direkonsiliasi dengan source tersebut. Dokumen ini tidak menyatakan endpoint, migration, collector, atau worker telah lulus runtime.

**Gerbang:** todo tersedia untuk ditinjau. Setelah pengguna mengonfirmasi fase 1, mulai bootstrap. Belum ada instalasi dependency atau perubahan source aplikasi pada fase perencanaan.

## Fase 1: starter proyek sesuai PRD

### 1.1 Runtime dan scaffold resmi

- [x] Periksa Node.js LTS/npm yang tersedia dan kompatibilitas `engines` versi stable yang akan dipasang.
- [x] Ambil dokumentasi terkini melalui Context7 untuk CLI Next.js dan konfigurasi Tailwind/daisyUI sebelum menjalankan atau menulis konfigurasi terkait.
- [x] Buat starter langsung di `web/` menggunakan `create-next-app@latest` resmi dengan TypeScript, ESLint, Tailwind, App Router, `src/`, alias `@/*`, npm, dan Git initialization dinonaktifkan, sesuai bagian 12 PRD. Pertahankan `web/prototype/`; jika generator memerlukan direktori kosong, generate pada staging kosong lalu pindahkan hasilnya setelah memeriksa benturan nama.
- [x] Periksa hasil scaffold dan instruksi `AGENTS.md` yang dihasilkan. Catat versi Node.js, npm, Next.js, React, Tailwind, dan daisyUI yang benar-benar terpasang.
- [x] Pasang daisyUI sebagai dev dependency; simpan `package-lock.json`. Pasang `@xyflow/react` untuk kebutuhan ERD, dengan penggunaan yang dimuat khusus halaman ERD.

### 1.2 Struktur dan konfigurasi dasar

- [x] Siapkan struktur route group, komponen, library server/domain, dan stylesheet sesuai bagian 12/21 PRD tanpa membuat implementasi fitur kosong seolah sudah berfungsi.
- [x] Tetapkan pembagian `globals.css`, `tokens.css`, `components.css`, `data-flow.css`, dan `erd.css` pada pipeline scaffold resmi.
- [x] Siapkan dasar tema light/dark TonzToon dan komponen representatif daisyUI dari token `DESIGN.md`; lengkapi penerapannya pada shell di fase 2.
- [x] Dokumentasikan batas Server Components, Client Components, BFF Route Handlers runtime Node.js, dan modul khusus server.
- [x] Tambahkan `.env.example` tanpa secrets: URL backend allowlist, origin admin, database sesi, kunci enkripsi sesi, serta konfigurasi lain yang benar-benar diperlukan. Implementasi sesi dilakukan pada fase 3.
- [x] Siapkan scripts lint, typecheck, build, dan start berdasarkan scaffold aktual; jangan mengandalkan build untuk menjalankan lint.
- [x] Tulis README setup, instalasi dari lockfile, menjalankan aplikasi, konfigurasi server, dan status fitur yang belum diimplementasikan.

### 1.3 Verifikasi dan hasil fase

- [x] Verifikasi instalasi dari lockfile, lint, typecheck, dan build dasar.
- [x] Jalankan hasil build dan buka halaman dasar; periksa console/runtime serta komponen daisyUI representatif pada kedua tema.
- [x] Catat hasil dan versi dependency di README/laporan fase.

**Kriteria selesai:** scaffold resmi bisa dipasang, dibangun, dan dijalankan; pipeline Tailwind/daisyUI serta dasar tema terverifikasi. Autentikasi dan akses backend belum diklaim selesai.

Hasil: [README aplikasi](../web/README.md), [laporan fase 1 dan Delivery Gate](admin_starter_phase1.md). Instalasi bersih, lint, typecheck, build, serta pemeriksaan browser starter lulus. Seluruh berkas prototype tetap sama dengan baseline.

**Checkpoint:** laporkan hasil fase 1, lalu tanyakan konfirmasi untuk fase 2. Jangan memulai migrasi seluruh halaman sebelum jawaban diterima.

## Fase 2: bangun frontend dengan menerapkan prototype

### 2.0 Fondasi komponen bersama sebelum migrasi luas

Koreksi fidelitas shell/Overview, penggunaan Tabs reusable, dan bukti terbaru dicatat di [laporan koreksi UI](admin_ui_fidelity_review.md). Ini tidak menutup task migrasi seluruh halaman maupun gerbang fase 2.

Lingkup dikonfirmasi pengguna pada 27 Oktober 2026. Selesaikan dan tinjau tahap ini sebelum melanjutkan migrasi halaman. Kontrak props ada pada [komponen UI](admin_ui_components.md).

- [x] Selaraskan alias token tema untuk warna semantik, radius, dan surface dari kontrak existing.
- [x] Gunakan class/modifier daisyUI yang sesuai dengan tugas komponen.
- [x] Lengkapi Button, Input, Select, Textarea, Checkbox, Table, Card/Panel, Alert, Badge/StatusBadge, Dialog/Drawer, dan Spinner yang reusable.
- [x] Tetapkan props native dan varian bersama: size, loading, disabled, invalid, primary/secondary, serta tone status.
- [x] Batasi override tt-* pada kebutuhan TonzToon, tanpa menduplikasi library.
- [x] Pisahkan style default netral dari status serta disabled/readonly.
- [x] Rapikan cascade agar varian tetap bekerja; selaraskan mapping desain yang stale dengan source prototype revisi 12.
- [x] Gunakan seluruh komponen pada halaman pemeriksaan starter, dengan contoh lokal dan kontrol yang berfungsi.
- [x] Validasi tema, responsivitas, kontras, keyboard/fokus/overlay, lint, typecheck, dan build; laporkan hasil sebelum meminta konfirmasi migrasi berikutnya.

Hasil tahap 2.0: [laporan dan Delivery Gate](admin_ui_components_review.md), termasuk 12 kombinasi tema/viewport, landscape, interaksi overlay, kontras, dan batas pengujian. Pengguna mengonfirmasi kelanjutan fase 2 pada 28 Oktober 2026. [Checkpoint frontend](admin_frontend_phase2_progress.md) mencatat shell/Overview dan rute monitoring awal beserta gap yang masih terbuka. Selesainya tahap fondasi tidak menandai fase 2 selesai atau mengizinkan fase 3.

Fase ini memigrasikan visual dan perilaku prototype dengan kontrak data bertipe yang disiapkan untuk integrasi. Selama API nyata belum terhubung, gunakan data contoh berlabel dalam mode pengembangan yang terisolasi; state ini tidak memberikan akses ke data/mutation produksi dan tidak menjadi bukti autentikasi atau RBAC server.

### 2.1 Shell, tema, dan komponen bersama

- [x] Bandingkan HTML, `styles.input.css`, dan perilaku `prototype.js` dengan `DESIGN.md` sebelum memindahkan implementasi.
- [x] Terapkan logo existing, font, token, surface, radius 8 px, navigasi netral, tab bergaris bawah, segmented filter, dan ukuran teks sesuai kontrak.
- [x] Bangun sidebar desktop lebar/ringkas, drawer mobile, overlay, breadcrumb, header kontekstual, dan pemulihan fokus sesuai perilaku existing.
- [x] Terapkan inisialisasi tema sebelum tampilan pertama, preferensi tersimpan lalu sistem, serta fallback storage sesuai kontrak produksi.
- [x] Gunakan daisyUI untuk komponen semantik; wrapper React secukupnya untuk reuse, state, validasi, dan aksesibilitas. CSS domain memakai namespace `tt-*`.
- [x] Terapkan filter/pagination/sort dan konteks investigasi pada URL; navigasi kembali mempertahankan konteks yang relevan.
- [x] Siapkan antarmuka data dan adapter terpisah dari komponen tampilan agar penggantian data contoh dengan API nyata tidak memerlukan penulisan ulang halaman.

### 2.2 Halaman monitoring

- [x] Login: field berlabel, validasi, serta tampilan 401/403/sesi kedaluwarsa.
- [x] Overview: KPI/grafik/tabel yang mengikuti environment, rentang, metrik, dan cutoff yang sama; tampilkan freshness/coverage.
- [x] Inventaris/detail endpoint: filter, sort, grafik, histogram, dokumentasi, dan tautan request terkait.
- [x] Request log/detail: pencarian, filter, pagination, pause/resume, buffer terbatas, posisi scroll, dan metadata tersanitasi.
- [x] Runtime log/detail: mode **Terminal dan Terstruktur** sesuai tambahan PRD 1.5, filter, autoscroll, pause, copy, traceback, dan status collector. Terminal merupakan viewer teks baca saja.
- [x] Health: bedakan status API, dependency, pipeline telemetry, dan koneksi browser; slot tidak diketahui tetap unknown.
- [x] Alert/detail: pending/firing/resolved/unknown, timeline, filter, dan tautan investigasi.

### 2.3 Halaman data

- [x] Komik: daftar/detail/tambah/edit; nilai source, override, dan efektif ditampilkan terpisah.
- [x] Chapter: daftar/detail/tambah/edit metadata; dukung nomor pecahan dan batas field immutable.
- [x] Genre dan source: daftar/pencarian/detail yang relevan; form genre dan registry source readonly.
- [x] Akun: daftar/detail/tambah/edit akun nonadmin, perubahan status, masking data, dan library terbatas baca saja.
- [x] Helpdesk: daftar/detail, filter, status, dan catatan internal.
- [x] Audit: daftar/detail, filter, diff aman, dan korelasi request/operation ID.
- [x] Semua editor: preview perubahan, validasi, draft, konfirmasi arsip/pulihkan, konflik versi, dan hasil operasi belum pasti. Simulasi keberhasilan tetap berlabel contoh sampai fase 3.

### 2.4 Preview Komik dan diagram

- [x] Preview feed/search, detail komik, daftar seluruh metadata chapter, dan mini reader.
- [x] Reader: lazy load, prefetch terbatas, navigasi chapter, status HTTP/transfer/decode, stop/retry/reset, timeline run, dan inspector URL sesuai izin.
- [x] Data Flow: node/card DOM dan SVG dashed arrow custom, pan/zoom/fit/reset, search/filter, selection, inspector, dan alternatif daftar.
- [x] Pisahkan demonstrasi arah dari aktivitas terukur; siapkan pause/reduced motion serta penghentian animasi saat sumber stale atau viewer tidak aktif.
- [x] ERD: empat diagram readonly dengan `@xyflow/react`, pencarian tabel/kolom, inspector/data dictionary, tema TonzToon, serta label existing/logical/usulan.
- [x] Pertahankan pemisahan renderer/controller/stylesheet Data Flow custom dan ERD React Flow.

### 2.5 State dan verifikasi frontend

- [x] Terapkan loading, kosong, tidak cocok filter, error, denied, stale, partial, timeout, gap, dan backend down sesuai konteks setiap modul.
- [x] Jalankan lint/typecheck/build dan verifikasi hasil build dengan browser nyata.
- [x] Catat click-through setiap kontrol, keyboard/fokus/dialog, dua tema, kontras, reduced motion, dan ukuran viewport terkait; perbaiki temuan sebelum serah hasil fase.
- [x] Simpan screenshot perbandingan terhadap prototype dan catatan perbedaan yang disengaja. Ubah `DESIGN.md` hanya jika kontrak desain memang berubah dalam lingkup yang disetujui.
- [x] Jalankan Delivery Gate Anti-slop pada frontend yang benar-benar dibangun; tandai integrasi API sebagai belum diuji sampai fase 3.

**Kriteria selesai:** seluruh 33 halaman terpetakan ke route aplikasi dan interaksi P0 frontend dapat diperiksa. Tambahan Terminal PRD 1.5 tercakup. Data contoh terlihat sebagai contoh; backend/security/SSE produksi belum diklaim selesai.

Hasil 30 Oktober 2026: [laporan fase 2 dan Delivery Gate](admin_frontend_phase2_completion.md). Lint/typecheck/build, 132 kombinasi route, 72 state, 102 assertion interaksi, 36 layout tambahan dan 422 sampel kontras lulus. Taste inspector final mencatat 0 FAIL/0 WARN. Batas integrasi dan cakupan browser dicatat eksplisit; prototype, DESIGN.md dan backend tidak diubah pada penyelesaian ini.

**Checkpoint:** laporkan cakupan halaman, bukti browser, dan batas integrasi, lalu tanyakan konfirmasi untuk fase 3.

## Fase 3: integrasi dan pelengkapan backend

Urutan dependensi: audit kontrak → sesi/izin → schema/storage → telemetry/API/log/worker → integrasi halaman dan mutation → preview → manifest diagram. Pakai ulang implementasi existing yang memenuhi kontrak; lengkapi atau perbaiki gap berdasarkan bukti.

### 3.1 Audit kontrak dan autentikasi

- [ ] Buat matriks gap PRD versus source/OpenAPI/runtime untuk `backend/app/admin`, adapter akun/helpdesk, migration, worker, supervisor/collector, dan tes existing.
- [ ] Verifikasi `/admin-session`, capabilities, login/refresh/logout/me, serta mapping izin tepercaya. Sinkronkan status implementasi PRD berdasarkan hasil yang terbukti.
- [ ] Implementasikan session store server dengan token terenkripsi, TTL, cookie ID opaque HttpOnly/SameSite/Secure produksi, invalidasi logout, dan refresh paralel yang terkontrol.
- [ ] Terapkan guard BFF dan backend untuk setiap izin modul; uji akses langsung, anonim, nonadmin, expired/revoked, serta penolakan role dari `user_metadata`.
- [ ] Terapkan allowlist environment/backend, Origin/CSRF, batas login/read/stream, redaksi error, dan konfigurasi server tanpa secrets pada bundle/URL/storage browser.

### 3.2 Schema, persistence, dan manajemen data

- [ ] Audit migration SQL/Alembic existing terhadap empat ERD dan source model aktual; lengkapi indeks, constraint, akun DB terbatas, serta prosedur rollback/retensi yang diperlukan.
- [ ] Uji migration pada database lokal/terisolasi. Siapkan hasil review sebelum meminta persetujuan penerapan pada database bersama/produksi.
- [ ] Lengkapi override editorial, nilai efektif, arsip/pulihkan, reset override, validasi relasi, dan perlindungan identitas immutable.
- [ ] Pastikan reader/search/feed/detail/library memakai nilai efektif dan status arsip secara konsisten; scraper tetap dapat memperbarui source tanpa menghapus override.
- [ ] Terapkan ETag/If-Match, idempotency key, operation ID, serta transaksi mutation/audit/outbox. Operasi Supabase Auth lintas layanan memakai operation record dan rekonsiliasi.
- [ ] Integrasikan API admin-data, akun, library terbatas, helpdesk, dan audit melalui BFF; lengkapi kontrak/paging/filter/masking yang belum tersedia pada endpoint lama.
- [ ] Implementasikan invalidasi cache setelah commit dan event perubahan berizin tanpa menghapus draft pengguna.

### 3.3 Telemetry dan API monitoring

- [ ] Audit/perbaiki middleware ASGI: request ID tervalidasi, observation ID unik, status/outcome, time-to-headers, durasi body final, dan finalisasi in-flight termasuk disconnect/cancellation.
- [ ] Verifikasi scope bisnis/admin/preview, pengecualian route, route template, unmatched label terbatas, count sebelum sampling, serta histogram dan cutoff konsisten.
- [ ] Lengkapi agregat realtime/historis, buffer/antrean terbatas, flush asynchronous idempotent, retensi, sampling, dan pelaporan drop/coverage/storage unavailable.
- [ ] Lengkapi capabilities, snapshot, timeseries, inventaris/detail endpoint, request list/detail, health, alert, dan stream sesuai kontrak PRD.
- [ ] Hubungkan halaman monitoring melalui BFF dengan validasi filter dan respons private/no-store. Ganti data contoh pada jalur produksi dengan API nyata.

### 3.4 Log runtime dan realtime

- [ ] Audit supervisor/transport/collector existing; lengkapi ingest yang dimulai sebelum Uvicorn serta tetap dapat merekam import/startup failure.
- [ ] Integrasikan logger aplikasi, Uvicorn, stdout/stderr, dan lifecycle melalui satu jalur ingest kanonis per sumber.
- [ ] Terapkan event kanonis, `console_text`, capture kind, checkpoint, korelasi opsional, redaksi sebelum antrean/store/broadcast, batas event/byte, truncation, dan sanitasi ANSI/OSC/control sequence.
- [ ] Sediakan list/detail/stream log berizin dari jalur collector/log store yang tetap dapat dibaca ketika API yang dipantau mati.
- [ ] Implementasikan SSE backend dan relay BFF, snapshot/reset/replay, Last-Event-ID, deduplikasi, heartbeat, backoff/jitter, polling fallback eksklusif, abort, dan cleanup subscription.
- [ ] Pastikan stream runtime memiliki cursor dan izin sendiri, serta sesi/izin diperiksa ulang tanpa menggandakan subscription.
- [ ] Hubungkan kedua mode runtime UI ke event nyata yang sama; label format console dari record jika bukan tangkapan output asli.

### 3.5 Health, alert, dan proses independen

- [ ] Audit/lengkapi worker probe, evaluator alert, dan cleanup yang berjalan di luar container/proses API serta tanpa browser terbuka.
- [ ] Terapkan probe/timeout/ambang gagal-pulih, dependency check cached, availability dan coverage terhadap jadwal aktual.
- [ ] Terapkan threshold, minimum sample, hold, deduplikasi, state unknown ketika data stale, serta jalur baca probe/insiden saat API down.
- [ ] Validasi batas satu worker/satu instance API MVP, identitas writer terbatas, kuota retensi, dan restart/gap semantics.

### 3.6 Preview dan manifest diagram

- [ ] Implementasikan BFF `/api/comic-preview` terotorisasi untuk run start/status/stop, source/feed/search/detail/chapter, serta relay gambar dengan handle opaque terikat run.
- [ ] Ikuti bentuk respons API aktual, identitas source+slug, seluruh metadata chapter, nomor pecahan, dan kontrak lazy-load/prefetch backend.
- [ ] Gunakan URL direct/proxy yang diberikan API tanpa pembungkusan ganda; tegakkan allowlist/redirect/payload limits dan jangan meneruskan credential admin ke host gambar.
- [ ] Terapkan TTL/buffer run, izin URL inspector, concurrency/batal/retry, diagnosis per tahap, dan korelasi request/runtime tanpa mengubah progress/bookmark/library pengguna.
- [ ] Hubungkan Data Flow/ERD ke manifest topology/schema dan overlay terukur yang diizinkan. Verifikasi state existing/usulan terhadap migration yang benar-benar diterapkan.

### 3.7 Verifikasi integrasi dan hasil fase

- [ ] Jalankan tes kontrak/unit/integrasi terfokus setiap area yang diubah, termasuk tes existing yang relevan; catat database/runtime yang digunakan.
- [ ] Jalankan frontend hasil build terhadap backend/database/collector/worker terkontrol dengan akun uji sesuai profil izin.
- [ ] Pastikan jalur produksi tidak bergantung pada generator/data contoh atau fallback sukses rekaan.
- [ ] Dokumentasikan API/config/migration, matriks gap yang tersisa, bukti runtime, serta keputusan operasional yang dibutuhkan untuk fase 4.

**Kriteria selesai:** seluruh P0 terhubung ke sumber nyata pada lingkungan uji terkontrol; sesi/izin, telemetry, runtime log, worker, mutation, dan preview memiliki bukti integrasi. Pengujian beban lengkap dan staging tetap pekerjaan fase 4.

**Checkpoint:** laporkan hasil integrasi dan batasnya, lalu tanyakan konfirmasi untuk fase 4.

## Fase 4: testing, hardening, dan penerimaan

### 4.1 Functional, security, dan regression

- [ ] Uji browser end-to-end: login → overview → endpoint → request → runtime; filter/konteks kembali dan sesi lintas reload.
- [ ] Uji sesi expired, refresh bersamaan, logout, pencabutan izin, akses langsung, CSRF/Origin, rate/stream limits, dan isolasi environment.
- [ ] Uji dataset deterministik untuk count/status/histogram/cutoff, stream completion/disconnect, sampling, replay/reset/deduplikasi, serta flush retry tanpa hitungan ganda.
- [ ] Uji konflik dua admin, idempotent retry, arsip/pulihkan, reset override, rollback audit/outbox, invalidasi cache, dan rekonsiliasi akun lintas layanan.
- [ ] Uji regresi reader/search/feed/library dan scraper terhadap override/arsip; relasi/progress pengguna tetap utuh.
- [ ] Uji Preview: semua jalur masuk, chapter kosong/pecahan/404/503, payload berubah, URL direct/proxy/signed expired, gambar korup/terpotong, stop/retry/perpindahan cepat, dan tidak ada write library.
- [ ] Masukkan secrets sintetis melalui header/query/body/log/exception; periksa browser, BFF, buffer, DB, SSE, detail/copy log, serta audit untuk kebocoran.

### 4.2 Recovery, collector, dan performa

- [ ] Uji API down, DB down, worker/collector down, import/startup failure, hard kill, restart, log rotation, graceful shutdown, dan slot unknown/gap yang sesuai.
- [ ] Uji stream terputus, tiga kegagalan → polling → kembali SSE, viewer lambat, buffer overflow, koneksi dibatalkan, serta jumlah subscription stabil.
- [ ] Uji threshold/minimum sample/hold/pemulihan alert dengan clock terkontrol; probe tetap mendeteksi down tanpa browser terbuka.
- [ ] Jalankan profil PRD: satu worker/environment, 100 request bisnis/detik selama 15 menit, hingga 200 route template, 20 viewer SSE, dan dataset historis tujuh hari; catat hardware dan campuran workload.
- [ ] Ukur target p95 freshness telemetry/log ≤3 detik, query snapshot/agregat ≤500 ms, overhead p95 ≤5%, dan Overview usable ≤3 detik pada RTT 100 ms. Target ini belum merupakan hasil pengukuran.
- [ ] Verifikasi memori/buffer tetap terbatas serta sampling/retensi/kuota byte-row dan kehilangan data dilaporkan secara eksplisit.

### 4.3 Browser, desain, dan aksesibilitas

- [ ] Uji hasil build produksi pada light/dark, viewport 360/375/768/1024/1440 CSS px, landscape, zoom teks 200%, reduced motion, dan forced colors/fallback yang relevan.
- [ ] Ukur kontras AA; periksa keyboard, urutan fokus, Escape, dialog, focus return, grafik/diagram alternatif daftar, serta target sentuh.
- [ ] Periksa SSR/hydration, tema saat startup/storage ditolak, console, layout/scroll, state per modul, serta selection/copy/autoscroll Terminal dengan buffer penuh.
- [ ] Uji Data Flow pada pan/zoom/resize/label panjang dan target jumlah node/edge; panah tetap terhubung dan stale tidak menjadi aktivitas live.
- [ ] Periksa keempat ERD readonly dan collision CSS daisyUI/React Flow, lazy loading library, serta inspector berizin.
- [ ] Catat click-through kontrol satu per satu, screenshot dan kritik/perbaikan hasil render, lalu jalankan Delivery Gate Anti-slop pada deliverable aktual.

### 4.4 Staging dan serah hasil

- [ ] Sebelum penerapan staging, konfirmasi target domain/host Node.js, dukungan SSE/proxy, lokasi worker/collector independen, akun admin uji, kuota DB, serta izin penerapan migration dan konfigurasi.
- [ ] Setelah disetujui, uji melalui host/reverse proxy sebenarnya: buffering/cache stream, timeout, cookie secure, sesi, jalur API down, cleanup, dan batas topology.
- [ ] Jalankan instalasi dari lockfile bersih, lint, typecheck, build, serta tes backend/frontend yang diwajibkan; simpan hasil dan daftar batas yang belum teruji.
- [ ] Lengkapi runbook backend/pipeline/DB down, retensi, rotasi session key, restart, rollback ke admin lama, serta pemulihan migration yang relevan.
- [ ] Susun laporan acceptance per FR/AC dan hasil benchmark; tandai item blocked/unrun secara eksplisit. Perbarui status PRD berdasarkan bukti.

**Kriteria selesai:** seluruh P0/AC relevan lulus dengan bukti pada lingkungan yang disebutkan, pengujian staging dan benchmark tercatat, serta runbook tersedia. Jika host/credential belum tersedia, penerimaan staging tetap belum selesai meskipun validasi lokal lulus.

**Checkpoint:** serahkan hasil dan sisa batas. Publikasi/go-live produksi merupakan pekerjaan berikutnya yang memerlukan konfirmasi pengguna; tidak otomatis dilakukan setelah testing.

## Peta migrasi 33 halaman prototype

Rute detail yang belum ditetapkan PRD di bawah merupakan rencana pemetaan; verifikasi identitas dan kontrak API pada fase implementasi. Rute statis seperti `new` dipisahkan dari segmen ID dinamis.

| Kelompok | HTML prototype | Rute aplikasi yang direncanakan |
| --- | --- | --- |
| Sesi | `login.html` | `/login` |
| Overview | `index.html` | `/overview` |
| Endpoint | `endpoints.html`, `endpoint-detail.html` | `/endpoints`, `/endpoints/[endpointId]` |
| Request | `requests.html`, `request-detail.html` | `/requests`, `/requests/[observationId]` |
| Runtime | `runtime-logs.html`, `runtime-log-detail.html` | `/runtime-logs`, `/runtime-logs/[logEventId]` |
| Health | `health.html` | `/health` |
| Alert | `alerts.html`, `alert-detail.html` | `/alerts`, `/alerts/[incidentId]` |
| Komik | `comics.html`, `comic-detail.html`, `comic-edit.html` | `/data/comics`, `/data/comics/[comicId]`, `/data/comics/[comicId]/edit`; tambah melalui `/data/comics/new` |
| Chapter | `chapters.html`, `chapter-detail.html`, `chapter-edit.html` | `/data/comics/[comicId]/chapters`, `/data/chapters/[chapterId]`, `/data/chapters/[chapterId]/edit`; tambah melalui daftar chapter komik |
| Genre | `genres.html` | `/data/genres` dengan editor sesuai prototype |
| Source | `sources.html`, `source-detail.html` | `/data/sources`, `/data/sources/[source]` |
| Akun/library | `accounts.html`, `account-detail.html`, `account-edit.html`, `account-library.html` | `/data/accounts`, `/data/accounts/[userId]`, `/data/accounts/[userId]/edit`, `/data/accounts/[userId]/library`; tambah akun nonadmin melalui daftar |
| Helpdesk | `helpdesk.html`, `helpdesk-detail.html` | `/data/helpdesk`, `/data/helpdesk/[submissionId]` |
| Audit | `audit.html`, `audit-detail.html` | `/data/audit`, `/data/audit/[auditEventId]` |
| Preview | `comic-preview.html`, `preview-detail.html`, `preview-reader.html` | `/comic-preview`, `/comic-preview/[source]/[slug]`, `/comic-preview/[source]/[slug]/chapters/[chapter]` |
| Data Flow | `data-flow.html` | `/data-flow` |
| ERD | `data-model.html` | `/data-model` |

## Cakupan requirement dan bukti yang harus tersedia

| Requirement PRD | Frontend | Integrasi | Penerimaan |
| --- | --- | --- | --- |
| FR-01: sesi | 2.2 | 3.1 | 4.1, 4.4 |
| FR-02: overview | 2.2 | 3.3, 3.4 | 4.1, 4.2 |
| FR-03: endpoint | 2.2 | 3.3 | 4.1 |
| FR-04: request log | 2.2 | 3.3, 3.4 | 4.1, 4.2 |
| FR-05: health | 2.2 | 3.5 | 4.2 |
| FR-06: alert | 2.2 | 3.5 | 4.2 |
| FR-07: state/pemulihan | 2.5 | 3.4, 3.5 | 4.1, 4.2, 4.3 |
| FR-08: modul data | 2.3 | 3.2 | 4.1 |
| FR-09: mutation/konflik | 2.3 | 3.2 | 4.1 |
| FR-10: canvas flow | 2.4 | 3.6 | 4.3 |
| FR-11: ERD/dictionary | 2.4 | 3.6 | 4.3 |
| FR-12: UI/responsive | 2.1, 2.5 | 3.7 | 4.3 |
| FR-13: skill/Delivery Gate | 2.5 | 3.7 | 4.3 |
| FR-14: runtime Terminal/Terstruktur | 2.2 | 3.4 | 4.1, 4.2, 4.3 |
| FR-15: instrumentasi/collector | 2.2 | 3.3, 3.4 | 4.1, 4.2 |
| FR-16: feed/search/chapter | 2.4 | 3.6 | 4.1 |
| FR-17: reader/gambar/proxy | 2.4 | 3.6 | 4.1, 4.3 |
| FR-18: diagnosis/korelasi | 2.4 | 3.6 | 4.1 |
| FR-19: daisyUI | 1.2, 2.1 | 3.7 | 4.3, 4.4 |
| FR-20: stylesheet custom | 1.2, 2.1 | 3.7 | 4.3, 4.4 |
| FR-21: Data Flow custom | 2.4 | 3.6 | 4.3 |

## Batas MVP dan keputusan operasional

- Gunakan satu environment dan satu worker/instance API sebagai asumsi MVP; kapasitas aktual diverifikasi sebelum staging/go-live.
- P1 mengikuti PRD, termasuk multiworker dengan agregator bersama, rule editor/alert eksternal, bulk mutation, editor/reorder gambar chapter, dan laporan preview persisten. Fitur tersebut tidak menjadi syarat selesai P0.
- Pertahankan aplikasi Flutter, `web/prototype`, dan admin HTML lama selama transisi. Penghapusan admin lama memerlukan pekerjaan migrasi tersendiri.
- Mode Terminal hanya menampilkan log tersanitasi; tidak menambahkan command execution, shell/PTY, atau restart proses melalui UI.
- Lokasi transport log/collector, hosting SSE, akun uji, kuota DB, serta credential lingkungan diselesaikan sebelum pekerjaan yang bergantung padanya. Konfirmasi fase tidak menjadi bukti nilai konfigurasi tersebut sudah tersedia.
- Pemanggilan Context7 untuk API/config library dilakukan pada fase implementasi yang relevan dan mengikuti versi yang terpasang. Todo ini tidak memasang atau mengklaim versi dependency terkini.

## Catatan verifikasi perencanaan

Deliverable fase 0 adalah dokumen todo. Pemeriksaan mencakup cakupan FR-01 sampai FR-21, pemetaan 33 HTML, urutan dependensi, tautan lokal, dan checkpoint konfirmasi. Kesesuaian dokumen diperiksa terhadap PRD serta source yang dibaca. Tidak ada klaim Delivery Gate UI produksi, build aplikasi, pengujian browser/backend, migration database, benchmark, atau staging telah lulus pada tahap ini.

## Riwayat konfirmasi fase

| Fase | Keputusan pengguna | Bukti hasil | Langkah berikutnya |
| --- | --- | --- | --- |
| Perencanaan | Diminta pada instruksi awal; mode during dikonfirmasi | Dokumen ini | Minta konfirmasi memulai fase 1 |
| 1 | Disetujui; starter langsung di root `web/` | [Selesai, bukti fase 1](admin_starter_phase1.md) | Awal fase 2 disetujui untuk komponen |
| 2 | Fondasi disetujui 27 Oktober; kelanjutan fase 2 disetujui 28 Oktober; penyelesaian penuh diminta 30 Oktober 2026 | [Fondasi selesai](admin_ui_components_review.md); [frontend selesai dan bukti final](admin_frontend_phase2_completion.md) | Minta konfirmasi fase 3; belum diizinkan |
| 3 | Menunggu | Belum tersedia | Belum diizinkan mulai fase 4 |
| 4 | Menunggu | Belum tersedia | Serah hasil; go-live menunggu konfirmasi tersendiri |
