# Hasil fondasi komponen admin, awal fase 2

Tanggal: 27 Oktober 2026. Lingkup yang disetujui: sembilan task fondasi komponen sebelum migrasi halaman secara luas. **Tahap 2.0 selesai; fase 2 secara keseluruhan belum selesai.**

## Hasil implementasi

- Token dua tema mempertahankan palette DESIGN.md revisi 12. Alias bersama mengatur warna semantik, radius, surface, target kontrol, padding, fokus, serta batas ukuran overlay.
- [Komponen UI](../web/src/components/ui/index.ts) mencakup Button, Input, Select, Textarea, Checkbox, Table, Card, Panel, Alert, Badge, StatusBadge, Dialog, Drawer, dan Spinner. Props native, size, tone/variant, loading, disabled, dan invalid dicatat di [kontrak komponen](admin_ui_components.md).
- Komponen memakai class/modifier daisyUI. Override tt-* mengatur kebutuhan TonzToon; warna netral tidak menimpa varian status. Disabled dan readonly mempunyai aturan terpisah.
- [Halaman pemeriksaan](../web/src/components/starter-preview.tsx) menggunakan seluruh komponen tersebut dan menyediakan interaksi lokal yang dapat dioperasikan. Tidak ada request/mutation backend.
- Dialog/Drawer terkontrol memakai modal native, label/description unik, Tab/Shift+Tab yang membungkus di dalam panel, Escape, tombol tutup, dan focus return. Drawer memakai placement modal-start/modal-end, bukan checkbox tanpa pengelolaan fokus.
- DESIGN.md hanya diperbarui pada mapping tombol yang stale serta kontrak fondasi produksi. Bentuk tombol 8 px mengikuti source prototype; tidak menyusun arah visual baru.

Dependency dan lockfile tidak diubah pada tahap ini. Next.js/Tailwind tetap memakai konfigurasi scaffold resmi. Dokumentasi Context7 untuk Next.js, daisyUI dan Tailwind dicocokkan dengan paket terpasang sebelum menulis konfigurasi terkait. Dokumentasi Server/Client Components yang dibundel dalam Next.js juga dibaca.

## Build dan batas sumber

Perintah dijalankan dari web/ pada source final:

| Pemeriksaan | Hasil |
| --- | --- |
| npm run lint | PASS, exit 0 |
| npm run typecheck | PASS, next typegen lalu tsc --noEmit, exit 0 |
| npm run build | PASS, Next.js 16.4.3/Turbopack, exit 0; route / dan /_not-found |
| npm run start -- --hostname 127.0.0.1 --port 3100 | Hasil build produksi berjalan dan dipakai untuk pemeriksaan browser |
| Console Chromium in-app | Tidak ada error/warning yang tercatat selama pemeriksaan final |
| Integritas prototype | 103 berkas selain node_modules, hash sama dengan baseline fase 1 |

Hash gabungan path relatif POSIX dan byte berkas prototype, diurutkan berdasarkan path: `9118b2e6daedc5bf487d088e8e3f678cdc67cd12015b332738f15cf5ab331e12`. Tidak ada perubahan berkas prototype.

Instalasi bersih dari lockfile sudah diuji pada fase 1 dan tidak diulang pada tahap ini karena dependency tidak berubah. Validasi di atas tidak membuktikan backend, BFF, sesi/RBAC, database, SSE, worker, atau staging berjalan.

## Browser dan responsivitas

Pemeriksaan aktual memakai Chromium in-app terhadap hasil next build + next start di http://127.0.0.1:3100/. Dua tema diuji pada tinggi viewport 900 px:

| Lebar CSS px | Tema terang | Tema gelap | Hasil |
| --- | --- | --- | --- |
| 360 | [Screenshot](screenshots/admin-components-phase2/light-360.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-360.jpg) | Satu kolom, tidak ada overflow halaman |
| 375 | [Screenshot](screenshots/admin-components-phase2/light-375.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-375.jpg) | Satu kolom, tidak ada overflow halaman |
| 390 | [Screenshot](screenshots/admin-components-phase2/light-390.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-390.jpg) | Satu kolom, tidak ada overflow halaman |
| 768 | [Screenshot](screenshots/admin-components-phase2/light-768.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-768.jpg) | Panel bertumpuk, field dua kolom |
| 1024 | [Screenshot](screenshots/admin-components-phase2/light-1024.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-1024.jpg) | Panel utama dua kolom, field tiga kolom |
| 1440 | [Screenshot](screenshots/admin-components-phase2/light-1440.jpg) | [Screenshot](screenshots/admin-components-phase2/dark-1440.jpg) | Konten dibatasi 80 rem, tidak ada overflow |

Pada seluruh 12 kombinasi, scrollWidth sama dengan clientWidth setelah layout stabil. Tidak ditemukan kontrol terlihat dengan tinggi di bawah 44 px. Checkbox berukuran 24 px memiliki label/area tekan setinggi 44 px; badge noninteraktif bukan target sentuh. Input/Button sm dan md terukur 44 px; lg 48 px. Selector tema tetap 144 px saat pilihan berubah. Inter Variable terdeteksi pada computed font-family dan document.fonts berstatus loaded.

Landscape 844×390 diuji pada [terang](screenshots/admin-components-phase2/light-landscape.jpg) dan [gelap](screenshots/admin-components-phase2/dark-landscape.jpg), tanpa overflow horizontal. Panel dialog 512×325 px masih menampilkan header, isi, serta footer di viewport pendek: [terang](screenshots/admin-components-phase2/light-dialog-landscape.jpg), [gelap](screenshots/admin-components-phase2/dark-dialog-landscape.jpg).

Overlay 360×800 diuji di kedua tema. Lebar dialog terukur 313 px dan drawer 321 px dalam ruang viewport yang tersedia, tanpa kontrol terpotong: [dialog terang](screenshots/admin-components-phase2/light-dialog-360.jpg), [dialog gelap](screenshots/admin-components-phase2/dark-dialog-360.jpg), [drawer terang](screenshots/admin-components-phase2/light-drawer-360.jpg), [drawer gelap](screenshots/admin-components-phase2/dark-drawer-360.jpg). Drawer desktop terukur 360 px pada sisi start dan end.

[Pengukuran mentah](screenshots/admin-components-phase2/measurements.json) menyimpan matrix viewport, warna computed, varian field, tombol, ukuran, overlay, serta hubungan label/description. Ini rekaman pemeriksaan lokal, bukan telemetry produk.

## Interaksi dan aksesibilitas

| Kontrol/state | Hasil pemeriksaan aktual |
| --- | --- |
| Tema sistem/terang/gelap | Pilihan bekerja; sistem menghapus data-theme eksplisit, tema tersimpan bertahan setelah reload |
| Cari modul | Pencarian monitoring menyisakan Monitoring API; pencarian tanpa hasil menampilkan empty state |
| Kondisi tabel | Ready/loading/empty/error tampil; header/caption tetap ada; loading menandai region busy |
| Coba lagi dan Reset tabel | Kembali ke tiga baris contoh dan kondisi normal |
| Tujuh varian Button | Semua diklik di kedua tema; setiap pilihan mengubah pesan lokal yang sesuai |
| Proses contoh/Akhiri loading | Loading memasang busy dan disabled; aksi pemulihan mengaktifkan kembali tombol |
| Aksi nonaktif | Native disabled; tidak tersedia untuk aksi maupun urutan Tab |
| Ukuran sm/md/lg | Ukuran kontrol berubah sesuai kontrak; minimum 44/44/48 px terukur |
| Lima tone field | Input/Select/Textarea/Checkbox mengikuti neutral/info/success/warning/error pada dua tema |
| Tampilkan invalid | Empat field invalid; modifier error dan pesan tetap muncul saat tone awal netral |
| Tampilkan loading field | Empat field busy, disabled, dan berindikator; kombinasi invalid mempertahankan pesan error di luar kontrol |
| Form kosong | Pesan validasi muncul; fokus berpindah ke Nama pemeriksaan |
| Form valid | Pesan sukses lokal muncul; tidak menyimpan data ke backend |
| Reset form | Menghapus nama/pesan validasi/forced invalid dan mengembalikan fokus ke nama |
| Sumber contoh | Kedua option dapat dipilih |
| Catatan pemeriksaan | Dapat diisi; checkbox menyertakan catatan mengatur disabled textarea; Space bekerja |
| Readonly | Mempunyai surface panel, tetap dapat difokuskan; Tab melewati dua kontrol disabled ke checkbox catatan |
| Label dan description | Tidak ada ID ganda, referensi aria-describedby putus, atau field tanpa label |
| Lewati ke konten | Enter memindahkan fokus ke main#konten |
| Buka dialog | Klik/Enter membuka modal, fokus awal ke Tutup |
| Tab dan Shift+Tab dialog | Membungkus antara Tutup dan aksi footer; fokus tetap di modal |
| Isi dan aksi dialog | Catatan dapat diisi; Gunakan dialog contoh mengubah pilihan lokal dan menutup modal |
| Tutup/Escape dialog | Menutup dan memulihkan fokus ke Buka dialog; reopen tetap bekerja |
| Sisi drawer | Start/end benar, lebar desktop 360 px |
| Pilihan drawer | Button, Input dan Table masing-masing mengubah pilihan lokal dan menutup drawer |
| Keyboard drawer | Shift+Tab/Tab membungkus, Escape/Tutup bekerja, fokus kembali ke Buka drawer |

Nama, hint, pesan invalid, busy dan role semantik diperiksa melalui DOM/accessibility snapshot. Fokus terlihat memakai outline aksen solid 3 px, offset 3 px. Pemeriksaan ini belum mencakup pembacaan dengan screen reader atau browser lain.

## Kontras dan pemisahan state

Kontras dihitung dari warna computed hasil render, bukan hanya pasangan token yang direncanakan. Teks menggunakan ambang 4.5:1, batas kontrol/fokus 3:1. Nilai hover daisyUI berupa Oklab dikonversi ke linear sRGB untuk perhitungan luminance; nilai tersebut tidak diperlakukan sebagai latar transparan.

| Sampel final | Hasil minimum |
| --- | --- |
| 99 sampel teks tema terang | 5.73:1, tidak ada sampel di bawah 4.5:1 |
| 99 sampel teks tema gelap | 5.35:1, tidak ada sampel di bawah 4.5:1 |
| Hover tujuh varian tombol × dua tema | 5.35:1 |
| Teks 60 sampel field, termasuk disabled/readonly | 6.88:1 |
| Batas 60 sampel field terhadap background kontrol | 3.64:1 |
| Placeholder terang/gelap | 6.31:1 / 8.14:1 |
| Focus ring terhadap page terang/panel gelap | 5.66:1 / 5.60:1 |

Script contrast-check.py dari antislop-human juga dijalankan untuk pasangan token info gelap final #101215 pada #5ba3e8: 7.01:1, PASS. Pengukuran hover aktual pasangan yang sama setelah perubahan warna vendor: 5.81:1.

Temuan selama pekerjaan dan perbaikan:

1. Style netral mengalahkan readonly karena spesifisitas. Neutral selector kini mengecualikan readonly; surface/tinta/border readonly diverifikasi terpisah.
2. Checkbox vendor mentransisikan background saat pergantian tema/tone. Transisi dibatasi pada box-shadow; lima warna checked sekarang langsung cocok dengan token masing-masing.
3. Native modal membolehkan peralihan fokus ke chrome browser pada batas Tab. Pembungkusan Tab/Shift+Tab eksplisit ditambahkan dan diuji ulang pada Dialog/Drawer.
4. Hover info gelap semula 4.43:1. Semantic info-content kini memakai canvas; hover terukur 5.81:1 tanpa mengubah palette dasar.
5. Utility minimum width selector tema kalah dari min-inline-size field. Override domain terbatas tt-theme-field kini menjaga lebar 144 px pada dua tema.

Bukti [invalid](screenshots/admin-components-phase2/light-invalid.jpg) dan [loading bersama invalid](screenshots/admin-components-phase2/light-loading.jpg) memperlihatkan bahwa warna kontrol disabled tidak menimpa pesan error.

## Review visual jalur app screen

Arah existing dipertahankan: **ENERGY 2 / RHYTHM 2 / MOTION 1**. Tidak ada draw/seed atau arah visual baru. Pertanyaan halaman: apakah komponen dan state bersama konsisten sebelum dipakai untuk migrasi admin? Panel pemeriksaan menjadi fokus; seluruh contoh jelas berlabel lokal.

Seluruh screenshot final pada matrix dan overlay dibuka dan diperiksa. Review mengacu pada tujuh pertanyaan app-screen Taste; inspeksi DOM/render dijalankan melalui browser yang tersedia, tanpa menambahkan tooling desain ke proyek.

| Pertanyaan review | Penilaian |
| --- | --- |
| Hierarki dan pertanyaan utama | PASS: title pemeriksaan, daftar modul dan galeri aksi terlihat sebelum field/overlay |
| Tepi, jarak dan ukuran panel | PASS: panel berbagi grid dan gutter; panel pendek tidak diregangkan untuk menyamai galeri state yang lebih panjang |
| Warna dan tipografi | PASS: Inter existing, ground netral, inset surface, focus biru. Banyak warna hanya untuk demonstrasi varian semantik yang diminta |
| Konsistensi angka | PASS: tiga baris fixture sesuai hasil pencarian/reset; tidak ada KPI atau persentase kesehatan rekaan |
| Missing value dan status | PASS: integrasi selalu Belum terhubung; varian sukses/gagal di galeri adalah contoh berlabel |
| Legend/collision | PASS: tidak ada grafik/legend yang perlu dicocokkan; label, pesan dan kontrol tidak bertumpuk pada screenshot |
| Ponsel | PASS: panel dan field bertumpuk; kedua kolom tabel tetap terbaca; overlay muat dalam viewport |

Motif yang dipertahankan adalah surface berlapis, primary foreground/canvas, radius kontrol 8 px, serta label domain method/route dan source/slug. Halaman ini merupakan alat pemeriksaan komponen; susunan galeri, banyak varian warna, dan contoh status tidak menjadi layout final Overview. Tidak ditambahkan ilustrasi, aset baru, KPI, atau navigasi yang belum tersedia.

## Delivery Gate Anti-slop

Status akhir: **PASS untuk fondasi komponen dan halaman pemeriksaan yang diuji di atas**. Tidak mencakup halaman admin yang belum dimigrasikan, integrasi, atau penerimaan lintas browser. Setiap item berikut merujuk pada source milik aplikasi dan bukti render/interaksi tahap ini.

| Item | Status dan bukti |
| --- | --- |
| R-01 dekorasi | PASS: surface flat dari token, tanpa gradient/glow dekoratif |
| R-02 copy | PASS: copy komponen/dokumen baru diperiksa tanpa em dash |
| R-03 mobile | PASS: 12 kombinasi ditambah landscape tanpa overflow; screenshot final ditinjau |
| R-04 ikon | PASS: logo existing; chevron dan loading memiliki fungsi kontrol/state |
| R-05 susunan | PASS: setiap panel menguji kelompok komponen yang diminta, tanpa bagian pemasaran pengisi |
| R-06 tipografi | PASS: Inter existing tersaji lokal dan terdeteksi di browser |
| R-07 pola latar | PASS: tanpa grid/dot/blueprint dekoratif |
| R-08 panah | PASS: tanpa panah CTA dekoratif; chevron native Select menyatakan pilihan |
| R-09 badge | PASS: badge berfungsi sebagai sampel status berlabel di dalam galeri/tabel |
| R-10 glass | PASS: surface panel opaque; blur tipis hanya pada backdrop modal untuk memisahkan konteks, sesuai permintaan pengguna |
| R-11 radius | PASS: kontrol 8 px, field/inner 16 px, panel 24 px, badge pill |
| R-12 shadow | PASS: panel diam tanpa shadow tambahan; overlay memisahkan konteks modal |
| R-13 glow | PASS: tidak menambahkan glow |
| R-14 pengulangan panel | PASS: blok tabel/aksi/form/semantik/overlay mempunyai tugas berbeda; tinggi mengikuti isi |
| R-15 CTA | PASS: aksi lokal bernama Periksa isian, Reset form, Coba lagi, Buka dialog/drawer |
| R-16 buzzword | PASS: copy menjelaskan perilaku dan batas contoh, tanpa klaim pemasaran |
| R-17 statistik | PASS: tidak menampilkan metrik/uptime rekaan |
| R-18 testimonial | PASS: tidak ada testimonial/persona rekaan |
| R-19 motion | PASS: gerak terbatas feedback kontrol/loading/modal sesuai MOTION 1; fallback CSS reduce tersedia |
| R-20 identitas | PASS: palette, Inter, inset panel serta identitas source/slug mengikuti TonzToon existing |
| R-21 tema | PASS: terang/gelap/sistem dapat dipilih, diuji dan direkam |
| R-22 ilustrasi | PASS: tidak menambahkan ilustrasi tanpa tujuan |
| R-23 aset | PASS: logo existing dipertahankan, tidak menciptakan aset atau struktur navigasi baru |
| R-24 tautan | PASS: tautan UI hanya skip link ke main yang tersedia; tidak ada menu menuju route kosong |
| R-25 kontras | PASS: teks minimum 5.35:1 pada sampel final; batas field minimum 3.64:1 |
| R-26 fungsi | PASS: seluruh jenis kontrol aktif pada tabel interaksi di atas dicoba; disabled memiliki label/keterangan |
| R-27 state | PASS: ready/loading/empty/error/retry, invalid, success, disabled dan readonly diperiksa |
| R-28 FAQ | PASS: tidak ada FAQ pengisi |
| R-29 palette | PASS: palette DESIGN.md dipertahankan; warna tambahan semata varian status yang diminta |
| R-30 orisinalitas | PASS: meneruskan kontrak TonzToon, tanpa meniru produk lain atau mengganti arah |
| R-31 alasan visual | PASS: radius, surface, fokus, tipografi dan susunan dijelaskan dalam kontrak/review ini |
| R-32 keyboard | PASS: Tab/Shift+Tab/Enter/Space/Escape, skip link, invalid focus dan focus return dicoba |
| R-33 source | PASS: implementasi ditulis langsung pada TSX/CSS, tanpa script yang memodifikasi UI dari luar |
| R-34 dua tema | PASS: matrix render final dan varian status diperiksa pada dua tema |
| R-35 runtime | PASS: lint/typecheck/build exit 0; hasil produksi dijalankan dan kontrol dicoba |
| R-36 klaim | PASS: halaman menyatakan lokal dan belum terhubung; tidak ada klaim keamanan/performa/backend selesai |
| R-37 arah | PASS: DESIGN.md existing dibaca sebelum perubahan; ENERGY 2 / RHYTHM 2 / MOTION 1 diwarisi |
| R-38 kejujuran isi | PASS: tiga modul dan semua status contoh diberi konteks lokal, tanpa aktivitas layanan rekaan |
| Liveness: dials | PASS: 2/2/1 dipertahankan pada seluruh galeri |
| Liveness: konsistensi | PASS: hierarki panel dan motion minimal sesuai dials |
| Liveness: fokus | PASS: title dan pemeriksaan tabel/aksi memimpin, tidak ada banner pengalih |
| Liveness: whitespace | PASS: gutter memisahkan kelompok; padding mengelompokkan label/kontrol/pesan |
| Liveness: aksen | PASS: biru untuk fokus/info; warna status di galeri digunakan untuk verifikasi varian |
| Liveness: motif | PASS: surface berlapis dan identitas resource existing diulang dengan sengaja |
| Liveness: Design Read | PASS: arah existing dan batas migrasi ditetapkan sebelum implementasi |
| C-1 intentionality | PASS: aturan token/cascade dan pengecualian galeri ditulis pada kontrak ini |
| C-2 completeness | PASS: seluruh kontrol aktif memiliki perilaku lokal terverifikasi |
| C-3 composition | PASS: panel sesuai sembilan task fondasi, tanpa filler |
| C-4 resilience | PASS: state/tema/viewport/keyboard dalam matrix di atas berjalan |
| C-5 evidence | PASS: angka dalam laporan berasal dari perintah/DOM/render; batas pengujian disebutkan |

## Batas yang belum diuji dan checkpoint

### Toast action async dan promise, 28 Oktober 2026

Toast action menerima callback sync/async, loading/disabled serta pengunci klik ganda. Berhasil menutup kecuali closeOnClick=false; reject/throw menampilkan pesan retry tanpa menutup. Toast promise menerima Promise atau factory dan opsi loading/success/error berupa pesan/formatter, memperbarui ID yang sama dengan spinner/aria-busy saat pending lalu tone success/error. Durasi pending 0; revision terminal mereset sisa timer tanpa mengganti ID/posisi. API mengembalikan id dan promise hasil asli. Penutupan menghapus ID aktif sehingga hasil terlambat tidak membangkitkan notifikasi; cleanup provider mencegah update setelah unmount. Menutup Toast tidak membatalkan operasi.

Lint dan build/TypeScript lulus. Playwright di development 3100 memeriksa empat kombinasi dua tema dan lebar 1440/360 px: spinner/busy pending, resolve dan reject bersamaan, ID/order tetap sama, formatter sukses membaca hasil, dismissed pending tidak muncul kembali setelah selesai, aksi disabled saat proses berjalan, kegagalan pertama tetap terbuka dengan pesan, retry berhasil memperbarui feedback lokal dan menutup. Tidak ada pageerror. Screenshot terang ponsel dan gelap desktop dibuka; hasil tetap memakai kartu netral/ikon semantik. Bukti di screenshots/admin-components-phase2/toast-promise/results.json dan screenshot terkait. Percobaan awal terganggu HMR/timeout notifikasi saat menunggu; matrix dijalankan ulang setelah koreksi API lint dan jeda hover saat membaca hasil.

Delivery Gate lingkup action/promise: build/runtime PASS; Purpose PASS (feedback async mengikuti hasil nyata promise dan tidak menambah notifikasi terpisah); Liveliness PASS (motion existing dan spinner untuk proses pending); Craftsmanship PASS pada skenario di atas. Unmount, factory yang throw sinkron, formatter gagal, closeOnClick=false dan unwrap hasil return/reject diperiksa pada source/type tetapi belum diuji browser khusus. Tidak ada klaim integrasi backend, pembatalan request, benchmark, atau screen reader nyata. Dokumentasi pemakaian dan DESIGN.md diselaraskan.

### Crossfade konten Tabs, 28 Oktober 2026

Panel Tabs kini memudar keluar/masuk dengan opacity 220 ms ease-in-out tanpa translate. Panel berbagi area grid selama crossfade, memakai display allow-discrete dan starting-style. Panel nonaktif langsung inert/aria-hidden walaupun fade keluar masih terlihat; field tetap mounted. Penanda tab tidak diubah, reduced motion menonaktifkan transisi panel. Kontrak UI dan DESIGN.md mencatat revisi ini menggantikan fade/translate awal.

Lint dan build/TypeScript lulus. Playwright pada development 3100 memeriksa dua tema dan lebar 1440/360 px dengan timeline CSS dijeda pada 110 ms: panel lama/baru sama-sama mempunyai opacity antara 0 dan 1 dan transform none, sementara panel lama sudah hidden/inert/aria-hidden. Setelah selesai panel lama display none. Perpindahan cepat Profil–Preferensi–Profil mempertahankan isian, hanya satu panel tersedia secara semantik; emulasi reduced motion menghasilkan transisi 0s dan opacity aktif 1. Bukti pengukuran: screenshots/admin-components-phase2/tabs-fade/results.json. Tidak ada klaim fps, browser lain atau screen reader nyata.

Delivery Gate lingkup motion: build/runtime PASS; Purpose PASS (crossfade menjelaskan pergantian panel); Liveliness PASS (motion terbatas interaksi, reduce tersedia); Craftsmanship PASS untuk titik tengah/final, perpindahan cepat dan preservasi state yang diukur. Browser tanpa dukungan discrete mempunyai fallback fungsional tetapi exit fade dapat instan; fallback tersebut belum diuji runtime.

### Tabs React berdasarkan referensi pengguna, 28 Oktober 2026

Tabs reusable ditambahkan di web/src/components/ui/tabs.tsx dan diekspor melalui index. Referensi Alpine diterjemahkan menjadi React, dengan track segmented netral dan marker surface bergeser 300 ms mengikuti ukuran/posisi tab aktif. ResizeObserver mengukur layout; panel masuk fade/translate 3 px selama 180 ms. Tidak ada dependency atau global event baru. Ukuran tab minimum 44 px, track radius 8 px dan marker radius 6 px. Gaya baru khusus Tabs produksi sesuai referensi, tidak mengganti tab grafik prototype. Galeri starter menyediakan Profil/Preferensi lokal serta tab disabled; aksi memakai Toast yang sudah ada.

API items/value/defaultValue/onValueChange mendukung controlled dan uncontrolled. ID ARIA memakai useId, hanya tab terpilih masuk urutan Tab; panah dan Home/End memilih sekaligus memindahkan fokus, disabled dilewati. Panel nonaktif hidden dan tetap mounted agar nilai field bertahan. Marker dekoratif, focus ring eksplisit, fallback reduced motion dan forced colors tersedia. Kontrak di DESIGN.md serta dokumentasi komponen diselaraskan.

Lint dan build produksi termasuk TypeScript lulus. Playwright pada server development port 3100 menguji tema terang/gelap pada lebar 1440/360 px: klik, ArrowRight dengan wrap melewati disabled, Home/End, fokus mengikuti pilihan, satu panel terlihat, relasi aria-labelledby, preservasi isian, posisi/lebar marker final terhadap tombol aktif (selisih kurang dari 1 px), tanpa overflow halaman dan tanpa pageerror. Emulasi reduced motion menghasilkan transition-duration 0s dan animation-name none. Screenshot terang desktop dan gelap ponsel dibuka untuk review. Bukti: screenshots/admin-components-phase2/tabs/results.json dan screenshot tiap kombinasi. Controlled mode, perubahan daftar dinamis, RTL, teks 200%, screen reader nyata, browser lain dan benchmark fps belum diuji runtime.

Delivery Gate lingkup Tabs: Hard Gate PASS untuk build dan matrix di atas; Purpose Gate PASS (mengelompokkan panel pengaturan lokal sesuai referensi); Liveliness PASS (arah existing dan gerak bermakna tanpa loop); Craftsmanship PASS pada render/semantik/fokus/geometry yang diperiksa. Pengujian ini memakai development; hasil next start tidak diuji ulang untuk Tabs.

### Soft gelap dengan alpha proporsional, 28 Oktober 2026

Soft gelap kini memakai shade500 dengan alpha, bukan shade950 opaque: blue/green/red 14%, yellow 12% untuk menyeimbangkan luminansi. Token rgb(... / alpha) setara konsep slash opacity background Tailwind. Teks shade400 dan ikon tetap opacity penuh; tidak ada opacity pada seluruh komponen. Token bersama berlaku pada Alert, Badge/StatusBadge soft dan Button soft. Warna solid/soft terang tidak berubah. Kontrak terbaru dicatat pada DESIGN.md dan dokumentasi komponen.

Build produksi/TypeScript lulus. Browser development port 3100 memeriksa 32 instance soft semantik pada lebar 1440/360 px dalam tema gelap: alpha background 0.12/0.14 dan opacity elemen 1 sesuai kontrak. Kontras teks dihitung setelah background dikompositkan terhadap rantai surface induk menggunakan canvas browser, kemudian memakai checker proyek; minimum 5.40:1. Screenshot Alert desktop dibuka, surface lebih tenang dan latar induk tetap berpengaruh. Bukti: screenshots/admin-components-phase2/soft-alpha/measurements.json dan screenshot terkait. Lint mandiri, interaksi lengkap, browser lain dan mode OS tidak diulang untuk perubahan empat token CSS ini.

Delivery Gate lingkup soft gelap: build/render/kontras PASS; Purpose PASS (warna semi transparan sesuai permintaan, tinta tetap terbaca); Liveliness PASS (tanpa motion baru); Craftsmanship PASS pada sampel komposit dan render yang diperiksa. Batas kontras solid putih success/warning pada catatan sebelumnya tetap berlaku, tidak termasuk PASS soft ini.

### Content putih dan soft gelap, 28 Oktober 2026

Koreksi eksplisit pengguna: solid success green600 dan warning yellow500 memakai teks putih pada kedua tema. Soft tema terang tetap 50/700; tema gelap memakai background950 dan tinta400 untuk blue/green/yellow/red. Token content bersama juga memengaruhi Badge solid/kontrol terpilih, dan soft mengalir ke Alert/Badge/StatusBadge. Hover solid kini menggelapkan fill 10%, tanpa menggunakan tinta400 yang terlalu terang sebagai fill. Kontrak komponen dan DESIGN.md mencatat keputusan terbaru ini.

Build produksi/TypeScript lulus. Playwright pada development 3100 memeriksa empat kombinasi tema dan viewport 1440/360 px: solid rest/hover, soft, klik soft/outline, serta tidak ada overflow. Screenshot Button terang dan Alert gelap dibuka, sesuai pilihan visual pengguna. Bukti terbaru berada di screenshots/admin-components-phase2/shades/. Checker kontras menyatakan putih/success600 3.30:1 dan putih/warning500 1.92:1; keduanya FAIL AA teks normal, dan warning juga FAIL untuk teks besar. Ini batas aksesibilitas yang disampaikan kepada pengguna dan dicatat, bukan PASS kontras. Hasil PASS minimum 4.52:1 pada revisi sebelumnya tidak berlaku pada pilihan putih terbaru ini.

Delivery Gate: build/render dan kesesuaian visual lulus; gerbang kontras teks solid success/warning tidak lulus sesuai angka di atas. Pilihan warna diterapkan atas arahan eksplisit pengguna. Lint mandiri dan regresi interaksi menyeluruh tidak diulang untuk perubahan token/CSS ini.

### Skala warna 600 / soft 50–700 dan Button appearance, 28 Oktober 2026

Permintaan pengguna diterapkan pada token warna produksi bersama: blue/green/yellow/red 600 untuk solid, 50 untuk background soft, 700 untuk tinta soft pada kedua tema. Button/Badge solid, Alert/Badge soft, StatusBadge dan warna semantik kontrol mengikuti token ini. Pasangan teks solid: putih untuk blue/red, hijau sangat gelap untuk green dan slate gelap untuk yellow agar memenuhi kontras. Hover/active solid memakai shade 700 dengan putih. Toast tetap kartu netral terpisah dan ikon status 600. Teks error field yang berdiri di atas surface dark memakai red300 agar tidak kehilangan kontras; ini bukan teks pada surface soft. Tidak ada perubahan prototype.

Button mendapat appearance solid/soft/outline. Secondary default memakai panel abu-abu/foreground tanpa border sesuai gambar 4; outline surface/foreground dengan border line 1 px mengikuti gambar 3, termasuk contoh ikon panah. Galeri starter menyediakan outline dan empat soft tone. Disabled/loading tetap mempunyai aturan terpisah dan focus ring existing tersedia.

Lint serta build/TypeScript lulus. Playwright pada server development port 3100 memeriksa tema terang/gelap, lebar 1440/360 px: empat solid rest/hover, empat soft dan klik tiap soft/outline; tidak ada overflow. Kontras 48 sampel tombol dihitung dari computed color browser, minimum 4.52:1. Screenshot desktop Button terang dan Alert gelap dibuka untuk review hierarki/warna; bukti matrix berada di screenshots/admin-components-phase2/shades/measurements.json dan screenshot terkait. Regresi interaksi lengkap field/overlay/Toast, forced colors, screen reader dan browser lain tidak diulang. Source perbaikan terakhir mempertahankan keterbacaan teks error standalone dan ikon Toast pada dark surface.

Delivery Gate: Hard Gate PASS dalam lingkup tersebut; Purpose Gate PASS (skala warna bersama dan appearance sesuai referensi); Liveliness PASS (arah dan motion existing); Craftsmanship PASS (palette/kontras terukur serta review render). Kontrak warna terbaru ditambahkan ke DESIGN.md dan kontrak UI; mapping historis sebelumnya digantikan oleh revisi ini.

### Pemulihan CSS Toast server development, 28 Oktober 2026

Pengguna melaporkan Toast tampil tanpa kartu dan mengalir vertikal pada port 3100. Reproduksi browser baru mengonfirmasi CSS development tidak memuat aturan tt-toast-surface: background transparent, radius 0 dan posisi item static, meskipun globals.css sudah mengimpor toast.css. Restart biasa tidak memperbaikinya. Server dihentikan, direktori cache generated web/.next/dev diverifikasi sebagai path di workspace lalu dibersihkan, dan next dev dinyalakan kembali. Setelah kompilasi ulang, stylesheet yang sama memuat aturan Toast; computed surface putih, radius 8 px, lebar 352 px dan posisi item absolute. Tidak ada perubahan desain atau source Toast pada pemulihan ini. Penyebab detail invalidasi cache Turbopack tidak dapat dipastikan hanya dari bukti tersebut.

Pengujian sebelumnya pada next start tidak mencakup masalah cache development yang dilihat pengguna. Pemulihan ini diperiksa langsung melalui port 3100; bukti browser disimpan di screenshots/admin-components-phase2/toast-dev-recovery/. Tab lama dapat memerlukan reload penuh untuk melepaskan stylesheet yang sudah dimuat. Tidak ada build ulang karena source aplikasi tidak diubah.

### Koreksi Toast agar sesuai referensi, 28 Oktober 2026

Toast kini memiliki markup dan styling tersendiri, tanpa membungkus Alert. Kartu memakai surface netral, border line tipis, radius 8 px, shadow halus, lebar 352 px responsif. Ikon solid 18 px berada di samping judul foreground 13 px; deskripsi muted 12 px sejajar teks judul. Tidak ada aksen kiri/ripple/background status Alert. Tombol tutup berada di dalam kartu; kontrol jumlah notifikasi dibuat ringkas. Selector placement/width dibuat lebih spesifik agar ukuran tidak mengikuti lebar kontrol expand.

ResizeObserver mengukur tinggi kartu dan konten custom. Kartu ditumpuk menggunakan offset 8/16 px dan scale 0.97/0.94, lalu bergerak ke offset tinggi aktual dengan gap 12 px saat hover/fokus/expand. Transform dan tinggi region bertransisi 220 ms; masuk/keluar surface 200 ms. Dismiss/dismissAll kini meminta exit sebelum elemen dihapus. Stack kosong dilepas dari React agar state hover/fokus lama tidak menjeda Toast baru. Timer mempertahankan sisa waktu dan menjeda saat hover/fokus/tab tersembunyi/pesan terhalang.

Validasi: lint dan build (TypeScript) lulus. Playwright pada next start menguji dua tema, viewport 1440/360 px dan enam posisi. Pemeriksaan mencakup kartu di dalam viewport, tidak ada markup Alert, lebar kartu 300–352 px pada ukuran uji, offset expanded lebih besar daripada collapsed, item belakang inert, ekspansi melalui hover/fokus, aksi custom, close, dismissAll, auto-dismiss yang ditunda selama hover 5.2 detik, reduced motion, serta keyboard close dengan focus return. Screenshot dua tema tersedia di screenshots/admin-components-phase2/toast-reference/. Ini tidak membuktikan benchmark fps, antrean sangat besar, browser lain atau screen reader nyata.

Delivery Gate revisi: Hard Gate PASS untuk pemeriksaan tersebut; Purpose Gate PASS (Toast ringkas sesuai referensi, Alert tetap komponen terpisah); Liveliness PASS (motion hanya feedback, reduced motion tersedia); Craftsmanship PASS dalam matrix posisi/viewport/tema yang diperiksa. Kontrak UI dan DESIGN.md diselaraskan. Bukti revisi ini menggantikan tampilan Toast berbasis Alert pada catatan implementasi awal di bawah.

### Toast React berdasarkan referensi pengguna, 28 Oktober 2026

Referensi Alpine diterjemahkan menjadi ToastProvider/useToast React pada folder UI bersama, dipasang sekali pada root layout. Mendukung lima tone, enam posisi independen, title/description, ReactNode custom, aksi, durasi/persisten, dismiss/dismissAll, stacked/expanded. Tidak ada Alpine, listener event global toast, window.toast, HTML mentah atau dependency tambahan. Surface netral/ikon warna mengikuti referensi dan token TonzToon; komponen memakai Alert/Button bersama serta container/placement daisyUI. Timer dijeda saat hover/fokus, pesan terhalang tumpukan, atau tab tersembunyi. Pesan beraksi/custom default persisten. Close selalu terlihat, tanpa focus steal saat muncul; penutupan dari kontrol Toast mengembalikan fokus ke pemicu yang masih tersedia.

Lint dan build produksi (termasuk TypeScript) lulus. Playwright lokal pada hasil next start port sementara 3101 menguji dua tema, viewport 1440/360 px dan enam posisi: 24 kombinasi lulus. Pengujian juga mencakup close, aksi custom, dismissAll, pembentangan saat hover, timer tetap hidup setelah hover 5.2 detik lalu hilang setelah pointer keluar, reduced motion serta Enter untuk menutup dengan fokus kembali ke pemicu. Tidak ada pageerror. Konflik translasi posisi tengah pada mobile ditemukan dan diperbaiki; matrix dijalankan ulang setelah build final. Panel dev Next sempat menutupi tombol Toast bawah kiri, sehingga pemeriksaan dipindahkan ke hasil produksi tanpa memodifikasi panel dev.

Delivery Gate: Hard Gate PASS untuk build/interaksi yang disebutkan; Purpose Gate PASS (feedback sementara pendamping hasil inline); Liveliness PASS (arah existing, motion feedback 200 ms dengan reduce); Craftsmanship PASS dalam matrix posisi/tema/viewport yang diuji. Screenshot di screenshots/admin-components-phase2/toast/ memperlihatkan tumpukan expanded dan galeri lokal. Announcements status/alert dan inert diperiksa pada source; screen reader nyata, perubahan visibility tab, provider layout expanded permanen, ReactNode kompleks, antrean besar, browser lain dan zoom teks belum diuji runtime. Tidak ada klaim integrasi backend atau penerimaan aksesibilitas menyeluruh.

### Alert dengan aksen kiri dan shadow tipis, 28 Oktober 2026

Semua varian Alert memakai border 0 pada atas/bawah/akhir dan aksen awal 4 px. Shadow token tema memakai 0 2px 6px rgba(15,23,42,0.06) pada terang dan rgba(0,0,0,0.18) pada gelap. Radius tetap 12 px. Ini pemisahan surface soft sesuai permintaan pengguna; fallback forced colors tetap memakai border sistem.

Playwright lokal pada server development memeriksa dua tema dan viewport 1440/360 px: border Alert terukur 0/0/0/4 px, shadow aktif, tanpa overflow halaman. Screenshot desktop kedua tema dibuka; surface tetap tenang, aksen kiri utuh dan shadow tidak mengaburkan isi. Bukti berada di screenshots/admin-components-phase2/alert-left-shadow/ termasuk measurements.json. Build produksi dan TypeScript lulus. Lint, regresi interaksi penuh, browser lain dan mode OS tidak diulang untuk koreksi CSS ini.

Delivery Gate revisi: Hard Gate PASS (build dan empat kombinasi render); Purpose Gate PASS (aksen kiri menunjukkan status, shadow memisahkan surface sesuai permintaan); Liveliness PASS (arah existing, tanpa motion baru); Craftsmanship PASS (render desktop dua tema ditinjau dan geometri border terukur). DESIGN.md dan kontrak komponen diselaraskan.

### Warning bersama menjadi amber, 28 Oktober 2026

Warna warning produksi direvisi pada token bersama, bukan override Button. Fill solid memakai #f5b932 (terang) / #f5c451 (gelap), dengan content #172b46. Tinta untuk Alert, Badge soft/outline, StatusBadge, ikon serta border field memakai #805b00 / #f5c451, di atas surface soft #fff8e1 / #302918. Pemisahan tinta/fill menghindari latar solid cokelat sekaligus mempertahankan keterbacaan teks dan batas kontrol. Field warning mengecualikan disabled, readonly dan invalid. DESIGN.md dan kontrak komponen diselaraskan; prototype belum mengikuti revisi token produksi ini.

Build produksi dan TypeScript lulus. Playwright lokal memeriksa hasil server development pada tema terang/gelap dan lebar 1440/360 px: fill/content Button sesuai token baru, Alert/Badge/field warning memakai warna bersama, dan tidak ada overflow halaman. Tiga screenshot desktop dibuka untuk meninjau Button/Badge dan Alert dua tema. Kontras melalui checker proyek: content terhadap solid terang 8.07:1, tinta terhadap soft terang 5.79:1, tinta terhadap soft gelap 8.86:1. Screenshot dan pengukuran berada di screenshots/admin-components-phase2/warning-global/. Pemeriksaan runtime ini memakai server development; bukan klaim pengujian hasil next start, screen reader, semua interaksi atau browser lain.

Delivery Gate lingkup revisi warna: Hard Gate PASS (build dan empat kombinasi runtime); Purpose Gate PASS (amber membedakan caution dari error, tinta terpisah menjaga keterbacaan); Liveliness PASS (arah existing tanpa motion baru); Craftsmanship PASS (token bersama konsisten pada komponen yang diperiksa, kontras teks lulus). Lint dan typecheck mandiri tidak diulang untuk koreksi token/CSS ini; TypeScript dijalankan oleh build.

### Ikon Alert dengan ripple statis, 27 Oktober 2026

Koreksi referensi pengguna diterapkan pada ikon semua tone Alert: outline solid tipis diganti cincin soft luar 4 px (tinta tone 10% dicampur surface tone), dengan lingkaran dalam lebih tegas (tinta tone 20%). Glyph memakai tinta tone solid. Diameter keseluruhan tetap 32 px dan glyph 18 px. Ini efek lapisan warna yang diam, tanpa pulse, animasi atau transisi ikon. Border/radius/isi Alert, role dan API komponen tidak berubah. DESIGN.md dan kontrak komponen diselaraskan.

Build produksi lulus. Playwright lokal pada Chrome headless menguji enam kombinasi: dua tema pada viewport 1440/360 px, ditambah font root 200% pada 360 px. Seluruh lima tone pada tiap kombinasi mempunyai lingkaran luar/dalam berbeda, ring 4 px, nol animasi aktif pada subtree ikon dan transition-duration 0s. Isi tetap membungkus tanpa overflow; pengujian validasi error/reset/sukses dan fokus field juga lulus tanpa pageerror. Minimum kontras glyph terhadap lingkaran dalam kini 3.94:1; teks 11.93:1 dan border aksen Alert 5.56:1. Kontras dihitung memakai fungsi contrast-check.py dari warna computed browser.

Delivery Gate koreksi ikon: PASS untuk lingkup tersebut. Hard Gate: build dan enam kombinasi runtime lulus. Purpose Gate: dua lapisan soft mengikuti referensi ripple statis dan warna glyph tetap solid. Liveliness: arah 2/2/1 dipertahankan, tanpa motion tambahan. Craftsmanship: empat screenshot desktop/ponsel dua tema dibuka; lapisan konsentris dan glyph tidak terpotong atau mengubah alignment pesan. Hasil font 200% diperiksa melalui pengukuran layout. Lint/typecheck mandiri tidak diulang untuk perubahan dua deklarasi CSS ini; build produksi menyelesaikan TypeScript. Browser lain, screen reader dan pengaturan OS tidak diuji ulang.

Bukti: [terang desktop](screenshots/admin-components-phase2/alerts-static-ripple/after-light-1440x900.png), [gelap desktop](screenshots/admin-components-phase2/alerts-static-ripple/after-dark-1440x900.png), [terang ponsel](screenshots/admin-components-phase2/alerts-static-ripple/after-light-360x900.png), [gelap ponsel](screenshots/admin-components-phase2/alerts-static-ripple/after-dark-360x900.png), [pengukuran render dan sifat statis](screenshots/admin-components-phase2/alerts-static-ripple/after-measurements.json), [kontras](screenshots/admin-components-phase2/alerts-static-ripple/contrast.json).

### Alert dengan ikon berbingkai, 27 Oktober 2026

Sesuai referensi pengguna, seluruh tone Alert (netral, info, sukses, peringatan, error) kini memakai surface soft tema, aksen border awal 4 px dan sudut 12 px. Bingkai ikon bulat 32 px menampung glyph 18 px, dengan gap 12 px dan padding 16 px. Border tipis sisi lainnya mempertahankan batas surface tanpa menyamai bobot aksen status. Ikon pesan/i/centang/tanda seru/silang membedakan makna; judul serta isi memakai foreground tema. Ikon bersifat dekoratif aria-hidden dan tidak menambah fokus atau announcement. Kontrak role note/status/alert serta announce tidak berubah.

Implementasi berada pada Alert bersama, memakai kelas alert/alert-soft dan modifier tone daisyUI, token radius/ukuran ikon khusus serta override tt-alert. Props dan API Alert tetap sama; pesan validasi dan feedback tanpa judul otomatis mendapat pola ini. Badge, field dan source prototype tidak diubah. DESIGN.md dan kontrak komponen diselaraskan. Dokumentasi alert daisyUI diperiksa melalui Context7 sebelum perubahan struktur/override.

Lint, typecheck dan build produksi exit 0. Playwright lokal pada Chrome headless 155.0.8059.85 memeriksa 14 kombinasi render: dua tema pada lebar 360, 375, 768, 1024, 1440 px, landscape 900x360, serta lebar 360 px dengan font root 200%. Semua 70 instance tone pada matrix tersebut memiliki ikon, role note, isi yang membungkus tanpa overflow dan alignment yang sesuai. Setiap kombinasi juga memeriksa validasi error (role alert, fokus ke field), reset error, dan pesan sukses (role status). Tidak ada pageerror. Pembesaran ini adalah emulasi font root melalui CSS, bukan pengujian zoom browser atau pengaturan aksesibilitas OS.

Review screenshot awal menemukan teks terjepit pada font 200%. Container query kini memindahkan isi/action ke bawah ikon saat ruang isi kurang dari 11rem. Aturan grid-auto-flow row menetralkan alur kolom bawaan daisyUI yang sempat membuat kolom implisit dan overflow. Build dan seluruh matrix dijalankan ulang setelah perbaikan hingga lulus. Kata panjang tetap dapat membungkus pada viewport sangat sempit; tidak ada pesan yang dipotong atau disembunyikan.

Kontras dihitung dari warna computed browser dengan fungsi pada contrast-check.py proyek: minimum teks 11.93:1, ikon terhadap isi bingkai 5.05:1, dan aksen border terhadap surface Alert 5.56:1 pada sepuluh pasangan tema/tone. Border tipis sekunder bukan satu-satunya penanda status; aksen, glyph dan teks tetap tersedia.

Delivery Gate revisi Alert: PASS untuk lingkup tersebut. Hard Gate: build produksi, matrix render serta validasi lokal lulus. Purpose Gate: bingkai ikon dan aksen border menyampaikan jenis pesan sesuai referensi pengguna, bukan dekorasi tanpa makna; radius 12 px proporsional terhadap padding/tinggi isi. Liveliness: palette, font dan arah 2/2/1 existing dipertahankan tanpa motion baru. Craftsmanship: 12 render normal ditinjau melalui contact sheet, ditambah dua render font 200% secara langsung; tidak ada glyph terpotong, overlap atau overflow. Pengujian screen reader, forced colors, browser lain, action slot opsional dan regresi interaksi modul lainnya tidak diulang pada revisi ini.

Bukti: [sebelum terang](screenshots/admin-components-phase2/alerts/before-light-1440x900.png), [sesudah terang](screenshots/admin-components-phase2/alerts/after-light-1440x900.png), [sesudah gelap](screenshots/admin-components-phase2/alerts/after-dark-1440x900.png), [matrix normal](screenshots/admin-components-phase2/alerts/after-contact.png), [font 200% terang](screenshots/admin-components-phase2/alerts/after-light-360x900-text200.png), [font 200% gelap](screenshots/admin-components-phase2/alerts/after-dark-360x900-text200.png), [pengukuran render](screenshots/admin-components-phase2/alerts/after-measurements.json) dan [kontras](screenshots/admin-components-phase2/alerts/contrast.json).

### Klik di luar Dialog dan Drawer, 27 Oktober 2026

Primitive Dialog bersama kini meminta penutupan melalui onOpenChange(false) saat klik/tap pointer utama dimulai dan berakhir di luar panel. Drawer awal/akhir mewarisi perilaku yang sama. Klik isi panel, pengeditan field, klik kanan dan drag dari dalam ke luar atau sebaliknya tidak menutup overlay. Pointer yang dibatalkan mereset kandidat klik. Handler pemakai tetap dikomposisikan; preventDefault pada pointerdown/click dapat membatalkan permintaan. Penutupan tetap terkontrol sehingga parent dapat menahan penutupan untuk konfirmasi draft. DESIGN.md dan kontrak komponen diselaraskan; style dan durasi motion tidak berubah.

Lint, typecheck dan build produksi lulus. Playwright lokal pada Chrome headless menguji 18 kombinasi: 12 skenario mouse (dua tema, viewport 1440/360 px, Dialog/Drawer awal/Drawer akhir) dan enam skenario emulasi tap sentuh (dua tema, 360 px, ketiga varian). Seluruh skenario lulus tanpa pageerror. Tiap skenario memeriksa klik internal, drag kedua arah, klik kanan, pembatalan melalui preventDefault, penutupan backdrop, animasi keluar, fokus kembali ke pemicu, buka ulang dan Escape. Field Dialog juga diedit tanpa memicu penutupan. Tap memakai touchscreen emulasi browser, bukan perangkat fisik.

Animasi keluar diukur melalui timeline CSS native yang dijeda pada separuh durasi: elemen tetap display grid/overlay auto dengan opacity panel-container dan backdrop di antara 0 dan 1. Setelah animasi selesai display none dan fokus berada pada pemicu. Pengukuran ini memverifikasi transisi penutupan backdrop tanpa mengklaim benchmark fps. Pengujian pertama menempatkan titik klik Drawer pada scrollbar viewport; titik uji diperbaiki menggunakan batas elemen dialog agar benar-benar mengenai backdrop, lalu seluruh matrix dijalankan ulang hingga lulus.

Delivery Gate revisi interaksi: PASS dalam lingkup tersebut. Hard Gate: produksi dan 18 kombinasi runtime lulus. Purpose Gate: pengguna dapat menutup overlay dari backdrop tanpa salah menutup saat mengedit/menyeleksi isi. Liveliness: arah 2/2/1 dan tampilan existing dipertahankan. Craftsmanship: tiga screenshot setelah penutupan dibuka; tidak ada overlay tertinggal dan focus ring pemicu terlihat. Regresi modul lain, perangkat sentuh fisik, browser lain, serta screen reader tidak diuji ulang.

Bukti keadaan tertutup: [Dialog](screenshots/admin-components-phase2/outside-click/light-1440-dialog-center-mouse-closed.png), [Drawer awal](screenshots/admin-components-phase2/outside-click/light-1440-drawer-start-mouse-closed.png), [Drawer akhir](screenshots/admin-components-phase2/outside-click/light-1440-drawer-end-mouse-closed.png). [Pengukuran 18 skenario](screenshots/admin-components-phase2/outside-click/measurements.json) mencatat tema, viewport, jenis pointer dan transisi keluar.

### Motion buka/tutup Dialog dan Drawer, 27 Oktober 2026

Dialog kini memakai fade dan scale 0.96 ke 1 selama 200 ms. Drawer memakai fade dan slide dari sisi awal/akhir selama 280 ms. Backdrop mengikuti durasi dan easing panel. Token bersama mengatur durasi; override menetralkan translate, scale dan delay bawaan daisyUI agar tidak bertabrakan. Transisi display/overlay allow-discrete mempertahankan render native hingga animasi keluar selesai, sedangkan starting-style menyediakan awal animasi masuk. Pola ini mengikuti [dokumentasi animasi dialog native](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog#animating_dialogs). Tidak ditambahkan timer JavaScript; callback penutupan dan pengembalian fokus tetap memakai perilaku native.

Verifikasi memakai Playwright lokal sesuai izin eksplisit pengguna setelah tool browser sebelumnya tidak tersedia. Playwright dipasang sementara di luar repository tanpa perubahan dependency web. Hasil produksi diuji pada Chrome headless 155.0.8059.85: 12 kombinasi normal (dua tema, viewport 1440/360 px, Dialog/Drawer awal/Drawer akhir) dan 12 kombinasi emulasi reduced motion. Semua 24 skenario lulus tanpa pageerror. Lint, typecheck dan build juga exit 0.

Pada setiap kombinasi normal, pengujian memeriksa masuk, keadaan terbuka, keluar dan keadaan tersembunyi. Timeline transisi native dijeda pada separuh durasi untuk mengukur opacity, transform dan backdrop secara deterministik; screenshot titik tengah merupakan sampel timeline tersebut. Pengujian buka ulang saat penutupan masih berlangsung dijalankan tanpa jeda timeline dan berhasil. Tab/Shift+Tab tetap mengurung fokus, Escape/tombol Tutup menutup overlay, dan fokus kembali ke pemicu. Saat keluar, open sudah false tetapi display masih grid dan overlay auto; setelah selesai display menjadi none, overlay none dan tidak ada rect yang menangkap interaksi. Reduced motion meniadakan transisi panel, root dan backdrop.

Delivery Gate revisi motion: PASS untuk lingkup yang diuji. Hard Gate: produksi dan 24 skenario runtime lulus. Purpose Gate: animasi memperjelas masuk/keluar konteks modal, dengan durasi sesuai DESIGN.md. Liveliness: arah 2/2/1 dan motion terbatas interaksi dipertahankan. Craftsmanship: sembilan frame berikut dibuka dan diperiksa; arah slide kedua sisi, skala dialog, fade backdrop, fokus dan pemulihan buka ulang konsisten. Pengujian ini tidak mengukur fps atau membuktikan perilaku browser lain. Browser tanpa dukungan transisi discrete mempertahankan fungsi native, tetapi fallback tersebut belum diuji pada runtime.

| Komponen | Masuk, titik tengah | Terbuka | Keluar, titik tengah |
| --- | --- | --- | --- |
| Dialog | [Masuk](screenshots/admin-components-phase2/motion/light-1440-dialog-enter.png) | [Terbuka](screenshots/admin-components-phase2/motion/light-1440-dialog-open.png) | [Keluar](screenshots/admin-components-phase2/motion/light-1440-dialog-exit.png) |
| Drawer awal | [Masuk](screenshots/admin-components-phase2/motion/light-1440-drawer-start-enter.png) | [Terbuka](screenshots/admin-components-phase2/motion/light-1440-drawer-start-open.png) | [Keluar](screenshots/admin-components-phase2/motion/light-1440-drawer-start-exit.png) |
| Drawer akhir | [Masuk](screenshots/admin-components-phase2/motion/light-1440-drawer-end-enter.png) | [Terbuka](screenshots/admin-components-phase2/motion/light-1440-drawer-end-open.png) | [Keluar](screenshots/admin-components-phase2/motion/light-1440-drawer-end-exit.png) |

[Pengukuran seluruh skenario](screenshots/admin-components-phase2/motion/measurements.json) mencatat keadaan aktual dari browser untuk kedua tema dan ukuran viewport.

### Backdrop gelap dan blur tipis, 27 Oktober 2026

Dialog dan Drawer memakai backdrop native dengan warna overlay tema: rgba(15,23,42,0.60) pada terang dan rgba(6,9,15,0.72) pada gelap. Token bersama tt-overlay-blur mengatur blur 4 px. Elemen dialog transparan dan backdrop display block menggantikan scrim bawaan daisyUI, sehingga warna tidak bertumpuk dan panel tetap solid/tajam.

Temuan render awal: daisyUI menyembunyikan ::backdrop dan menggambar scrim pada elemen modal. Warna/filter computed pada pseudo-element saja belum membuktikan blur terlihat. Setelah override display/background diterapkan, screenshot final memperlihatkan halaman belakang gelap dan blur, sedangkan isi overlay tetap tajam. Dokumentasi modal native diperiksa melalui Context7 dan dicocokkan dengan source CSS daisyUI terpasang. Source vendor tidak diubah.

Delivery Gate revisi ini: PASS. Hard Gate: build produksi exit 0; delapan kombinasi Dialog/Drawer, tema terang/gelap dan viewport 1440/360 px diuji. Purpose Gate: scrim dan blur memisahkan konteks modal sesuai permintaan pengguna dan DESIGN.md. Liveliness: arah 2/2/1, palette tema dan surface panel dipertahankan. Craftsmanship: delapan screenshot final dibuka; backdrop terukur display block dan blur(4px), background dialog transparan, panel opaque dengan filter none. Tab/Shift+Tab tetap di dalam modal, Escape menutupnya, dan fokus kembali ke pemicu pada seluruh kombinasi. Gangguan koneksi pemeriksaan browser berhasil dipulihkan sebelum verifikasi final diselesaikan.

Bukti desktop: [Dialog terang](screenshots/admin-components-phase2/backdrop-dialog-light-1440.jpg), [Drawer terang](screenshots/admin-components-phase2/backdrop-drawer-light-1440.jpg), [Dialog gelap](screenshots/admin-components-phase2/backdrop-dialog-dark-1440.jpg), [Drawer gelap](screenshots/admin-components-phase2/backdrop-drawer-dark-1440.jpg). Bukti ponsel: [Dialog terang](screenshots/admin-components-phase2/backdrop-dialog-light-360.jpg), [Drawer terang](screenshots/admin-components-phase2/backdrop-drawer-light-360.jpg), [Dialog gelap](screenshots/admin-components-phase2/backdrop-dialog-dark-360.jpg), [Drawer gelap](screenshots/admin-components-phase2/backdrop-drawer-dark-360.jpg). [Pengukuran aktual](screenshots/admin-components-phase2/backdrop-measurements.json) mencatat tema/viewport dari DOM, bukan label skenario saja.

Fallback tanpa dukungan backdrop-filter mempertahankan lapisan gelap melalui CSS; browser yang tidak mendukung filter belum diuji pada runtime. Pengujian lintas browser dan benchmark rendering blur tetap di luar lingkup revisi ini.

### Ring fokus mengikuti error, 27 Oktober 2026

Field aktif dengan tone error atau aria-invalid=true kini memakai warna danger dari tema aktif pada ring fokus, termasuk Input, Select saat picker terbuka, Textarea dan Checkbox. Ukuran/offset tetap 3 px. Field normal kembali memakai aksen; disabled tidak diberi ring error. Kontrak UI dan DESIGN.md diperbarui sesuai permintaan pengguna.

Delivery Gate revisi ini: PASS. Hard Gate: build produksi exit 0; empat jenis field difokuskan melalui klik/Tab pada dua tema, serta Select terbuka diuji pada viewport 1440/360 px. Purpose Gate: ring memperjelas status error yang sudah ditunjukkan border/pesan/aria-invalid. Liveliness: arah existing dan warna semantik tema dipertahankan. Craftsmanship: enam screenshot dibuka; ring terukur #b91c1c pada terang dan #f08a8a pada gelap, dengan kontras terhadap surface 6.47:1 dan 7.16:1. Tone error tanpa invalid, pemulihan ke ring biru, serta kombinasi disabled-invalid diuji; kontrol disabled tidak terfokus dan outline-style tetap none. Regresi interaksi penuh dan browser lain tidak diulang pada perubahan warna ring ini.

Bukti: [Input terang](screenshots/admin-components-phase2/error-focus-input-light.jpg), [Select terang](screenshots/admin-components-phase2/error-focus-select-light.jpg), [Input gelap](screenshots/admin-components-phase2/error-focus-input-dark.jpg), [Select gelap](screenshots/admin-components-phase2/error-focus-select-dark.jpg), [ponsel terang](screenshots/admin-components-phase2/error-focus-mobile-light.jpg), [ponsel gelap](screenshots/admin-components-phase2/error-focus-mobile-dark.jpg), serta [pengukuran](screenshots/admin-components-phase2/error-focus-measurements.json).

### Radius Input/Select 18 px, 27 Oktober 2026

Pilihan pengguna diterapkan melalui token field 1.125rem (18 px); Textarea memakai token tersendiri 1rem (16 px). Readonly, disabled, invalid dan loading mengikuti radius komponen yang sama. DESIGN.md serta kontrak UI diperbarui. Panel luar/isi tetap 24/20 px, Card mandiri 16 px, dan Button 8 px.

Delivery Gate revisi ini: PASS. Hard Gate: build produksi exit 0; hasil render diperiksa pada dua tema dan viewport 1440/360 px. Purpose Gate: field satu baris lebih lembut, sedangkan Textarea multiline mempertahankan proporsi 16 px. Liveliness: arah 2/2/1 dan motif surface berlapis dipertahankan. Craftsmanship: seluruh screenshot dibuka; 12 kombinasi tema/viewport/size sm-md-lg terukur Input/Select 18 px dan Textarea 16 px. Tinggi kontrol tetap 44/44/48 px, Textarea minimum 128 px. State invalid-loading dan ring fokus Select terbuka 3 px/offset 3 px diverifikasi pada kedua tema. Pengujian lengkap interaksi dan kontras tidak diulang untuk perubahan radius ini.

Bukti: [form final](screenshots/admin-components-phase2/field-radius-final.jpg), [terang desktop](screenshots/admin-components-phase2/field-radius-light-1440.jpg), [gelap desktop](screenshots/admin-components-phase2/field-radius-dark-1440.jpg), [terang ponsel](screenshots/admin-components-phase2/field-radius-light-360.jpg), [gelap ponsel](screenshots/admin-components-phase2/field-radius-dark-360.jpg), serta [pengukuran](screenshots/admin-components-phase2/field-radius-measurements.json).

### Revisi ring fokus Select, 27 Oktober 2026

Saat picker native terbuka, fokus dapat berada pada option sehingga Select tidak cocok dengan focus-visible. Sebelum perbaikan, browser menunjukkan open=true/focus=false dan outline vendor 2 px dengan offset 2 px berwarna foreground. Aturan tt-control.select kini memakai ring bersama pada focus/focus-within/open, serta mengecualikan disabled.

Delivery Gate revisi ini: PASS. Hard Gate: build produksi exit 0; Tab, Space, Escape, klik dan pemilihan option diuji. Purpose Gate: ring aksen 3 px/offset 3 px kini sama persis dengan Input untuk mouse, keyboard dan picker terbuka. Liveliness: warna aksen dan arah existing dipertahankan. Craftsmanship: empat screenshot terang/gelap pada viewport 1440/360 px dibuka dan diperiksa; lima tone, invalid dan disabled diperiksa pada kedua tema. Border status tetap sesuai tone, terpisah dari ring fokus. Pemilihan Kosong menampilkan empty state tabel dan Reset tabel memulihkan data contoh. Pengujian lintas browser dan regresi modul lain tidak diulang untuk perubahan selector fokus ini.

Bukti: [terang desktop](screenshots/admin-components-phase2/select-focus-light-1440.jpg), [gelap desktop](screenshots/admin-components-phase2/select-focus-dark-1440.jpg), [terang ponsel](screenshots/admin-components-phase2/select-focus-light-360.jpg), [gelap ponsel](screenshots/admin-components-phase2/select-focus-dark-360.jpg), dan [pengukuran fokus/status](screenshots/admin-components-phase2/select-focus-measurements.json). Dokumentasi Select diperiksa melalui Context7 dan dicocokkan dengan CSS paket daisyUI terpasang; source vendor tidak diubah.

### Revisi radius surface berlapis, 27 Oktober 2026

Koreksi pengguna diterapkan pada seluruh Panel: radius luar 24 px, inset 4 px, dan radius surface isi diturunkan menjadi 20 px melalui token bersama. Card mandiri tetap 16 px. DESIGN.md dan kontrak komponen diselaraskan dengan koreksi ini.

Delivery Gate revisi ini: PASS. Hard Gate: build produksi exit 0 dan empat kombinasi tema terang/gelap pada viewport 1440/360 px tanpa overflow horizontal. Purpose Gate: radius luar dikurangi inset menjaga ketebalan lapisan di sudut. Liveliness: susunan, warna dan arah 2/2/1 tetap. Craftsmanship: screenshot empat kombinasi dibuka; semua empat Panel terukur inset kiri/kanan/bawah 4 px, radius luar/dalam 24/20 px. Selisih pusat kurva bawah kiri terukur 0 px di kedua sumbu. Interaksi lengkap dan kontras sebelumnya tidak diulang karena perubahan terbatas pada geometri radius/inset.

Bukti: [desktop final](screenshots/admin-components-phase2/radius-final-desktop.jpg), [terang desktop](screenshots/admin-components-phase2/radius-light-1440.jpg), [gelap desktop](screenshots/admin-components-phase2/radius-dark-1440.jpg), [terang ponsel](screenshots/admin-components-phase2/radius-light-360.jpg), [gelap ponsel](screenshots/admin-components-phase2/radius-dark-360.jpg), serta [pengukuran geometri](screenshots/admin-components-phase2/radius-measurements.json).

### Revisi background starter, 27 Oktober 2026

Sesuai permintaan pengguna, latar viewport halaman starter sekarang memakai token canvas, melalui selector html:has(.tt-starter). Computed background terukur #ffffff pada tema terang dan #101215 pada tema gelap. Token palette dan surface komponen tetap mengikuti kontrak sebelumnya.

Delivery Gate perubahan ini: PASS. Hard Gate: build produksi exit 0; kedua tema pada viewport 1440 dan 360 px tidak memiliki overflow horizontal. Purpose Gate: canvas menandai area pemeriksaan sesuai permintaan pengguna. Liveliness: arah 2/2/1, Inter dan susunan panel existing dipertahankan. Craftsmanship: empat screenshot dibuka dan ditinjau; background cocok dengan token pada seluruh sampel. Pengujian interaksi lengkap sebelumnya tidak diulang untuk perubahan satu aturan background ini.

Bukti terbaru: [desktop terang](screenshots/admin-components-phase2/canvas-light-1440.jpg), [desktop gelap](screenshots/admin-components-phase2/canvas-dark-1440.jpg), [ponsel terang](screenshots/admin-components-phase2/canvas-light-360.jpg), [ponsel gelap](screenshots/admin-components-phase2/canvas-dark-360.jpg).

- Browser engine lain, screen reader, zoom browser/teks 200%, serta aktivasi reduced motion dan forced colors di OS belum diuji pada runtime. Emulasi reduced motion untuk Dialog/Drawer telah diuji pada revisi motion di atas; itu bukan bukti pengujian pergantian mode OS. Pemeriksaan lainnya tetap ada pada fase penerimaan.
- Penyimpanan tema yang ditolak, pergantian preferensi OS secara langsung, dan JavaScript nonaktif tidak diulang pada tahap komponen; tidak diklaim sebagai hasil browser baru.
- Belum ada shell/sidebar admin, migrasi 33 halaman, Data Flow/ERD, login, BFF, koneksi backend, mutation nyata, staging atau benchmark pada tahap ini.

Lanjutkan hanya setelah pengguna mengonfirmasi pekerjaan berikutnya. Usulan berikut: shell/sidebar/header responsif serta Overview sebagai pilot pemakaian komponen sebelum migrasi modul lainnya. Fase 3 tetap menunggu penyelesaian dan laporan frontend fase 2.
