# Koreksi fidelitas UI fase 2

## Surface environment seragam — 28 Oktober 2026

Background kontrol komposit dipindahkan ke `.tt-environment`; select netral di dalamnya transparan, tanpa sudut surface kedua. Tinggi internal 42 px dan frame sekitar 44 px, dengan padding kanan 16 px. Disabled menyamakan surface pembungkus ke panel. Focus ring dan picker mengambang tetap mengikuti kontrak sebelumnya.

Verifikasi Chrome pada `localhost:3100/overview`: background pembungkus dark `rgb(24,27,32)` dan light putih; background select internal transparan pada keduanya. Tinggi DOM terukur sekitar 44 px pada frame dan 42 px pada select. Screenshot dark ditinjau secara visual; [bukti dan pengukuran](screenshots/admin-select-surface/). Build lulus. Ini koreksi lokal kontrol komposit, bukan perubahan palette atau perilaku picker.

## Panel picker tanpa border — 28 Oktober 2026

Sesuai permintaan pengguna, panel `::picker(select)` pada komponen bersama memakai border 0 dan shadow dua lapis: offset/blur 4/12 px serta 12/24 px. Opacity light 10%/8%, dark 24%/20%, dengan radius existing 16 px. Border bidang select, fokus, opsi dan aturan penempatan tetap dipertahankan. Perubahan berupa CSS; verifikasi visual revisi shadow belum dijalankan karena tab browser pengujian tidak dapat diakses. Bukti screenshot pada bagian sebelumnya mendahului koreksi shadow ini.

## Koreksi fokus, tab dan picker select — 28 Oktober 2026

Permintaan lanjutan pengguna mengganti border tab rentang aktif menjadi surface tanpa border. Focus ring keyboard tab tetap tersedia; garis indikator grafik tetap mengikuti varian underline. Environment memakai focus ring pada pembungkus termasuk dot, melalui `:focus-within` dan `:has(select:open)`; select internal tidak mempunyai outline kedua. Field biasa tetap memberi ring pada kontrol, bukan label/helper.

Picker reusable tetap `<select>` native. CSS customizable select mengutamakan bawah, menyesuaikan horizontal, lalu flip-block saat ruang bawah tidak cukup. `calc-size(stretch, ...)` membatasi tinggi ke ruang yang tersedia; daftar panjang memakai scroll lokal. Browser tanpa fitur ini memakai picker sistem; posisi fallback sistem tidak dapat dijamin lewat CSS.

Prioritas browser `most-block-size` dinetralkan dengan `position-try-order:normal` agar area lebih besar di atas tidak mengalahkan pilihan awal ke bawah. Ikon picker native dipulihkan karena daisyUI menyembunyikannya saat memakai panah background. Screenshot desktop final di [final-native.png](screenshots/admin-select-focus/final-native.png) memakai viewport native 1280 × 720 untuk menghindari artefak tiling/resize pada capture emulasi; screenshot mobile gelap ada di [dark-375.jpg](screenshots/admin-select-focus/dark-375.jpg).

Verifikasi aktual pada development server 3100: terang 1440 dan gelap 375, pilihan rentang via ArrowRight, select via keyboard End/Enter dan Escape, serta layar pendek 844 × 390. Pada layar pendek picker terukur 157 px dan opsi terakhir dapat digulir ke y 373, masih di dalam viewport 390. Pada viewport 1440 × 560 dengan kontrol di y 449–493, picker berbalik ke atas: opsi berada di y 352–440. Ring wrapper solid 3 px, outline internal none, border marker tab 0 px. Lint, typecheck dan build lulus. Bukti di [folder fokus/select](screenshots/admin-select-focus/). Pengujian engine non-Chromium dan screen reader belum dijalankan. Prototype tidak diubah.

Delivery Gate koreksi terbatas: keyboard/fokus, opsi panjang/scroll, dua tema, dan reflow yang diperiksa lulus. Perubahan mempertahankan token, tipografi, struktur komponen serta ENERGY 2 / RHYTHM 2 / MOTION 1 existing. Fase 2 keseluruhan tetap terbuka.

28 Oktober 2026. Cakupan: shell admin dan Overview Next.js dibandingkan dengan `web/prototype/index.html`, dengan root `DESIGN.md` sebagai kontrak. Fase 2 keseluruhan masih berjalan; fase backend belum dimulai.

## Hasil

- Brand, seluruh kelompok menu, ikon SVG prototype, breadcrumb, footer admin, toggle tema lingkaran, sidebar 80/240 px, toggle bergerak dan crossfade ikon diterapkan pada shell React.
- Navigasi memakai `ScrollArea` reusable dengan SimpleBar React 3.3.2, scroll lokal autohide, nama aksesibel, dan recalculate setelah drawer dibuka. Tooltip collapsed memakai popover manual, mendukung hover/fokus/Escape serta ditutup saat scroll/resize.
- Overview mengikuti susunan prototype: judul, panel demo, filter, metadata, empat KPI, grafik/health berdampingan, tabel endpoint enam kolom, pipeline strip dan keterangan data contoh. Padding Panel dan badge dikoreksi dari hasil pengukuran browser agar wrapping baris health sama.
- Rentang waktu, grafik dan Terminal/Terstruktur memakai `Tabs` reusable. Rentang/mode log memakai segmented; grafik memakai underline. Arrow/Home/End, roving tabindex, panel inert dan animasi komponen existing dipertahankan.
- Token aksen dan tinta/surface status light/dark mengikuti prototype. Fill varian solid daisyUI dipisahkan dari tinta semantik. Override netral pada admin dibatasi `data-tone=neutral`; tidak menimpa varian status. Layer vendor diletakkan sebelum components/utilities.
- Dialog/Drawer tetap native modal dengan focus management. Header brand dan close icon tersedia melalui props bersama; halaman belakang terkunci saat modal terbuka.

## Pengukuran desktop

Chromium, viewport 1440 × 1000 CSS px, scrollbar gutter stabil, Production contoh, 5 menit, panel demo terbuka. Angka berikut merupakan geometri DOM, bukan hasil pixel diff otomatis.

| Region | Prototype | Next.js |
| --- | --- | --- |
| Topbar | x 241, y 17, tinggi 80 | Sama |
| Judul halaman | x 269, y 125, tinggi 67,609 | Sama |
| Panel demo | x 269, y 216,609, tinggi 204 | Sama |
| KPI | x 269, y 544,609, tinggi 159,109 | Sama |
| Grid grafik/health | x 269, y 751,719, tinggi 568,125 | Sama |

Bukti: [terang desktop](screenshots/admin-ui-fidelity/light-1440.jpg), [gelap desktop](screenshots/admin-ui-fidelity/dark-1440.jpg), [terang mobile](screenshots/admin-ui-fidelity/light-375.jpg), [gelap mobile](screenshots/admin-ui-fidelity/dark-375.jpg), dan [pengukuran](screenshots/admin-ui-fidelity/measurements.json). Keempat screenshot final ditinjau secara visual. Label `Frontend` dan keterangan API belum terhubung sengaja menjelaskan status aplikasi, menggantikan label prototype.

## Verifikasi

| Pemeriksaan | Hasil |
| --- | --- |
| `npm run lint` | PASS, exit 0 |
| `npm run typecheck` | PASS, next typegen dan tsc --noEmit, exit 0 |
| `npm run build` | PASS setelah koreksi CSS/token terakhir; build produksi dijalankan pada 127.0.0.1:3101 |
| `node scripts/check-overview-demo.mjs` | PASS: seed 200/0/394/100, semua skenario/rentang, retensi, total bucket/endpoint/KPI, quantile, dan Staging tanpa data |
| Responsif | Dua tema pada 360, 375, 768, 1024, 1440 serta landscape 844 × 390; tidak ada overflow horizontal halaman. Tabel/grafik memakai scroll lokal |
| Sidebar | Default 80 px pada 1024 dan 240 px pada 1440 diperiksa sebelum preferensi manual. Preferensi expanded kemudian bertahan pada matrix produksi, termasuk 1024 |
| Motion | Sidebar/canvas/toggle 280 ms cubic-bezier(.4,0,.2,1); ikon opacity 180 ms dan transform 280 ms. Fokus tetap pada toggle. Reduced motion dipakai untuk screenshot lalu emulasi dipulihkan |
| Keyboard/overlay | Arrow/Home/End tab rentang/grafik; tab log Terstruktur; tooltip fokus/Escape; dialog snapshot/Escape/fokus kembali; drawer focus wrap, Escape, scroll lock dan penutupan/pemulihan fokus saat breakpoint berubah |
| Data/UI | Search kosong/reset, Staging kosong/pemulihan, denied menyembunyikan KPI, skenario error menghasilkan 25 respons 5xx, dan pemulihan tampilan diperiksa |
| Runtime | Tidak ada error/warning console pada pemeriksaan produksi; mismatch hydration SVG title diperbaiki |
| Prototype | Tidak diedit; `git diff --numstat -- web/prototype` kosong |

Kontras pasangan tinta/surface semantik: GET light 5,73:1 dan dark 5,56:1; success 6,50/8,22; warning 6,84/7,86; error 5,91/6,47. Muted di surface putih 7,58:1 dan surface dark 9,52:1. Ini pemeriksaan pasangan token yang dipakai Overview, bukan audit seluruh state hover/solid komponen. Bukti RGB runtime disimpan bersama pengukuran.

## Data dan batas penerimaan

Simulator Overview menghasilkan event/probe lokal; KPI, quantile, bucket dan endpoint dihitung dari event yang sama. Waktu seed tetap agar SSR deterministik. Skenario ini belum menggantikan evaluator insiden server dan belum dibagikan lintas route; halaman monitoring lain masih memakai fixture historis yang berlabel. Tidak ada SSE, autentikasi atau backend bisnis yang diintegrasikan pada koreksi ini.

Arah existing dipertahankan: Anti-slop DURING + Taste app screens, ENERGY 2 / RHYTHM 2 / MOTION 1. Fokus visual tetap kondisi API dan KPI. Ikon berasal dari prototype; warna menyatakan data/status/fokus; tanpa aset atau arah desain baru. Kritik render yang ditangani: shell tidak sesuai, tab berupa kelompok Button, select terlalu sempit, wrapping health berbeda, semantik warna dark, dan hydration SVG.

Gerbang koreksi shell/Overview lulus untuk cakupan dan pemeriksaan di atas. **Gerbang fase 2 keseluruhan tetap terbuka**: login/editor/preview/diagram serta kelengkapan interaksi monitoring masih mengikuti todo. Zoom teks 200%, forced colors, screen reader, storage ditolak, engine lain dan pixel diff seluruh halaman belum diuji pada revisi ini. Tidak meminta persetujuan fase 3 pada checkpoint ini.
