---
version: alpha
name: TonzToon Admin
description: Sistem desain TonzToon berdasarkan prototype revisi 12 dan kontrak produksi Next.js PRD 1.5, 26 Oktober 2026.
---

# TonzToon Admin

## Overview

Dokumen ini adalah **satu acuan desain web admin TonzToon**. Arah dan token berasal dari migrasi sistem desain sebelumnya serta tampilan Overview yang sudah disetujui pengguna. Cakupan ini tidak mengubah desain aplikasi Flutter. Revisi 12 menerapkan keputusan pengguna pada 26 Oktober 2026 untuk menyesuaikan pill/tab dan tipografi dengan Taste: pilihan navigasi netral, tab bergaris bawah, filter waktu segmented netral, serta teks minimum 11 px. Perilaku sidebar, toggle, drawer, overlay, focus ring, inisialisasi tema dan sesi demo terhubung tetap mengikuti kontrak existing. Pada 25 Oktober 2026 pengguna mengizinkan JavaScript untuk interaksi prototype; implementasi produk tetap memakai Next.js.

Format mengikuti [spesifikasi DESIGN.md Google Labs](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md), versi **alpha**, dengan delapan bagian dan token YAML sebagai dokumentasi. Penggunaannya tidak memerlukan CLI, dependency, atau skrip pemeriksa desain tambahan. Format ini merupakan konvensi dokumentasi yang dipilih proyek, bukan standar universal seluruh alat vibecode. Aturan produk, styling produksi, dan izin mengikuti [PRD 1.5](docs/prd_web_admin_monitoring.md).

Pembacaan desain: konsol operasional dengan surface berlapis, kontrol radius 8 px, data yang mudah dipindai, dan gerak minimal. **ENERGY 2 / RHYTHM 2 / MOTION 1**. Biru TonzToon menandai data dan focus keyboard; pilihan navigasi/tab menggunakan surface atau garis netral dengan teks foreground. Aksi primary memakai foreground di atas canvas dan secondary memakai surface dengan border control. Charcoal netral menjaga pembacaan dark mode. Inter melanjutkan identitas existing. Motif resource `(source, slug)` berulang pada breadcrumb, detail, dan inspector untuk mencerminkan katalog multisource.

Permintaan pengguna pada 25 Oktober 2026 menetapkan aplikasi nyata memakai Next.js resmi, Tailwind, daisyUI, dan CSS custom modern. Data Flow produksi memakai card/node custom dengan dashed arrow yang interaktif dan beranimasi, dengan exception **MOTION 2 khusus viewer flow**; ERD produksi memakai React Flow. Aturan dan bukti prototype tetap terpisah. Warna, typography, bentuk, serta shell bersama mengikuti desain TonzToon saat komponen library diterapkan.

Gunakan logo [existing](assets/logo_app_sm.png), tanpa membuat logo atau avatar pengganti. Prototype mengikuti tema sistem dengan pilihan pembalikan tersimpan pada sesi browser. Bootstrap inline sinkron di head membaca pilihan tersebut dan menetapkan data-theme sebelum stylesheet utama; runtime menyelaraskan checkbox dan perubahan tema sistem tanpa membalik tema sekali lagi saat startup. Pilihan lebar sidebar desktop tersimpan pada sesi yang sama dan terpisah dari drawer. Storage yang ditolak/rusak memakai tema sistem dan tidak menghalangi navigasi. Pada aplikasi Next.js, preferensi tema eksplisit tersimpan didahulukan lalu sistem. Mode antislop mengikuti pilihan sesi atau preferensi sah; pilihan DURING pada sesi penyusunan ini tidak menjadi mode global untuk sesi berikutnya.

| Acuan | Peran |
| --- | --- |
| Dokumen ini | Token, komposisi, aksesibilitas, dan perilaku lintas halaman |
| [Source stylesheet](web/prototype/styles.input.css) | Implementasi token dan komponen Tailwind bersama |
| [Overview HTML](web/prototype/index.html) | Acuan visual dan interaksi contoh: filter, SVG, tabel, sidebar, serta detail |
| [README](web/prototype/README.md), [QA](web/prototype/QA.md), [Delivery Gate](docs/admin_design_review.md) | Build, bukti verifikasi, dan batas penerimaan |

Prototype memakai **HTML dan Tailwind CSS**. Konten awal, angka, tabel, grafik, ikon, dan detail tertulis langsung pada HTML serta berlabel data contoh. Satu [prototype.js](web/prototype/prototype.js) menambahkan pencarian/filter, form dan perubahan lokal, feed contoh, reader file lokal, serta viewer diagram. Tidak ada app.js, framework, module shell/UI, generator fixture, atau pemeriksa desain tambahan.

Setiap halaman menyertakan bootstrap tema kecil dan style critical di head, setelah meta color-scheme dan sebelum link stylesheet. Bootstrap ini tidak memakai async/defer atau menunggu DOMContentLoaded. Style critical hanya menetapkan color-scheme dan background page light/dark dari token existing, memakai urutan cascade layer yang sama. Background tetap benar ketika stylesheet atau script aplikasi terlambat. Saat data-ui-loading aktif, transisi/animasi tidak berjalan; atribut dihapus setelah inisialisasi dan dua requestAnimationFrame. Konten tidak disembunyikan dengan opacity/visibility dan tidak menunggu timer buatan. Tanpa JavaScript, CSS prefers-color-scheme serta checkbox native tetap menjadi fallback.

Checkbox tema diselaraskan dengan runtime; CSS menyediakan fallback tanpa JavaScript serta mengatur lebar sidebar. Details/summary membuka data tambahan; popover native menyediakan drawer dan detail Overview; dialog native menyediakan preview perubahan dan konfirmasi. SimpleBar lokal diaktifkan melalui atribut HTML untuk autohide. Filter daftar dan Overview mengubah data contoh serta URL. Environment memakai select native; segmented waktu/tab grafik memakai button dengan aria-pressed dan label tetap.

Kontrol yang tampak interaktif harus memberi hasil yang dapat diperiksa. Pada Overview, environment/rentang memperbarui KPI, periode, bucket/tabel grafik, endpoint, dan detail popover. Tab grafik mengganti metrik serta unit; pencarian/urutan mengubah hasil endpoint, dengan reset saat kosong. Total bucket dan endpoint harus cocok dengan KPI. Staging tanpa sampel tidak menampilkan availability/latensi sehat. Tautan investigasi mempertahankan environment, rentang, resource, dan konteks kembali.

Halaman berikutnya mengikuti token, shell, dan komposisi ini. Simulasi izin/perubahan memakai data browser dan tidak membuktikan keamanan atau transaksi backend. Reader mengunduh tiga placeholder SVG lokal dengan HTTP/decode terukur; skenario error tetap dilabeli simulasi. Next.js, autentikasi, otorisasi server, telemetry, proxy, SSE, dan audit produksi merupakan pekerjaan implementasi berikutnya.

## Colors

```yaml
colors:
  page: "#edf0f4"
  page-dark: "#090a0d"
  canvas: "#ffffff"
  canvas-dark: "#101215"
  surface: "#ffffff"
  surface-dark: "#181b20"
  panel: "#f2f4f7"
  panel-dark: "#23272e"
  inset: "#e9eef4"
  inset-dark: "#2b3038"
  overlay: "rgba(15, 23, 42, 0.60)"
  overlay-dark: "rgba(6, 9, 15, 0.72)"
  foreground: "#0f172a"
  foreground-dark: "#f1f3f5"
  muted: "#475569"
  muted-dark: "#b9c1ce"
  subtle: "#526176"
  subtle-dark: "#a8b3c3"
  line: "#dfe5ec"
  line-dark: "#343a43"
  control: "#718096"
  control-dark: "#8792a4"
  primary: "#1a5fa8"
  primary-dark: "#5ba3e8"
  primary-soft: "#eaf2fc"
  primary-soft-dark: "#172938"
  on-primary: "#ffffff"
  on-primary-dark: "#172b46"
  secondary: "#172b46"
  secondary-dark: "#172b46"
  on-secondary: "#ffffff"
  on-secondary-dark: "#ffffff"
  success: "#166534"
  success-dark: "#68d391"
  success-soft: "#edf7ef"
  success-soft-dark: "#18291f"
  warning: "#805b00"
  warning-dark: "#f5c451"
  warning-solid: "#f5b932"
  warning-solid-dark: "#f5c451"
  on-warning: "#172b46"
  warning-soft: "#fff8e1"
  warning-soft-dark: "#302918"
  incident: "#fffbeb"
  incident-dark: "#211e18"
  warning-line: "#d4b476"
  warning-line-dark: "#75603b"
  danger: "#b91c1c"
  danger-dark: "#f08a8a"
  danger-soft: "#fef2f2"
  danger-soft-dark: "#301f23"
  chart: "#2b7cd4"
  chart-dark: "#5ba3e8"
  chart-area: "#edf4fd"
  chart-area-dark: "#152331"
  chart-error: "#b91c1c"
  chart-error-dark: "#f08a8a"
```

YAML pada bagian ini menyimpan **26 peran warna dalam dua tema**. Nama tanpa suffix adalah light; suffix `-dark` menyatakan padanan dark, bukan palette alternatif per halaman. Prototype memakai nama semantik yang sama dengan `light-dark()` dan `color-scheme`; selector `data-theme` tetap tersedia untuk implementasi tema eksplisit pada aplikasi. Jangan membuat palette baru per halaman.

| Peran DESIGN.md / utility Tailwind | Custom property CSS |
| --- | --- |
| page, canvas, surface, panel, inset | --bg, --canvas, --surface, --panel, --surface-alt |
| foreground, muted, subtle | --fg, --muted, --subtle; subtle digunakan melalui custom property |
| line, control | --line, --control |
| primary, primary-soft, on-primary | --accent, --accent-bg, --on-accent |
| secondary, on-secondary | --secondary, --on-secondary |
| success, success-soft | --success, --success-bg |
| warning, warning-soft, incident, warning-line | --warning, --warning-bg, --incident-bg, --warning-line |
| danger, danger-soft | --danger, --danger-bg |
| chart, chart-area, chart-error | --chart, --chart-area, --chart-error pada SVG |

Susunan surface: `page` di luar shell, `canvas` pada area kerja, `panel` pada grouping/header, kemudian `surface` pada isi. Light memakai panel abu lembut di sekitar isi putih. Dark memakai background hampir hitam, canvas charcoal gelap, isi sedikit lebih terang, dan header panel satu tingkat di atasnya. `inset` dipakai untuk kelompok kontrol. Perbedaan lapisan tetap halus; jangan mewarnai seluruh permukaan dengan biru/navy atau menyamakan semua lapisan.

Border panel `line` hanya pemisah wadah. Kontrol memakai `control` agar batas interaksi terukur. Primary/secondary solid tidak dipakai sebagai warna status. Hijau/amber/merah selalu disertai label/ikon status. Insiden mempunyai background tersendiri: pada light nilainya sama dengan warning-soft, pada dark lebih tenang daripada badge warning.

Selection navigasi memakai line/foreground pada kedua tema. Pada Next.js, sesuai koreksi pengguna 28 Oktober 2026, rentang waktu memakai surface/foreground tanpa border pada tab aktif; focus ring keyboard tetap tersedia. Tab grafik memakai teks foreground dan garis indikator 2 px. Warna primary tetap tersedia untuk data, focus, dan elemen semantik yang memerlukannya; jangan menjadikan label primary sebagai teks kecil di atas primary-soft dark tanpa pengukuran pasangan yang sebenarnya.

Kontras minimum teks normal **4.5:1**, batas kontrol/seri grafik bermakna **3:1**. Border dekoratif bukan batas kontrol. Pengukuran mencakup hover, pressed, focus, disabled, composite, dan kedua tema. Contoh pasangan primary: putih di biru light 6.47:1; navy di biru dark 5.34:1. Angka ini tidak menggantikan pemeriksaan seluruh komponen.

## Typography

```yaml
typography:
  body:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.5rem
  body-sm:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 0.875rem
    fontWeight: 400
  label:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 0.75rem
    fontWeight: 500
  micro-label:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 0.6875rem
    fontWeight: 500
  heading:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 2rem
    fontWeight: 600
  heading-min:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 1.6rem
    fontWeight: 600
  panel-heading:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 1rem
    fontWeight: 600
  metric:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 2.1rem
    fontWeight: 600
  metric-min:
    fontFamily: 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif'
    fontSize: 1.5rem
    fontWeight: 600
  code:
    fontFamily: monospace
    fontSize: 0.75rem
    fontWeight: 400
```

Inter untuk heading dan isi, fallback sistem saat font web tidak tersedia. Body 1rem dengan line-height 1.5. Heading dan angka KPI berbobot 600; heading panel 1rem/600. Tabel/deskripsi biasa 0.875rem; label padat 0.75rem. Brand-sub, eyebrow, tag, dan badge navigasi minimum 0.6875rem (11 px pada root 16 px), termasuk sidebar collapsed; label kecil tidak dijadikan ukuran default isi halaman. Brand-sub memakai tracking .02em dan eyebrow tanpa tracking tambahan. Teks code yang mewarisi ukuran relatif tidak boleh turun di bawah 0.6875rem.

H1 memakai `clamp(1.6rem, 2.2vw, 2rem)`; angka KPI memakai `clamp(1.5rem, 2.6vw, 2.1rem)`. Token heading/metric menyimpan batas atas dan token berakhiran min menyimpan batas bawah, karena nilai dimension pada format resmi bukan ekspresi clamp.

Angka memakai tabular numerals, format `id-ID`, dan satuan eksplisit. Generic monospace sistem hanya untuk route, ID, module, stack, dan kode, tanpa dependency unduhan font kode atau klaim bahwa face tertentu telah dimuat. Route/ID panjang membungkus aman; jangan menjadikan heading monospace. Gunakan CSS px/rem, bukan pt/dp native.

Copy berbahasa Indonesia langsung menjelaskan kondisi dan tindakan: `Simpan perubahan`, `Arsipkan komik`, `Pulihkan chapter`, `Tentang snapshot`. Hindari greeting pemasaran, metrik rekaan, testimonial, terminal palsu, dan CTA tanpa objek. Data tidak tersedia ditulis `Belum tersedia`; angka prototype selalu berlabel data contoh.

## Layout

```yaml
spacing:
  unit: 4px
  compact: 8px
  control: 12px
  content: 16px
  panel: 20px
  section: 24px
  gutter: 28px
  spacious: 32px
  touch: 44px
  sidebar-collapsed: 80px
  sidebar-expanded: 240px
  drawer-max: 360px
  main-max: 1660px
  health-column: 320px
  dialog-max: 640px
  kpi-threshold: 56rem
  graph-threshold: 64rem
```

### Hierarki menurut tugas

| Halaman | Keputusan dan susunan |
| --- | --- |
| Overview | Gangguan yang perlu ditindak: insiden, umur data, empat KPI, grafik/health, lalu endpoint investigasi |
| Endpoints | Endpoint berpengaruh: tabel count/5xx/p95, kemudian grafik detail setelah selection |
| Requests | Request penyebab error/latensi: filter, daftar, detail tersanitasi, pause/resume dekat status feed |
| Log Runtime | Mode Terminal/Terstruktur produksi: output server/aplikasi tersanitasi, inspector, izin khusus, pause/autoscroll/status collector; prototype tetap demo |
| Preview Komik | Alur baca nyata: feed/search, detail dan chapter lengkap, reader page, inspector URL/proxy/decode, serta timeline diagnosis |
| Katalog | Resource yang perlu dikoreksi: source/judul, status, informasi keputusan, aksi dekat selection |
| Edit data | Perubahan dan dampak: form, preview lama-baru, satu aksi simpan utama |
| Helpdesk | Laporan yang perlu ditangani: status, kategori, umur, judul, lalu catatan/status detail |
| Akun | Identitas seperlunya, status, izin; data pribadi tidak disebar dalam kartu ringkasan |
| Data flow | Canvas, inspector node/edge, legenda asal data dan coverage |
| ERD | Pencarian tabel/kolom, canvas domain, inspector schema, mode daftar |
| Audit | Waktu, aksi, resource, aktor, hasil, serta diff yang diizinkan |

Empat KPI adalah keputusan Overview, bukan jumlah card wajib untuk halaman lain. Grafik mempunyai pertanyaan, judul, satuan, periode, serta alternatif data tabel. Tidak ada grafik yang hanya mengisi ruang kosong.

### Ruang dan reflow

Skala spacing 4/8 px. Kelompok KPI mempunyai padding/gap 4 px; kontrol memakai 8/12 px; isi card/panel 16/20 px; gap grafik-health 20 px; pemisahan bagian 24 px. Gutter main 16 px di bawah 640 px, 28 px mulai 640 px. Main maksimum 1660 px. Shell desktop memiliki margin atas/bawah/kanan 16 px; margin kiri mengikuti lebar sidebar.

| Viewport | Shell dan isi |
| --- | --- |
| Di bawah 360 px | Drawer; KPI boleh satu kolom |
| 360/375 px | Drawer; KPI dua kolom, bagian utama bertumpuk |
| Mulai 640 px | Gutter 28 px; toolbar membungkus sesuai ruang |
| 768 px | Tetap drawer; inspector dapat berupa sheet |
| 1024–1279 px | Sidebar desktop default collapsed 80 px |
| Mulai 1280 px | Sidebar default expanded 240 px tanpa preferensi manual |
| 1440 px | Grafik dan health berdampingan bila ruang container mencukupi |

Container `dashboard` menentukan empat kolom KPI mulai 56rem (`@4xl/dashboard`) serta grafik + kolom health 320 px mulai 64rem (`@5xl/dashboard`). Ambang memakai lebar konten setelah sidebar berubah. Halaman lain dapat memakai container tugasnya sendiri tanpa mengganti shell/token.

Tidak ada horizontal scroll pada halaman. Tabel/grafik/canvas dapat bergeser di region lokal berlabel dan dapat difokuskan. Kolom keputusan tidak disembunyikan tanpa alternatif detail. Uji landscape, teks 200%, reduced motion, serta keyboard layar; label/satuan tetap membungkus dan sticky area tidak menutupi fokus atau aksi akhir.

### Shell dan sidebar

Shell produksi Next.js (29 Oktober 2026) dirender langsung tanpa fallback teks yang menggantikan seluruh admin. Suspense dikelompokkan menjadi satu batas untuk navigasi desktop, satu untuk navigasi mobile, dan satu untuk label breadcrumb. Setiap kelompok navigasi membaca pathname sekali untuk seluruh menu aktif. Saat pathname belum tersedia pada prerender route dinamis, menu tetap berupa link netral yang berfungsi dan ruang label breadcrumb tetap disediakan tanpa teks loading. Header, sidebar, footer, serta area konten tidak ikut disembunyikan oleh penantian pathname.

Gunakan brand, kelompok/urutan menu, breadcrumb, theme toggle, identitas admin, dan skip link Overview. Hanya daftar navigasi yang bergulir; header/logo dan footer berada di luar host scroll. Sidebar desktop dan margin canvas membaca satu nilai --sidebar-width dan bergerak serentak selama 280 ms dengan cubic-bezier(0.4, 0, 0.2, 1).

Prototype memakai checkbox native berlabel `Ubah lebar sidebar`, CSS :has() dan media query. Default 1024–1279 px adalah collapsed 80 px; mulai 1280 px expanded 240 px. Checkbox membalik default breakpoint, sedangkan JavaScript menyimpan pilihan absolut expanded/collapsed pada sessionStorage melalui kunci tt-prototype-sidebar dan memetakannya ulang saat melewati 1280 px. Preferensi desktop tidak mengubah drawer; storage ditolak memakai fallback memori halaman. Pada implementasi Next.js, toggle memakai nama aksi yang sesuai serta aria-expanded/aria-controls.

Desktop memakai padding sidebar 16 px 18 px 0, logo 36 × 40 px, dan tombol toggle lingkaran 44 × 44 px. Dalam expanded, tinggi header 44 px dan toggle berada di samping brand, pada transform translate3d(160px, 0, 0). Dalam collapsed, header menjadi 100 px dan toggle bergerak ke bawah logo, pada translate3d(0, 56px, 0). Posisi toggle dan tinggi header mengikuti transisi 280 ms yang sama; jangan mengganti posisi secara mendadak ketika menyalin shell ke halaman lain.

Ikon collapse/expand ditumpuk dalam tombol yang sama. Ikon aktif memakai opacity 1, scale(1), rotate(0deg); ikon keluar memakai opacity 0, scale(0.7), serta rotasi 90 derajat untuk collapse atau -90 derajat untuk expand. Crossfade berlangsung 180 ms dan transform 280 ms; ikon tersembunyi tidak menerima pointer. Fokus DOM tetap pada checkbox dan ring berada pada pembungkus tombol.

Menu desktop setinggi 44 px, margin vertikal 4 px, radius 8 px, kolom ikon 44 px dan SVG 18 px. Label berjarak 8 px dari kolom ikon. Teks sidebar memakai nowrap, overflow tersembunyi, dan ellipsis pada label; brand-copy, label menu, tag serta teks/aksi footer memudar selama 180 ms saat collapsed, tanpa mengubah susunan DOM. Tinggi heading kelompok tetap 28 px; label diganti secara visual oleh divider netral saat collapsed. Footer tetap setinggi 64 px pada kedua ukuran.

Collapsed tetap menampilkan logo, ikon, nama aksesibel, indikator aktif, dan badge insiden. Badge menjadi penanda 16 × 16 px di pojok ikon (top 4 px, left 24 px), sedangkan expanded memakai badge inline. Tooltip hover/focus memakai popover manual di luar area scroll; posisinya 12 px setelah sisi sidebar dan dibatasi viewport. Tooltip ditutup melalui pointer keluar, fokus berpindah, Escape, scroll atau perubahan viewport. Menu aktif memakai aria-current="page" pada desktop dan drawer; hanya navigasi sesuai breakpoint yang terlihat.

| State menu | Sidebar desktop | Drawer mobile/tablet |
| --- | --- | --- |
| Default | Background transparan, teks muted | Background transparan, teks muted |
| Hover nonaktif | Light: line; dark: inset (--surface-alt); teks foreground | Background inset |
| Aktif | Background line, teks/icon foreground, weight 600 | Background line, teks/icon foreground, weight 600 |
| Hover aktif | Surface dan teks aktif dipertahankan | Surface dan teks aktif dipertahankan |
| Focus keyboard | Ring 3 px/offset 3 px mengikuti radius 8 px, nama aksesibel tetap tersedia | Ring dan ukuran target yang sama |

Hover desktop mengubah background-color, color dan filter selama 150 ms ease, tanpa menggeser atau membesarkan menu. Sidebar memakai fallback light-dark() ketika data-theme belum tersedia. Hover tidak menjadi pengganti focus indicator atau penanda halaman aktif.

Di bawah 1024 px gunakan drawer dengan lebar min(360px, viewport - 24px), tinggi 100dvh, radius kanan 24 px, tanpa border. Padding 16 px memperhitungkan safe-area atas/bawah. Header memakai logo dan wordmark desktop; close berupa lingkaran 44 px tanpa border, background inset dan focus ring.

Drawer masuk dari translate3d(-100%, 0, 0) ke translate3d(0, 0, 0), lalu bergerak keluar saat ditutup. Slide dan opacity backdrop berlangsung 280 ms cubic-bezier(0.4, 0, 0.2, 1). @starting-style menetapkan posisi awal masuk; transisi display dan overlay memakai allow-discrete agar keluar tetap terlihat sebelum elemen meninggalkan top layer. Browser tanpa dukungan transisi tersebut tetap mempunyai buka/tutup native.

Prototype memakai popover native dengan tombol tutup, Escape, light dismiss dan penutupan setelah memilih tautan. Saat drawer atau overlay detail terbuka, scroll body dikunci, pointer/seleksi pada konten belakang dicegah dan shell diberi inert melalui runtime. Tooltip navigasi tidak mengaktifkan penguncian ini. Klik backdrop menutup overlay jika pointer dimulai dan berakhir di luar batas panel; interaksi di dalam panel tidak dianggap klik backdrop. Ini melengkapi popover native; implementasi Next.js tetap memakai modal dengan focus management penuh.

Saat melewati breakpoint 1024 px, runtime menutup drawer yang masih terbuka. Fokus berpindah ke toggle desktop ketika beralih ke desktop, atau tombol menu mobile ketika fokus sebelumnya berada pada sidebar yang kemudian tersembunyi. Preferensi lebar desktop dipertahankan terpisah.

Pada aplikasi Next.js, sesuai migrasi yang diminta pengguna 28 Oktober 2026, `ScrollArea` memakai OverlayScrollbars/overlayscrollbars-react. Scrollbar autohide saat pointer keluar (delay 700 ms), track 8 px dan thumb memakai control. Viewport scroll berlabel, role region dan tabIndex 0; fokus keyboard mempertahankan thumb. Sidebar menyembunyikan overflow horizontal; tabel memakai kedua sumbu. ResizeObserver menangani perubahan ukuran; sesudah drawer berubah, wrapper memanggil update pada frame berikutnya. Prototype HTML tetap memakai vendor SimpleBar 6.3.3 sebagai referensi historis, tanpa diimpor ke bundle Next.js.

## Elevation & Depth

Canvas desktop memakai shadow ringan `0 2px 12px #0f172a04`. Dialog memakai custom property shadow: light `0 12px 48px #0f172a26`, dark `0 16px 56px #0008`. Dialog/backdrop menandai perubahan konteks.

Card isi tetap flat. Kedalaman terutama berasal dari surface, spacing, dan border netral 1 px. Jangan menambah shadow besar, glow, glass, atau grid dekoratif pada setiap panel. Drawer tidak mempunyai border; focus indicator tetap terlihat.

Backdrop drawer, detail popover dan dialog memakai --overlay-bg: light rgba(15, 23, 42, 0.60), dark rgba(6, 9, 15, 0.72), dengan --overlay-blur 4 px. Scrim dan blur hanya memisahkan konteks overlay dari halaman belakang; panel/isi tetap solid. Opacity backdrop bergerak bersama overlay yang bersangkutan.

## Shapes

```yaml
rounded:
  shell: 28px
  panel: 1.5rem
  inner: 1rem
  field: 1.125rem
  textarea: 1rem
  control: 8px
  full: 9999px
```

| Elemen | Token dan bentuk |
| --- | --- |
| Shell desktop | shell, 28 px; mobile mengikuti tepi viewport |
| Panel, insiden, dialog | panel, 1.5rem / 24 px |
| Isi card mandiri, Textarea multiline | inner / textarea, 1rem / 16 px |
| Input dan Select produksi | field, 1.125rem / 18 px; termasuk readonly dan disabled |
| Surface isi Panel produksi | Radius luar dikurangi inset: 24 - 4 = 20 px |
| Tombol teks/aksi, environment, menu navigasi | control, 8 px |
| Filter waktu | Track 8 px, opsi 6 px, pilihan surface dengan border control |
| Tab grafik | Sudut atas 6 px, garis dasar 1 px dan indikator pilihan foreground 2 px |
| Badge status dan angka navigasi | full / pill, hanya untuk status/data |
| Tombol ikon | Lingkaran 44 x 44 CSS px |
| Logo | Aset 36 x 40 px dalam hit area minimal 44 px |

Bentuk mengikuti fungsi. Hindari pill pada seluruh panel; badge tidak menjadi tombol kecuali memang interaktif. Kontrol utama minimum 44 x 44 CSS px. Focus ring solid **3 px primary dengan offset 3 px**, mengikuti radius batas komponen, termasuk komponen yang border statisnya dihapus. Pada field produksi yang invalid atau bertone error, warna ring mengikuti token danger pada tema aktif; tebal/offset tetap 3 px. Berlaku juga untuk Checkbox dan Select saat picker terbuka, sesuai permintaan pengguna 27 Oktober 2026.

## Components

Skeleton konten Next.js (29 Oktober 2026): fallback Suspense setiap halaman memakai placeholder mengikuti komposisi Overview, daftar, atau detail, sementara shell tetap terlihat. Primitive `Skeleton` memakai line sebagai dasar dan shimmer surface 1,5 detik hanya selama pending; reduced motion memakai bentuk statis. Bentuk dekoratif aria-hidden, satu status pembacaan serta aria-busy menandai konten yang belum siap. Tidak ada tombol placeholder yang dapat difokuskan, durasi minimum buatan, angka contoh, atau loading seluruh viewport. Skeleton diganti saat konten tersedia; data kosong/gagal tetap memakai state aktual halaman.

Progress navigasi Next.js (29 Oktober 2026): satu bar linear indeterminate setinggi 3 px menempel di atas viewport, memakai token accent dengan track accent 15%. Status berasal dari pending `Link` Next.js dan selesai saat navigasi commit atau link dilepas; tidak ada persentase atau durasi loading rekaan. Gerak hanya selama pending, tanpa mengambil fokus atau menggeser layout. Reduced motion memakai segmen statis. Navigasi instan/prefetched dapat melewati indikator. Ini berlaku pada link perpindahan halaman; filter query lokal dan navigasi history browser mengikuti perilaku native. Identitas serta ENERGY 2 / RHYTHM 2 / MOTION 1 tetap berlaku.

Toast action/promise: aksi async menampilkan loading dan menonaktifkan tombol sampai selesai; gagal tetap terbuka dengan pesan retry. Loading promise persisten, kemudian memperbarui notifikasi yang sama menjadi success/error dengan timer terminal baru. Hasil terlambat tidak menghidupkan kembali Toast yang sudah ditutup. Tombol tutup dan penutupan dengan motion tetap tersedia saat proses berjalan; menutup notifikasi tidak membatalkan request. Contoh starter adalah simulasi lokal berlabel. Hasil penting dan recovery mutation tetap tersedia inline sesuai kontrak.

Revisi motion konten Tabs terbaru: crossfade opacity 220 ms ease-in-out tanpa gerak posisi. Panel lama/baru berbagi area grid saat transisi; native CSS display allow-discrete dan starting-style menjaga fade keluar/masuk. Nonaktif langsung inert/aria-hidden, nilai field tetap mounted. Reduced motion berpindah langsung. Ini menggantikan fade/translate 3 px selama 180 ms pada spesifikasi awal Tabs; marker tetap 300 ms.

Tabs produksi reusable (28 Oktober 2026) mengikuti referensi pengguna: track segmented netral abu-abu radius 8 px, padding 4 px, penanda surface radius 6 px/shadow tipis yang bergeser 300 ms. Kontrol minimum 44 px dan teks 14 px. Panel fade/translate 3 px selama 180 ms; reduced motion meniadakan animasi. Track dapat bergulir lokal untuk label panjang. ARIA tablist/tab/tabpanel, satu tab stop, panah/Home/End dan disabled tersedia. Nilai form bertahan antar-panel. Gaya ini khusus Tabs baru; tab grafik prototype yang bergaris bawah tidak diganti. Semua contoh starter lokal dan tidak menyimpan akun/password ke backend.

Tombol tutup Toast memakai glyph 14 px dan permukaan hover/fokus lingkaran 28 px. Area tekan transparan tetap 44 px dengan radius 50% serta focus ring keyboard. Override lokal meniadakan background hover persegi dari Button ghost agar proporsi sesuai kartu Toast yang ringkas.

Koreksi soft gelap terbaru 28 Oktober 2026: gunakan latar transparan shade500, bukan blok opaque950: blue500 rgba(59,130,246,0.14), green500 rgba(34,197,94,0.14), yellow500 rgba(234,179,8,0.12), red500 rgba(239,68,68,0.14). Tinta shade400 tetap opaque. Alpha hanya pada background, sehingga teks/ikon tetap jelas dan surface induk masih terlihat. Yellow memakai 12% untuk menyeimbangkan luminansi; lainnya 14%. Berlaku bersama pada Button soft, Alert, Badge dan StatusBadge produksi. Mapping ini menggantikan latar soft gelap950 pada revisi sebelumnya; soft terang50/700 dan solid tidak berubah.

Koreksi warna produksi terbaru 28 Oktober 2026: pengguna meminta content success/warning solid tetap putih dan warning solid yellow500 (#eab308); success solid tetap green600 (#16a34a). Soft terang tetap background50/tinta700, sedangkan soft gelap memakai background950/tinta400 sesuai gambar referensi: blue #172554/#60a5fa, green #052e16/#4ade80, yellow #422006/#facc15, red #450a0a/#f87171. Ini menggantikan keputusan soft terang pada dark mode dan content gelap pada solid success/warning dalam revisi sebelumnya. Hover/active solid menggelapkan fill 10% dengan content tetap putih. Batas aksesibilitas pilihan putih ini terukur 3.30:1 untuk success dan 1.92:1 untuk warning; tidak diklaim memenuhi AA teks normal. Arahan visual pengguna diprioritaskan dan temuan kontras tetap dicatat.

Revisi produksi 28 Oktober 2026 berdasarkan referensi warna pengguna: solid semantik shade 600; soft memakai background 50 dan tinta 700 pada kedua tema. Info blue600/50/700 = #2563eb/#eff6ff/#1d4ed8; success green = #16a34a/#f0fdf4/#15803d; warning yellow = #ca8a04/#fefce8/#a16207; error red = #dc2626/#fef2f2/#b91c1c. Mapping produksi ini menggantikan nilai semantik sebelumnya dalam dokumen; prototype belum dimigrasikan. Solid blue/red memakai teks putih, green teks #052e16, yellow #0f172a, demi kontras. Hover/active solid memakai 700/putih. Token tinta terpisah mengalir ke Alert/Badge soft dan StatusBadge. Toast tetap surface netral dengan judul/isi tema.

Button secondary produksi memakai latar panel abu-abu lembut dan foreground tanpa border, mengikuti gambar secondary pengguna. Appearance outline terpisah memakai surface, foreground, dan border line netral 1 px mengikuti referensi outline teks/ikon. Appearance soft berwarna memakai 50/700. Kontrak terbaru ini menggantikan secondary berborder pada mapping lama; radius dan target tekan minimum tetap 8 px / 44 px.

```yaml
components:
  canvas:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.shell}"
  sidebar:
    backgroundColor: "{colors.page}"
    textColor: "{colors.muted}"
    typography: "{typography.body-sm}"
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.panel}"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.inner}"
  inset:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.muted}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.inner}"
  button-primary:
    backgroundColor: "{colors.foreground}"
    textColor: "{colors.canvas}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  button-neutral:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  icon-button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
    width: "{spacing.touch}"
    height: "{spacing.touch}"
  nav-active:
    backgroundColor: "{colors.secondary}"
    textColor: "{colors.on-secondary}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
  nav-unavailable:
    backgroundColor: "{colors.page}"
    textColor: "{colors.subtle}"
    typography: "{typography.body-sm}"
  method:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
  badge-success:
    backgroundColor: "{colors.success-soft}"
    textColor: "{colors.success}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-warning:
    backgroundColor: "{colors.warning-soft}"
    textColor: "{colors.warning}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-danger:
    backgroundColor: "{colors.danger-soft}"
    textColor: "{colors.danger}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-neutral:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  incident:
    backgroundColor: "{colors.incident}"
    textColor: "{colors.foreground}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.panel}"
  divider:
    backgroundColor: "{colors.line}"
  control-outline:
    backgroundColor: "{colors.control}"
  incident-outline:
    backgroundColor: "{colors.warning-line}"
  chart-series:
    backgroundColor: "{colors.chart}"
  chart-area:
    backgroundColor: "{colors.chart-area}"
  chart-error-series:
    backgroundColor: "{colors.chart-error}"
  canvas-dark:
    backgroundColor: "{colors.canvas-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.shell}"
  sidebar-dark:
    backgroundColor: "{colors.page-dark}"
    textColor: "{colors.muted-dark}"
    typography: "{typography.body-sm}"
  panel-dark:
    backgroundColor: "{colors.panel-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.panel}"
  card-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.inner}"
  inset-dark:
    backgroundColor: "{colors.inset-dark}"
    textColor: "{colors.muted-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.inner}"
  button-primary-dark:
    backgroundColor: "{colors.foreground-dark}"
    textColor: "{colors.canvas-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  button-secondary-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  button-neutral-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.control}"
  icon-button-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
    width: "{spacing.touch}"
    height: "{spacing.touch}"
  nav-active-dark:
    backgroundColor: "{colors.primary-dark}"
    textColor: "{colors.on-primary-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
  nav-unavailable-dark:
    backgroundColor: "{colors.page-dark}"
    textColor: "{colors.subtle-dark}"
    typography: "{typography.body-sm}"
  method-dark:
    backgroundColor: "{colors.primary-soft-dark}"
    textColor: "{colors.primary-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.full}"
  badge-success-dark:
    backgroundColor: "{colors.success-soft-dark}"
    textColor: "{colors.success-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-warning-dark:
    backgroundColor: "{colors.warning-soft-dark}"
    textColor: "{colors.warning-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-danger-dark:
    backgroundColor: "{colors.danger-soft-dark}"
    textColor: "{colors.danger-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  badge-neutral-dark:
    backgroundColor: "{colors.inset-dark}"
    textColor: "{colors.muted-dark}"
    typography: "{typography.label}"
    rounded: "{rounded.full}"
  incident-dark:
    backgroundColor: "{colors.incident-dark}"
    textColor: "{colors.foreground-dark}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.panel}"
  divider-dark:
    backgroundColor: "{colors.line-dark}"
  control-outline-dark:
    backgroundColor: "{colors.control-dark}"
  incident-outline-dark:
    backgroundColor: "{colors.warning-line-dark}"
  chart-series-dark:
    backgroundColor: "{colors.chart-dark}"
  chart-area-dark:
    backgroundColor: "{colors.chart-area-dark}"
  chart-error-series-dark:
    backgroundColor: "{colors.chart-error-dark}"
```

YAML mendefinisikan warna/shape/type komponen dasar dalam kedua tema. Properti seperti `divider.backgroundColor` mewakili warna garis nonteks, bukan background untuk label teks. Gunakan class bersama berikut; jangan menyalin hex dan perilaku shell ke setiap halaman.

Tabel berikut merangkum source prototype existing. Koreksi radius untuk komponen produksi mengikuti bagian kontrak produksi di bawah; source prototype tidak diubah pada tahap ini.

| Komponen source | Kontrak |
| --- | --- |
| .panel / .panel-header / isi bg-surface | Panel lembut, header berjudul, isi surface inset 4 px; radius 24/16 px |
| .metrics / .metric | Kelompok panel dengan KPI individual, label, angka, satuan, konteks periode |
| .button / .button.primary / .button.secondary | Radius 8 px; label spesifik; primary foreground/canvas solid, secondary surface/foreground dengan border control |
| .icon-button | Lingkaran 44 px dengan nama aksesibel; border kontrol kecuali close drawer |
| .range-control / .chart-tabs | Segmented netral / tab bergaris bawah dengan button native/aria-pressed, hover/focus dan satu pilihan aktif; hasil data/grafik berubah |
| .nav-item.active | Selection konsisten dengan tab; aria-current dan bentuk aktif |
| .sidebar-head / .sidebar-toggle | Header 44/100 px, toggle 44 px dengan perpindahan posisi dan crossfade ikon; mengikuti state sidebar |
| .sidebar .nav-item / .nav-copy / .nav-count | Baris 44 px, label tidak wrapping, hover bertema dan badge tetap terlihat ketika collapsed |
| #mobile-navigation / .navigation-scroll | Drawer slide 280 ms, header tetap, OverlayScrollbars autohide pada Next.js, backdrop dan konten belakang terkunci |
| .searchbox / select / field | Surface, border control, radius 16 px; environment 8 px. Ring searchbox/environment mengikuti pembungkus, bukan bidang internal |
| .status | Badge pill soft success/warning/danger atau inset/muted untuk neutral, selalu berlabel |
| .incident | Background incident, border warning-line, judul/dampak/waktu, aksi investigasi |
| .prototype-dialog / .dialog-note / .app-modal | Detail popover dan dialog native; judul, close/cancel, isi membungkus, preview perubahan maksimum 640 px |
| .table-controls / .table-scroll / .pagination | Filter berlabel, tabel dengan scroll lokal, urutan/hasil kosong/page pulih melalui URL |
| .reader-image / .reader-tools | Area page stabil, status HTTP terpisah dari decode, kontrol retry/stop/reset/lompat dan inspector |
| .diagram-viewport / .diagram-node / .schema-node | Viewer flow/ERD readonly, selection/inspector, zoom/pan serta alternatif daftar |

### State dan keyboard

Hover memberi feedback tanpa mengubah ukuran. Pressed mempunyai feedback singkat; focus tidak dihapus. Disabled/processing memberi alasan dan mencegah submit ganda; refresh contoh memakai opacity 0.65/cursor wait. Izin ditolak dan fitur belum tersedia tidak disamarkan sebagai loading.

Focus indicator memakai token stylesheet **--focus-width: 3px**, **--focus-offset: 3px**, dan **--focus-color: var(--accent)**. Warna mengikuti primary light/dark existing, bukan palette baru. Kontras ring terhadap surface sekitar minimal **3:1**; ring memakai outline, tanpa glow atau shadow tambahan dan tanpa mengubah ukuran layout.

- **Kontrol komposit berbingkai:** searchbox dan environment memakai :focus-within pada pembungkus. Border ikut menjadi primary dan ring mengikuti radius pembungkus, mencakup ikon/dot serta input/select. Outline internal dihilangkan hanya pada kontrol ini karena pembungkus sudah menyediakan penggantinya.
- **Input, textarea, select biasa:** ring mengikuti bidang kontrol yang memiliki border. Jangan memberi ring pada seluruh label .field/.filter-field yang juga memuat judul, helper, atau error.
- **Picker select Next.js:** utamakan bawah kontrol, lalu sesuaikan posisi horizontal atau balik ke atas bila ruang tidak cukup. Gunakan progressive enhancement customizable native select pada engine pendukung, dengan tinggi terbatas dan scroll lokal; engine lain mempertahankan picker sistem. Environment tetap memberi ring pada seluruh pembungkus termasuk dot, tanpa ring kedua pada select internal.
- **Tombol, link dan kontrol keyboard:** gunakan :focus-visible. Checkbox transparan di dalam tombol ikon memberi ring pada tombol pembungkus, tanpa ring kedua pada checkbox.
- **Semantik:** fokus DOM tetap pada input/select/checkbox sebenarnya. Pembungkus tidak mendapat tabindex tambahan; nama aksesibel, Tab, validasi, dan native dropdown tetap bekerja.
- **Surface picker Next.js:** panel dropdown tanpa border, radius 16 px, dengan shadow dua lapis yang proporsional (4/12 px dan 12/24 px; opacity disesuaikan light/dark). Shadow membedakan panel mengambang dari halaman; border bidang select dan focus ring tetap mengikuti kontrak kontrol.
- **Forced colors:** --focus-color memakai warna sistem Highlight agar ring tetap terlihat. Jangan menghapus outline secara global atau menggantinya hanya dengan warna border.

| State | Informasi dan pemulihan |
| --- | --- |
| Loading | Data yang sedang dimuat; skeleton sesuai layout tanpa memindahkan fokus |
| Awal tanpa data | Belum ada traffic/resource serta aksi sesuai izin |
| Filter kosong | Tidak ada hasil filter dan reset |
| Denied | Modul tidak diizinkan, tanpa membocorkan resource |
| Error/timeout | Operasi gagal, waktu snapshot terakhir, retry aman |
| Stale/offline | Koneksi browser, telemetry, dan layanan dibedakan; snapshot berlabel |
| Gap runtime log | Sumber/cursor terputus, sampling/drop/truncation yang diketahui, muat ulang |
| Konflik versi | Draft dipertahankan, muat/lihat versi terbaru |
| Arsip | Status arsip dan pemulihan jika diizinkan |
| Hasil simpan belum pasti | Rekonsiliasi operation/idempotency key, bukan sukses rekaan |

Seluruh kontrol bekerja dengan Tab/Enter/Space sesuai semantik; Escape menutup overlay/tooltip. Modal mempunyai judul, close/cancel, focus trap dan restore focus. Prototype menggunakan showModal() untuk preview/konfirmasi serta semantik native checkbox, details, dan popover. Drawer memakai popover native dengan shell inert dan scroll lock saat terbuka; ini tidak menggantikan kontrak modal/focus management penuh pada Next.js. Ikon SVG ditulis inline dengan vocabulary/stroke existing; ikon dekoratif disembunyikan dari accessibility tree dan kontrol mandiri mempunyai nama aksesibel.

MOTION 1: gerak hanya menjelaskan perubahan lebar, posisi toggle atau konteks overlay. Easing utama cubic-bezier(0.4, 0, 0.2, 1); hover memakai ease. Durasi berikut mencerminkan stylesheet saat ini:

| Perubahan | Durasi/perilaku |
| --- | --- |
| Lebar sidebar, margin awal canvas, tinggi header | 280 ms, berjalan serentak |
| Posisi tombol toggle dan transform ikon | 280 ms |
| Opacity ikon, brand-copy, label/tag/footer; label/divider kelompok | 180 ms |
| Hover menu desktop: background, teks, brightness | 150 ms, tanpa perubahan ukuran |
| Drawer masuk/keluar dan fade backdrop | 280 ms; display/overlay allow-discrete |
| Detail popover/dialog dan backdrop | 200 ms; opacity dan scale(0.96) ke scale(1) |

Pilihan aktif tetap memakai pasangan warna tema yang sama selama hover; jangan menambah animasi gerak menu. prefers-reduced-motion: reduce mematikan transition/animation, termasuk pseudo-element backdrop, serta mengembalikan scroll-behavior ke auto. Penonaktifan transisi saat startup tema tetap berlaku. Tidak ada counter tween, pulse berulang, partikel aliran, atau animasi yang menyiratkan trace aktual.

### Tabel, form, dan mutation

Search, sort, filter, page/cursor, tab, dan environment dipulihkan melalui URL aman. Jangan memasukkan token/data pribadi. Kembali dari detail memulihkan konteks daftar. Header tabel menjelaskan kolom dan sort; pagination mengikuti server pada implementasi nyata. Teks rata awal, angka pembanding rata akhir; header/baris selang-seling boleh memakai panel netral.

Table Next.js memakai TanStack Table v9 headless, dengan data/definisi kolom bertipe dan renderer semantik TonzToon sendiri. Sorting header menyediakan aria-sort dan tombol keyboard. Client filtering dan sorting berjalan sebelum pagination pada dataset contoh yang lengkap; perubahan filter mereset halaman. Overview lima endpoint tidak menampilkan pagination, sedangkan starter menyediakan contoh dua baris per halaman. Mode server belum terhubung; jangan menganggap filter client atas satu halaman server sebagai pencarian seluruh dataset.

Empty state produksi memakai komponen reusable `EmptyState`: ikon SVG existing 56 px, area visual 80 × 72 px, judul 16 px/600, deskripsi muted maksimum 40ch dan aksi opsional di tengah. Padding 24/32 px dan tinggi minimum 224/256 px mengikuti ukuran sm/md, tanpa tinggi tetap atau animasi dekoratif. Ikon search menjelaskan hasil filter kosong; requests/overview menjelaskan daftar kosong; health menjelaskan belum adanya data monitoring. Ilustrasi custom dapat menggantikan ikon, tetap dekoratif dan proporsional. Empty state tabel berada setelah viewport scroll agar tetap di tengah panel mobile meskipun kolom lebih lebar; tabel tetap memiliki baris kosong semantik. Loading/error dipertahankan sebagai state terpisah. Announcement opsional tidak memindahkan fokus.

Uji pergantian pilihan berulang, bukan hanya pilihan pertama. Pilih urutan lain lalu kembali ke prioritas harus memulihkan urutan awal. Enter pada input filter menerapkan pencarian langsung. Pergantian resource memperbarui form, detail dan tautan terkait tanpa membawa nilai record sebelumnya. Arsip/pulih memperbarui status terlihat, menjaga identitas parent/chapter, dan mempertahankan status sebelum arsip.

Nama/judul membuka detail. Menu tambahan hanya memuat tindakan yang tersedia. Form memiliki label nyata, helper seperlunya, error tertaut, dan ringkasan error yang dapat menuju field. Izinkan paste/password manager. Preview menunjukkan nilai lama-baru. Konflik mempertahankan draft; sukses baru tampil setelah committed.

Mutation mengonfirmasi resource dan dampak. Processing mencegah submit ganda, hasil penting tersedia inline, dan hasil jaringan belum pasti mempunyai recovery. Toast hanya pendamping. Pembaruan live tidak memindahkan fokus atau mengumumkan setiap detik; pengumuman hanya perubahan bermakna.

Toast produksi (28 Oktober 2026) mengikuti referensi pengguna dengan struktur sendiri, bukan Alert: kartu surface netral selebar 352 px responsif, radius 8 px, border line, shadow 0 4px 14px hitam 8%, ikon status solid 18 px sejajar judul foreground 13 px/500, deskripsi muted 12 px. Netral tanpa ikon. Close 44 px berada dalam kartu; tidak memakai ripple atau aksen kiri Alert. Lima tone dan enam posisi viewport tersedia. Tumpukan terbaru di depan (offset 8/16 px, scale 0.97/0.94) dibentangkan melalui hover, fokus atau tombol eksplisit. Tinggi kartu diukur untuk expanded dengan gap 12 px; perpindahan transform/tinggi 220 ms, masuk/keluar 200 ms. Durasi default 5 detik dijeda saat hover/fokus/tab tersembunyi; pesan beraksi/custom default persisten. Reduced motion meniadakan transisi. Announcement tidak memindahkan fokus. Konten custom berupa ReactNode; hasil mutation penting tetap inline.

### Pola domain untuk halaman berikutnya

Flow/ERD mengikuti PRD sebagai viewer berizin, tanpa mutation schema/topology. Prototype tetap memakai node HTML dan konektor SVG. Pada Next.js, **Data Flow memakai node/card DOM custom berbasis daisyUI serta konektor SVG dashed dengan panah**, sedangkan **ERD memakai React Flow**. Toolbar berlabel: zoom, fit view, reset, search, filter domain, mode daftar; kontrol animasi berlaku pada flow. MiniMap ERD digunakan jika kompleksitas memerlukannya. Posisi tidak berubah saat telemetry diperbarui; selection membuka inspector, bukan langsung keluar halaman.

Inspector menjelaskan identitas, tipe, existing/proposed, asal data, observed_at, izin, serta link yang tersedia. ERD menunjukkan field/constraint; flow menunjukkan measurement/coverage yang benar-benar diukur. Legend menulis Relasi logis, FK terdefinisi, Usulan, dan Belum diukur; warna/gaya garis hanya pendamping. Tab mencapai node/kontrol, Enter/Space memilih, Escape membatalkan/menutup; fokus membawa node ke viewport. Tidak ada instruksi ARIA hapus/connect yang dinonaktifkan. Alternatif list/tabel memuat informasi dan aksi setara tanpa drag.

Batasi render awal sesuai PRD; domain dapat dilipat dan diperluas bertahap. Jangan menggambar seluruh komik/chapter sebagai node ERD. Deep link hanya menyimpan ID node/tabel, bukan graph atau payload sensitif.

Log Runtime PRD 1.2 memakai izin logs:read dan collector tersanitasi FastAPI/Uvicorn. Pesan memakai font baca, module/stack/ID monospace; traceback multiline satu detail expandable. Pause mempertahankan posisi/fokus, autoscroll dapat dikontrol, clear hanya tampilan lokal. Satu status merangkum event baru tanpa live region pada setiap baris. Link request/audit memerlukan korelasi dan izin sah. Prototype menjalankan buffer contoh maksimum 1.000 event; collector/SSE dan retensi produksi belum terhubung.

Tambahan produksi PRD 1.5, atas permintaan pengguna 26 Oktober 2026: Log Runtime membuka mode `Terminal`, dengan pilihan `Terstruktur` pada toolbar netral. Area output monospace menjadi fokus untuk membaca urutan console dan indentasi traceback FastAPI/Uvicorn; ini fungsi investigasi, bukan dekorasi terminal. Keduanya berbagi filter, event, izin dan stream. Shell, warna level dengan label teks, tema light/dark, serta ENERGY 2 / RHYTHM 2 / MOTION 1 tetap berlaku. Tidak ada prompt command atau animasi ketikan.

Terminal menyediakan jeda/lanjut, kendali autoscroll, jumlah event baru, pencarian buffer, salin teks tersanitasi, detail event, bungkus baris, perluas/kembalikan panel, dan bersihkan tampilan lokal. Scroll ke atas/seleksi menghentikan autoscroll. Default wrap mencegah overflow mobile; wrap nonaktif hanya menggeser region output berlabel. Inspector pada layar sempit menjadi detail satu kolom. Satu pengumuman ringkas event baru menggantikan live region per baris; fokus, seleksi, dan posisi baca dipertahankan sesuai buffer. Status koneksi/API/collector, gap, sampling, truncation, dan teks yang dibentuk dari record terstruktur terlihat tanpa menyamar sebagai output Uvicorn. Batas buffer serta acceptance keamanan/koneksi mengikuti FR-14/FR-15 PRD. Kontrak ini khusus aplikasi nyata; source prototype dan bukti QA revisi 12 tidak diubah atau dianggap membuktikan viewer produksi.

### Kontrak aplikasi nyata: Tailwind, daisyUI, dan CSS modern

Ketentuan ini berlaku pada root `web/`, sesuai keputusan lokasi starter pada 26 Oktober 2026, bukan instruksi memasang framework/daisyUI pada `web/prototype/`. Scaffold memakai `npx create-next-app@latest` dengan Tailwind resmi, kemudian `npm i -D daisyui@latest`. Ikuti konfigurasi plugin CSS versi terpasang. Prototype tetap memakai kontrak HTML/Tailwind dan satu `prototype.js` yang ditetapkan pengguna.

Revisi 29 Oktober 2026: **Tailwind utility-first menjadi pendekatan utama styling aplikasi Next.js.** Layout, spacing, tipografi, ukuran, warna, responsive/container queries, data/ARIA state dan motion yang dapat dinyatakan dengan utility berada pada JSX komponen reusable. Komponen dasar tetap memakai class semantik daisyUI seperti `btn`, `card`, `input`, `select`, `table`, `badge`, dan `modal`. Pemetaan varian memakai nama class lengkap dan statis. Tema light/dark memetakan semantic color/content serta bentuk melalui `@theme inline`; gunakan `bg-surface`, `text-foreground` dan token sejenis agar kedua tema mengikuti kontrak yang sama. `cx` memakai tailwind-merge untuk override utility komponen, bukan mengandalkan urutan string class. Class library tidak menggantikan label, HTML semantik, fokus, validasi, state, atau izin server.

Fondasi komponen awal fase 2 (27 Oktober 2026) berada pada `web/src/components/ui/`. Props, varian, dan batas primitive didokumentasikan pada [kontrak komponen](docs/admin_ui_components.md). Mapping YAML tombol light/dark di atas diselaraskan dengan keputusan revisi 12 dan source prototype `.button.primary`/`.button.secondary`; ini koreksi mapping lama yang masih menunjuk warna/pill sebelumnya, bukan perubahan arah visual. Implementasi prototype tidak diubah.

Token daisyUI info/success/error memakai warna tinta status dan pasangan content untuk varian solid. Warning produksi memisahkan tinta `--warning` dari fill `--warning-solid` dan teks di atas fill `--on-warning`: amber #f5b932 pada terang / #f5c451 pada gelap, content #172b46. Alert, Badge soft/outline, ikon dan border field memakai tinta #805b00 pada terang / #f5c451 pada gelap, dengan surface soft #fff8e1 / #302918. Ini revisi global warning produksi sesuai permintaan pengguna 28 Oktober 2026 agar solid tidak tampak cokelat, sekaligus menjaga keterbacaan teks dan batas field. Mapping warning-solid/on-warning berada pada token produksi; prototype belum dimigrasikan ke revisi warna ini. Tint existing tetap tersedia untuk Badge/Alert soft. Button primary tetap foreground/canvas, secondary tetap surface/foreground dengan border control. Disabled mempunyai aturan terpisah; invalid memprioritaskan error.

Alert produksi memakai surface soft dan aksen border awal 4 px sesuai tone, radius 12 px, padding 16 px, serta gap ikon/teks 12 px. Bingkai ikon bulat 32 px menampung glyph 18 px: pesan untuk netral, i untuk info, centang untuk sukses, tanda seru untuk peringatan, silang untuk error. Judul/isi memakai foreground tema; ikon dan border membawa warna status. Ikon dekoratif tidak menambah announcement atau fokus. Teks membungkus tanpa tinggi tetap; action opsional berada di bawah teks. Pola bersama ini mengikuti referensi pengguna pada 27 Oktober 2026 dan berlaku pada semua varian Alert di starter, tanpa mengubah Badge atau field.

Koreksi ikon Alert pada tanggal yang sama memakai dua lingkaran soft bertingkat sebagai ripple statis: cincin luar 4 px dengan tinta tone 10%, lingkaran dalam tinta tone 20%, keduanya dicampur surface tone. Glyph memakai tinta tone solid. Ukuran total 32 px dan glyph 18 px tetap; efek ini tidak bergerak dan tidak mempunyai pulse/transisi/hover tersendiri.

Revisi Alert produksi 28 Oktober 2026 sesuai permintaan pengguna: border hanya aksen kiri/awal 4 px; border atas, bawah, dan kanan/akhir dihapus. Pemisahan surface memakai shadow tipis 0 2px 6px, slate opacity 6% pada terang dan hitam 18% pada gelap. Radius 12 px tetap. Ini pengecualian shadow khusus pesan semantik untuk memperjelas surface soft; forced colors tetap boleh memakai border sistem agar wadah terbaca.

Radius produksi memakai alias bersama: control 8 px, Input/Select 18 px, Textarea multiline/card mandiri 16 px, panel/dialog 24 px, badge pill. Radius field 18 px disetujui pengguna 27 Oktober 2026; readonly dan disabled mengikuti radius komponen, sedangkan Textarea memakai token tersendiri agar bentuk multiline tetap proporsional. Khusus surface isi langsung di dalam panel berlapis, radius mengikuti radius luar dikurangi inset: 24 px - 4 px = 20 px. Alias inset dan radius turunan menjaga ketebalan lapisan merata pada sudut, sesuai koreksi pengguna 27 Oktober 2026. Ukuran sm/md/lg memperhatikan target sentuh: sm dan md minimum 44 px, lg 48 px; perubahan sm juga mengatur font/padding. Dialog dan Drawer memakai primitive dialog native dengan class modal/placement daisyUI. Drawer merupakan varian overlay samping, agar Escape, modalitas latar, dan focus return tidak digantikan checkbox styling tanpa pengelolaan fokus.

Dialog dan Drawer produksi menutup melalui callback terkontrol saat klik/tap dimulai dan berakhir di luar panel. Klik di dalam panel, klik kanan dan drag melintasi batas panel tidak menutupnya. Escape dan tombol Tutup tetap tersedia, dengan animasi keluar serta pengembalian fokus mengikuti primitive yang sama. Parent dapat menahan permintaan penutupan untuk konfirmasi draft. Perilaku bersama ini diterapkan sesuai permintaan pengguna pada 27 Oktober 2026; hasil runtime dicatat pada laporan komponen.

Stylesheet aplikasi aktif dibatasi pada entry `globals.css`, token/tema `tokens.css`, dan `integrations.css`. Yang terakhir hanya menyimpan baseline dokumen, kontrak variabel vendor OverlayScrollbars, progressive enhancement picker native (`@supports`, anchor positioning, `calc-size`, fallback), lifecycle top-layer dialog (`@starting-style`, discrete transition/backdrop), keyframes Toast serta forced-colors. Layout komponen tidak dipindah menjadi kumpulan `@apply` atau selector `tt-*` baru. Gunakan utility logical/arbitrary/variant sebelum menambah pengecualian stylesheet, dan catat alasan pengecualiannya. Nilai hasil pengukuran runtime (tinggi Toast, koordinat tooltip, marker Tabs) boleh diteruskan lewat CSS variable/style dinamis; jangan menghasilkan nama utility secara dinamis. CSS 2026 adalah praktik CSS modern, bukan versi bahasa/paket baru. Hindari reset berulang dan blanket `!important`. Satu `p-0!` lokal pada sel kosong melindungi padding nol dari utility descendant tabel; tidak ada penguatan global.

Styling statis tidak ditulis sebagai blok inline style panjang pada JSX. Nilai dinamis seperti koordinat/transform viewport boleh memakai props/CSS variables runtime; geometri internal React Flow tetap mengikuti library. Edit stylesheet sumber, bukan CSS build atau distribusi vendor. Override produksi tidak mengubah stylesheet prototype kecuali ada tugas perubahan prototype tersendiri.

Data Flow produksi memakai `.card` dengan modifier node TonzToon dan konektor SVG ber-arrowhead. Anchor tetap menyambung ketika node/viewport berubah. Demonstrasi arah alur diputar melalui kontrol berlabel dan tidak mengklaim trafik nyata. Mode aktivitas hanya menggerakkan edge yang mempunyai bukti telemetry, tanpa menyamakan kecepatan dash dengan RPS/latensi. Pause mempertahankan data/arah; stale menghentikan indikasi aktivitas; reduced motion membuat konektor statis; tab tidak aktif menjeda kerja animasi. ENERGY/RHYTHM tetap 2, sementara MOTION 2 hanya berlaku pada viewer flow produksi sesuai permintaan pengguna.

ERD produksi memakai viewport, node/edge interaction, dan aksesibilitas React Flow dengan tema TonzToon serta inspector/control daisyUI yang sesuai. Controller/stylesheet ERD dipisahkan dari flow custom. Keduanya mempunyai alternatif list/tabel dan tidak mengubah topology/schema server. Pengujian browser produksi diperlukan untuk tema, fokus, pan/zoom/resize, Pause, reduced motion, dan performa graph; bukti prototype tidak membuktikan integrasi ini.

### Resep halaman baru dan kontrak source

Preview Komik PRD 1.3 menggunakan shell/token yang sama, dengan area baca sebagai fokus dan inspector diagnosis sebagai panel sekunder. Desktop menampilkan reader dengan inspector di samping; pada layar sempit panel bertumpuk dan diagnosis dapat dibuka tanpa memaksa gambar melebar. Produk mengambil feed/cover/judul/source dari API; prototype memakai daftar contoh dan placeholder yang jelas berlabel. Daftar chapter lengkap dapat dicari, termasuk nomor pecahan. Jangan mengubah semua halaman menjadi susunan empat KPI Overview.

Reader default vertikal menyediakan nomor page, lompat page, dan chapter sebelumnya/berikutnya dari data aktual. Setiap page mempunyai ruang loading stabil dan status belum diuji/memuat/berhasil/gagal/dibatalkan. Retry, Stop, dan Periksa seluruh page chapter ini mempunyai hasil yang terlihat, tanpa memindahkan fokus atau menghapus error sebelumnya. Browser hanya mengambil gambar dekat viewport sampai admin meminta pemeriksaan penuh chapter. Status HTTP, keberhasilan decode, serta jumlah page belum diuji diperlihatkan terpisah.

Inspector menunjukkan URL payload/sumber/proxy yang dapat dikenali, dimensi, metadata transfer terukur, dan ID korelasi. Query sensitif dimasking; tampil/copy URL lengkap hanya melalui aksi dan izin yang sesuai PRD. URL panjang membungkus dengan aman, bukan memaksa page melebar. Timeline memakai warna/status dengan teks dan tidak mengarang edge berhasil atau pesan runtime. Link log memeriksa izin modul tujuan. Badge Alur API nyata menjelaskan efek lazy-load/prefetch normal tanpa mengklaim progress/bookmark akun diubah.

Reader prototype membatasi concurrency tiga file lokal, melakukan lazy load/prefetch, membatalkan sesi lama, merevoke blob URL, serta mempertahankan riwayat attempt gagal. Hasil QA file lokal dicatat terpisah dari pengujian proxy, gambar komik panjang, korelasi backend, dan perilaku produksi yang belum dilakukan. Token, palette, dan shell existing tetap digunakan.

1. Pilih keputusan utama dari PRD dan tabel hierarki. Gunakan daftar, form, atau viewer sesuai tugas.
2. Buat HTML di web/prototype dari shell Overview, termasuk meta color-scheme, style critical dan bootstrap tema sebelum stylesheet. Jangan memindahkan pembacaan tema awal ke script defer. Ganti title, H1, breadcrumb, aria-current/active, toolbar, dan konten. Link hanya menuju halaman/section yang tersedia; fitur mendatang diberi alasan.
3. Tulis konten awal, ikon inline, grafik SVG, tabel, serta detail langsung dalam HTML. Gunakan utility Tailwind dan komponen existing. Interaksi contoh ditambahkan pada prototype.js yang sama; jangan membuat app.js, module shell/UI, generator fixture, atau logika backend.
4. Pertahankan struktur brand, sidebar, breadcrumb, dan penanda menu aktif. SimpleBar memakai vendor lokal serta atribut HTML. Gunakan kontrol native dan progressive enhancement; labeli data, peran, serta perubahan sebagai contoh lokal.
5. Pakai stylesheet sumber bersama serta mapping nama utility lengkap pada HTML/JavaScript untuk setiap status. @source memindai semua HTML dan prototype.js; jangan membangun nama class sebagian secara dinamis.
6. Tambahkan state umum dan domain yang relevan, lalu periksa seluruh kontrol dan keyboard pada kedua tema.
7. Cocokkan token dan komposisi dengan dokumen ini, build CSS, lalu periksa HTML dan interaksi di browser pada kedua tema dan viewport yang ditentukan. Jangan menganggap simulasi browser sebagai implementasi izin, mutation, feed, atau transaksi backend.

Edit styles.input.css, bukan styles.css hasil compiler. Tailwind 4.3.3 memakai @theme inline; data-theme dipasang sebelum paint, dengan light-dark()/color-scheme dan :has() sebagai fallback native tanpa JavaScript. Container query mengatur reflow/collapse. Urutan layer: theme/base/vendor/components/utilities; style critical head memakai urutan yang sama dan CSS SimpleBar berada di vendor. Utility/@apply menangani layout/type/spacing/state; custom CSS melengkapi SVG, dialog/popover, reader, diagram, scrollbar, dan perilaku visual. @source memindai seluruh HTML dan prototype.js agar state dinamis tetap bergaya setelah kompilasi.

Build menyertakan CSS dan vendor lokal beserta lisensi agar HTML dapat dibuka tanpa Node/CDN library. Inter boleh fallback sistem. Perubahan token/komponen dilakukan pada DESIGN.md dan source dalam pekerjaan yang sama, lalu diperiksa kesesuaiannya saat review. Lockfile hanya mengunci dependency prototype. Lihat README untuk perintah dan rincian build.

## Do's and Don'ts

- Gunakan palette, radius, shell, dan library bersama; jangan menghasilkan ulang font/palette saat menambah halaman.
- Gunakan data aktual beserta periode/coverage. Labeli fixture; jangan menyimpulkan kondisi sehat dari snapshot stale atau membuat angka untuk mengisi panel.
- Uji 360, 375, 768, 1024, 1440 px, landscape, sidebar expanded/collapsed, drawer, teks 200%, reduced motion, dan dua tema.
- Ukur teks 4.5:1 dan kontrol/grafik 3:1 pada hasil render. Jalankan axe dan keyboard; jangan menyatakan linter dokumen sebagai bukti aksesibilitas runtime.
- Pada prototype, uji loading/kosong/error/denied/stale/partial, persistensi sesi, storage ditolak, tema/sidebar, tooltip keyboard, dialog, drawer, dan scroll autohide.
- Periksa filter, form, konfirmasi, konflik, hasil belum pasti, feed lokal, reader, diagram, dan seluruh kontrol setelah Tailwind dikompilasi. Uji integrasi/security secara terpisah ketika Next.js dibuat.
- Catat screenshot, hasil pemeriksaan, dan batas yang belum diuji pada QA/Delivery Gate. Jangan memperluas PASS Overview ke backend, Next.js, atau halaman lain yang belum dibuat.

Revisi 11 merupakan sinkronisasi dokumentasi terhadap styles.input.css, prototype.js dan markup sidebar Overview pada 25 Oktober 2026. Delivery Gate dokumen: **PASS** untuk kesesuaian kontrak/timing/state dengan source, alasan gerak dan hover, identitas/dials yang dipertahankan, serta struktur delapan bagian. Build dan browser tidak dijalankan ulang untuk perubahan dokumentasi ini; angka QA revisi sebelumnya tidak menjadi bukti pengujian ulang animasi/sidebar terbaru. Saat implementasi sidebar berubah lagi, cocokkan kedua ukuran desktop, drawer buka/tutup, hover aktif/nonaktif pada dua tema, tooltip/fokus, perpindahan breakpoint dan reduced motion sebelum memperbarui status QA runtime.

Ikuti alur kerja desain terpadu pada [.agents/rules/ui-design-flow.md](.agents/rules/ui-design-flow.md):
- **Scaffolding desain / pondasi**: [Anti-slop](.agents/skills/antislop/SKILL.md) + [UI UX Pro Max](.agents/skills/ui-ux-pro-max/SKILL.md) hanya setelah keputusan pengguna untuk menyusun/melengkapi fondasi yang belum tersedia atau memadai. Jika klasifikasi meragukan atau arahan skill bentrok dengan kontrak desain, tanyakan opsi beserta kelebihan, kekurangan, dan rekomendasi beralasan; tunggu jawaban untuk bagian yang bergantung padanya. Prosedur lengkap berada pada aturan terpadu di atas.
- **Daily driver**: [Anti-slop](.agents/skills/antislop/SKILL.md) beserta modul concern ([UI](.agents/skills/antislop-ui/SKILL.md), [human](.agents/skills/antislop-human/SKILL.md), [responsive](.agents/skills/antislop-layoutmobile/SKILL.md), [copy](.agents/skills/antislop-copywriting/SKILL.md)) + [Taste Skill](.agents/skills/taste-skill/SKILL.md) sebagai **Director Desain UI**, menggunakan jalur app screen. Penambahan halaman/modul dan migrasi prototype ke framework memakai fondasi existing; scaffold teknis tidak memulai scaffolding desain. Lewati draw untuk perubahan komponen kecil.
- Taste boleh memperbarui dokumen ini saat revisi/redesain yang diminta agar kontrak selaras dengan source UI. Catat alasan, lingkup lokal/global, dampak lintas halaman, serta bukti dan batas pengujiannya; perubahan lokal tidak otomatis mengubah token/font/shell/perilaku global. UI/UX Pro Max dan Taste tidak menjadi dua pengarah pada lingkup keputusan yang sama. Pertanyaan alur fondasi/konflik terpisah dari mode Anti-slop `during/after`.

Untuk API/config library gunakan Context7 sesuai versi terpasang. Rujukan resmi: [Tailwind CLI](https://tailwindcss.com/docs/installation/tailwind-cli), [theme](https://tailwindcss.com/docs/theme), [dark mode](https://tailwindcss.com/docs/dark-mode), [source detection](https://tailwindcss.com/docs/detecting-classes-in-source-files), dan [SimpleBar](https://github.com/Grsmto/simplebar/tree/master/packages/simplebar#readme).


### Sesi demo terhubung (revisi 10)

Panel **Demo lokal terhubung** berada sesudah judul halaman, sebelum area data. Panel dapat ditutup untuk memberi ruang investigasi; pada mobile dimulai tertutup. Tombol dan field memakai token, focus ring parent, ukuran sentuh, dan surface bersama. Tidak ada warna atau shell baru.

Satu sesi browser menjadi sumber observasi untuk Overview, endpoint, request log, runtime, health, insiden, Preview, dan audit. Konten HTML tetap menjadi fallback berlabel fixture ketika JavaScript tidak tersedia. Runtime memakai baseline 1.000 request selama 24 jam dengan 600 di 15 menit terakhir; generator awalnya dijeda. Nilai KPI, bucket, distribusi status, histogram, dan quantile dihitung dari event tersimpan dalam environment/rentang/scope yang sama, bukan dikalikan dari angka HTML. Overview memakai scope reader; admin_preview dan admin_operation dipisahkan. Quantile demo dihitung dari sampel mentah, bukan histogram telemetry produksi.

- **Mulai/Jeda demo** mengendalikan generator; satu tick tiap dua detik nyata memajukan jam simulasi 30 detik. **Langkah 30 detik** berjalan sekali. **Jalankan skenario** menjalankan 90 detik gangguan atau 390 detik pemulihan agar window lima menit dan hold 60 detik benar-benar dievaluasi.
- Skenario: normal/pulih, latensi tinggi, HTTP 5xx, API tidak terjangkau, telemetry terputus, serta lonjakan trafik. Environment simulasi dipilih terpisah dari filter investigasi. Production/Staging tidak saling meminjam data.
- API down menghasilkan probe gagal dan lifecycle collector independen, tanpa access log API palsu. Telemetry gap mempertahankan observed_at terakhir, mencatat coverage parsial dan menjadikan evaluasi metrik unknown. Unknown tidak berarti resolved. Readiness database tetap belum diukur.
- Rule metrik: minimal 100 sampel reader, coverage minimal 80%, window lima menit, hold/recovery 60 detik. Dua probe gagal/sukses menentukan down/pulih. Pipeline gap dievaluasi setelah 30 detik jam demo. Satu insiden aktif per rule/environment mempunyai ID dan timeline stabil.
- Request/runtime/probe masing-masing dibatasi 1.000 event; insiden 100. Eviction retensi dipisahkan dari ingest loss. Coverage menandai sampel yang keluar dari window retensi. Detail yang sudah tidak tersimpan tidak digantikan record lain.
- **Jeda tampilan** menahan daftar dan posisi investigasi; generator bersama tetap berjalan. Buffer menghitung event baru. **Lanjutkan tampilan** memuat observasi unik yang masih dalam rentang/retensi. **Bersihkan tampilan** hanya memberi cutoff lokal, **Tampilkan riwayat** memulihkan riwayat yang masih tersimpan.
- Request ID menghubungkan log request dan runtime. Lifecycle dapat tidak memiliki request ID. Run ID menghubungkan feed/detail/chapter/attempt gambar Preview. Operation ID menghubungkan perubahan admin, request, runtime dan audit; 409/422/hasil belum pasti dicatat tanpa menyimpan payload sensitif. Audit keberhasilan muncul sesudah perubahan lokal dikonfirmasi.
- Reader tetap mengunduh/decode tiga placeholder lokal. Inspector membedakan HTTP aktual file lokal dari status skenario; attempt, cancel, retry dan decode error masuk ke observasi demo dengan scope admin_preview. Tidak ada progress/bookmark pengguna yang ditulis.

State tt-simulation-v1 menyimpan jam, skenario, generator, event dan insiden pada sessionStorage; revisi skema internal saat ini 2. Reload/navigasi pada tab yang sama melanjutkan sesi, bukan menggandakan event. Generator berhenti ketika dokumen tidak terlihat; saat kembali, catch-up dibatasi sepuluh tick dan diberi catatan. Tab terpisah merupakan sesi terpisah. Storage ditolak memakai memori halaman dan menampilkan batas persistensinya. Reset demo juga menghapus draft/perubahan/audit lokal, dengan konfirmasi; tema/sidebar tetap terpisah.

Alur ini membuktikan korelasi demo browser lokal. Tidak membuktikan request backend, SSE, otorisasi server, proxy produksi, telemetry nyata, atau transaksi database. Topologi Flow yang tidak disimulasikan tetap diberi label belum diukur. Pola halaman berikutnya memakai sumber sesi dan link korelasi yang sama, tanpa membuat timer/fixture terpisah. Dokumentasi MDN melalui Context7 menjadi acuan [Page Visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API) dan [sessionStorage](https://developer.mozilla.org/en-US/docs/Web/API/Window/sessionStorage).
