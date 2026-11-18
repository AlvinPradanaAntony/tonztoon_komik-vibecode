# Migrasi tabel dan scrollbar admin

Lingkup: frontend Next.js fase 2. Integrasi monitoring/backend belum dilakukan.

## Implementasi

- `@tanstack/react-table` 9.3.1 mengelola pipeline filter global/kolom, sorting, dan pagination di wrapper `Table<T>`. Versi terpasang memakai API v9 (`useTable`, feature composition), bukan contoh API v8 `useReactTable`.
- `TableColumn<T>[]` mendefinisikan accessor, header, cell renderer, dan metadata class/row header. Markup semantik, token, daisyUI dan `tt-*` tetap dikendalikan aplikasi. Header sortable memakai tombol keyboard dan `aria-sort`; loading, empty, error dan retry tetap tersedia.
- Starter, tabel bucket/endpoint Overview, inventaris endpoint, request, log terstruktur, dan health memakai wrapper yang sama. Overview mempertahankan daftar endpoint singkat tanpa pagination dan menyinkronkan sorting/pencarian dengan URL. Tabel lain memakai pagination lokal; pemilih ukuran halaman tetap tersedia setelah ukuran dinaikkan.
- `ScrollArea` memakai `overlayscrollbars` 2.17.0 dan `overlayscrollbars-react` 0.5.7. Sidebar desktop/drawer serta tabel menggunakan instance React yang dibersihkan saat unmount. Scrollbar autohide saat pointer meninggalkan area (700 ms), warna mengikuti tema; viewport berlabel dan dapat difokuskan. Tabel mendukung scroll horizontal lokal.
- Dependency, import, CSS dan struktur SimpleBar telah dihapus dari aplikasi Next.js. API tabel lama `head`/`children` dan filtering/sorting manual untuk tabel telah diganti. Penyaringan teks viewer Terminal tetap terpisah dari tabel terstruktur. Prototype HTML dan laporan historis mempertahankan konteks implementasinya.

## Dokumentasi dan validasi

Context7 dipakai untuk TanStack Table dan OverlayScrollbars. Contoh v8 yang dikembalikan salah satu query dicocokkan ulang dengan panduan resmi dan deklarasi paket v9.3.1 terpasang sebelum implementasi.

- PASS: lint, typecheck, production build.
- PASS: `node scripts/check-table-model.mjs`: urutan numerik, filter global/kolom sebelum pagination, perpindahan dan batas halaman, reset halaman setelah filter, empty result dan ukuran halaman.
- PASS: `node scripts/check-overview-demo.mjs`: seed, skenario/rentang, retensi, agregasi, quantile dan missing data.
- Browser Chrome lokal port 3100: starter next/last boundary, filter dari halaman kedua, reset halaman, empty/loading/error/retry, sorting dan ukuran halaman terverifikasi. Overview sorting keyboard memperbarui `sort=count&order=desc`; pencarian menghasilkan empty state. Severity ERROR pada log terstruktur menyisakan satu baris ERROR.
- Pada emulasi mobile 375 px: lebar dokumen 375 px; viewport tabel 333 px dengan isi 740 px, sehingga overflow horizontal tetap lokal. Drawer mempunyai viewport 719 px dan konten 882 px dengan OverlayScrollbars aktif.
- Tema terang dan gelap digunakan pada pemeriksaan; token scrollbar mengikuti variabel kontrol. Bukti tampilan terang: [starter-light.png](screenshots/admin-table-scroll/starter-light.png).

Browser sesekali mengalami timeout dispatch input; hasil yang dicatat di atas diambil dari state DOM setelah pembaruan selesai. Browser juga memuat ekstensi yang menghasilkan warning/injeksi atribut; pemeriksaan ini tidak menyatakan console browser bebas warning, pengujian lintas browser penuh, audit kontras seluruh halaman, maupun integrasi backend lulus.

## Pemakaian

Berikan `data`, `columns`, dan `caption` ke `Table`; gunakan `globalFilter` dan `columnFilters` untuk pencarian. Sorting dapat lokal melalui `initialSorting`, atau dikendalikan pasangan `sorting`/`onSortingChange`. `pagination={false}` menampilkan semua hasil; `pageSize` menentukan ukuran awal. `footer` menerima jumlah hasil terfilter dan total data. Header yang tidak memiliki makna urutan perlu `enableSorting:false`.

Data saat ini lokal. Untuk backend berhalaman, kontrak total row, filter dan sorting server perlu adapter tersendiri pada fase integrasi; jangan memfilter hanya satu halaman server sebagai keseluruhan dataset.
