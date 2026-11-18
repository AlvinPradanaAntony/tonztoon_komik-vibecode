# Refaktor Tailwind aplikasi admin

29 Oktober 2026. Lingkup: aplikasi Next.js `web/src`, bukan prototype HTML atau integrasi backend. Acuan visual tetap DESIGN.md, ENERGY 2 / RHYTHM 2 / MOTION 1. Anti-slop during dan Taste app screens dipakai untuk menjaga arah existing.

## Hasil dan kontrak pemeliharaan

- Layout, spacing, tipografi, ukuran, warna, state, breakpoint, container query dan sebagian besar transisi kini memakai utility statis pada komponen React. Tidak ada konversi massal menjadi `@apply` atau generator CSS.
- Shared primitives tetap di `src/components/ui`. `styles.ts` menyimpan resep utility berulang untuk field, focus, tone dan ukuran. `admin/patterns.tsx` menyediakan PageTitle serta pola tabel/detail; tidak menghasilkan stylesheet global. Gunakan komponen/props untuk berbagi markup, konstanta untuk resep class yang pendek.
- Card/Panel menerima `headerClassName`/`bodyClassName`; Dialog/Drawer menerima header/body/panel class; Tabs menerima compact/hidePanels; Select menerima leading dekoratif. Ini menggantikan override global berdasarkan parent admin/dashboard.
- `cx` memakai tailwind-merge 3.7.0 dengan ekstensi radius field/control/inner/panel/panel-inner. Urutan argumen menentukan utility yang dipertahankan. Varian daisyUI tetap dipilih melalui props, bukan menambahkan class semantik yang bertentangan melalui className. Arbitrary variant tidak otomatis dianggap ekuivalen dengan modifier standar; gunakan modifier yang sama saat override.
- Tema memakai token `@theme inline` seperti bg-surface, bg-page, text-foreground, text-muted dan rounded-field. Utility tidak menggandakan nilai warna untuk setiap mode. Nilai runtime yang berasal dari pengukuran tetap berupa CSS variable/inline style untuk marker Tabs, tinggi/offset Toast dan posisi tooltip; tidak membangun nama class secara dinamis.
- Source detection tetap eksplisit ke `src/`. Prototype tidak masuk bundle aplikasi.

Stylesheet layout lama components.css (317 baris), admin.css (217), toast.css (64), serta dua placeholder diagram dihapus. Source aktif tinggal tokens.css (211 baris, termasuk konfigurasi daisyUI dan token) serta integrations.css (65 baris). Angka baris adalah ukuran source, bukan pengukuran ukuran bundle, kecepatan runtime, atau jaminan bebas dead code seluruh repo.

## Pengecualian CSS modern

`integrations.css` menyimpan baseline dokumen dan lima batas integrasi:

1. API variabel scrollbar vendor yang DOM-nya dibuat OverlayScrollbars.
2. Picker native dengan feature detection, anchor positioning, position-try, calc-size, fallback dan pseudo-element. Aturan dikelompokkan agar progressive enhancement mudah diaudit.
3. Lifecycle top-layer dialog/backdrop dengan starting-style dan discrete transitions. Layout panel tetap utility; Escape, focus trap dan focus return tetap perilaku React/native existing.
4. Keyframes masuk/keluar Toast; pemilih animasi, placement, stack, ukuran dan reduced motion ada pada utility.
5. Forced-colors untuk batas komponen dan marker.

Ini penggunaan CSS modern yang relevan pada 2026, bukan paket atau versi bahasa bernama CSS 2026. Hindari stylesheet layout baru, selector parent lintas halaman, arbitrary value berulang tanpa token, serta blanket important. `p-0!` lokal pada sel kosong merupakan satu pengecualian spesifik terhadap padding descendant tabel. Reduced motion shell memakai arbitrary descendant variant dengan specificity yang cukup tanpa important.

## Perbaikan saat verifikasi

- Body diberi bg-page/has-starter bg-canvas: baseline html sebelumnya kalah oleh tema vendor dan membuat sidebar putih.
- Lebar select simulasi dipindah ke FieldFrame agar intrinsic width tidak menyusut.
- Ekstensi radius pada tailwind-merge ditambahkan setelah regression test menangkap rounded-field yang tidak terhapus oleh rounded-control.
- Reduced motion diuji lewat computed transition-property. Varian descendant awal kalah oleh utility desktop; setelah diperbaiki nilainya none.
- Teks solid warning memakai on-warning #172b46 sesuai kontrak desain, menggantikan putih pada fill #eab308. Kontras terukur 7.45:1. Warna fill tetap.

## Validasi

- PASS: lint tanpa warning, typecheck dan production build akhir. Build menghasilkan seluruh route existing; tidak ada source prototype yang dimigrasikan atau diubah.
- `node scripts/check-ui-styles.mjs`: PASS override width, radius custom, layout field, tinggi/padding tombol, tone, serta preservation focus/disabled/readonly/invalid.
- `node scripts/check-table-model.mjs`: PASS sorting, filter global/kolom, pagination, reset halaman, batas halaman dan empty result.
- `node scripts/check-overview-demo.mjs`: PASS seed, skenario, retensi, agregasi, quantile dan missing data.
- Browser Chrome pada 3100: sidebar collapse/expand; Snapshot dialog dan Escape/focus return; mobile drawer dengan scroll lock; tabel lokal tetap horizontal di panel.
- Overview pada kedua tema: 360, 375, 768, 1024, 1440 dan landscape 812 × 375. Lebar dokumen sama dengan viewport pada seluruh sampel. Desktop 1440 memakai empat kolom metrik, viewport sempit dua kolom. JSON matriks disimpan bersama screenshot.
- Starter: next page; query kosong hasil; Reset tabel melalui Enter memulihkan dua baris; invalid menghasilkan border error pada Input/Select/Checkbox/Textarea; readonly dan disabled memakai surface panel serta teks muted. Keyboard ArrowRight memilih tab Preferensi. Toast persisten selebar 352 px terlihat dan aksinya berfungsi; dialog 512 px serta drawer 360 px terbuka, action penutup berfungsi.
- Runtime log terstruktur: Severity ERROR menyisakan satu baris ERROR. Endpoint, Request log, Health dan Alert diverifikasi melalui heading setelah navigasi.
- Screenshot [Overview gelap 1440](screenshots/admin-tailwind-refactor/overview-dark-1440.png), [Overview terang](screenshots/admin-tailwind-refactor/overview-light.png), [mobile terang](screenshots/admin-tailwind-refactor/overview-light-375.png), [drawer gelap 375](screenshots/admin-tailwind-refactor/drawer-dark-375.png), dan [Toast starter](screenshots/admin-tailwind-refactor/starter-toast-light.png).

Browser kadang timeout atau click tidak terproses; interaksi dikonfirmasi melalui perubahan state, dan keyboard dipakai sebagai alternatif. Browser memuat ekstensi yang menyisipkan bis_skin_checked dan menghasilkan hydration warning; tidak ada klaim console bersih. Seluruh kombinasi tone/appearance/state pada setiap viewport, teks 200%, forced-colors, semua posisi/stack Toast, seluruh detail route dan lintas browser belum diaudit penuh. Bukti prototype historis tidak dipakai sebagai bukti aplikasi ini. Integrasi backend tidak berubah dan belum divalidasi oleh pekerjaan ini.

## Delivery Gate pada lingkup refaktor

- Hard Gate PASS: komponen dibangun/dijalankan, state dan kontrol utama diuji; kedua tema tidak overflow pada matriks; tidak ada penambahan aset/statistik/navigasi fiktif. Batas matriks kombinatorial dicatat di atas.
- Purpose Gate PASS: token, glyph, konten serta shell existing dipertahankan; pengecualian CSS memiliki alasan integrasi konkret; tidak menambah efek dekoratif.
- Liveliness PASS: dials existing dipertahankan, angka monitoring tetap fokus layar, motion berfungsi sebagai feedback dan dimatikan saat reduce.
- Craftsmanship PASS: utility lengkap statis, wrapper bertipe, className merge diuji termasuk radius custom, stylesheet layout lama dihapus, source detection terbatas src; fokus, modal dan scroll lokal diuji. Tidak ada klaim ukuran/performa bundle tanpa pengukuran.

Rujukan Context7: [Tailwind utility-first](https://tailwindcss.com/docs/styling-with-utility-classes), [theme](https://tailwindcss.com/docs/theme), [state variants](https://tailwindcss.com/docs/hover-focus-and-other-states), [custom styles](https://tailwindcss.com/docs/adding-custom-styles), serta [tailwind-merge configuration](https://github.com/dcastil/tailwind-merge/blob/main/docs/configuration.md). Contoh arsip v1/v2 dari hasil pencarian tidak dipakai sebagai konfigurasi v4.
