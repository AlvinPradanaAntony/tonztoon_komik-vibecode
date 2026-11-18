# Laporan fase 1: starter TonzToon Admin

Tanggal: 26 Oktober 2026. Lokasi aplikasi: root `web/`, dikonfirmasi pengguna. Mode Anti-slop: during, pilihan sesi. Status: **fase 1 selesai; menunggu konfirmasi fase 2**.

## Hasil implementasi

- Scaffold CLI resmi Next.js 16.4.3 dengan App Router, TypeScript, ESLint, Tailwind Turbopack, `src/`, alias `@/*`, dan npm. Git initialization dinonaktifkan.
- Generator dijalankan pada `.codex-bootstrap/web` karena `web/` berisi prototype. Hasil dipindahkan setelah pemeriksaan benturan; staging dibersihkan dan tidak ada `web/.git`.
- daisyUI 5.7.50 terpasang sebagai dev dependency; tema custom light/dark mengikuti token `DESIGN.md`. CSS sumber dibagi menjadi entry, token, komponen bersama, serta tempat stylesheet Data Flow/ERD.
- React Flow 12.12.0 sudah terpasang untuk ERD fase 2 dan belum diimpor oleh halaman starter. Data Flow tetap direncanakan sebagai DOM/SVG custom.
- Inter 5.3.0 disajikan dari paket lokal. Tidak ada build-time fetch Google Fonts. Logo memakai salinan asset existing.
- Halaman `/` menyediakan contoh komponen berlabel: tema, input pencarian, select, panel/card, tabel, status, alert, dan dialog native. Kondisi normal/memuat/kosong/gagal bersifat lokal.
- Struktur route group, BFF, dan modul domain disiapkan dengan `.gitkeep`. Tidak ada route/fitur produksi yang disimulasikan sebagai endpoint berhasil.
- `.env.example`, `.nvmrc`, scripts lint/typecheck/build/start, serta README mencatat runtime dan batas server/client. Sesi/DB/BFF belum dihubungkan.
- Todo, PRD, dan satu catatan lokasi implementasi pada `DESIGN.md` diselaraskan ke root `web/`; tidak ada perubahan token/kontrak visual global.

## Verifikasi

| Pemeriksaan | Hasil |
| --- | --- |
| CLI resmi dan npm install | Lulus; generator melaporkan selesai, instalasi dependency melaporkan 0 vulnerabilities |
| Lint | Lulus, exit 0; diulang setelah instalasi bersih |
| Typecheck | Lulus; route types dihasilkan lalu TypeScript exit 0, diulang setelah instalasi bersih |
| Instalasi ulang lockfile | Lulus; npm ci --include=dev, 380 paket, audit 381 paket, exit 0 |
| Build produksi | Lulus; next build menghasilkan route statis / dan /_not-found, TypeScript tanpa error |
| Browser hasil build | Lulus pada starter; next start di 127.0.0.1:3100, dua tema, lima lebar viewport |
| Kontras sumber token | Lulus; lihat rincian berikut |
| Integritas prototype | Lulus; 103 berkas sama dengan baseline |

Hash gabungan path relatif dan byte seluruh berkas prototype selain `node_modules`: `9118b2e6daedc5bf487d088e8e3f678cdc67cd12015b332738f15cf5ab331e12`. Jumlah dan hash sebelum/sesudah scaffold cocok. Pemeriksaan ini membuktikan berkas prototype tidak berubah; bukan pengujian runtime prototype ulang.

Perhitungan warna menggunakan fungsi pada checker Anti-slop Human. Sebelas pasangan teks per tema mencakup foreground/muted/subtle pada page/panel/surface/inset, primary content, dan error. Tiga pasangan kontrol per tema mencakup border serta focus accent:

| Tema | Minimum kontras teks | Minimum kontras kontrol/fokus | Ambang |
| --- | --- | --- | --- |
| Light | 6.306:1 | 4.015:1 | Teks 4.5:1, kontrol 3:1 |
| Dark | 7.158:1 | 5.489:1 | Teks 4.5:1, kontrol 3:1 |

Pengukuran sumber dilengkapi pemeriksaan warna terkomputasi pada 27 elemen teks yang terlihat per tema: minimum light 6.629:1 dan dark 8.266:1, tanpa pasangan gagal pada elemen yang diukur. Placeholder turut diperiksa melalui pasangan token sumber. FontFaceSet berstatus loaded dengan tujuh face terdaftar dan pemeriksaan Inter Variable bernilai true. Console akhir tidak mencatat error/warning. Data mentah berada pada [qa.json](screenshots/admin-starter-phase1/qa.json).

Catatan dependency: npm memberi peringatan deprecated untuk ESLint 9.39.5 yang dipilih scaffold, serta postinstall unrs-resolver belum tercakup allowScripts. Kebijakan global script tidak diubah; lint/typecheck/build tetap lulus. Audit npm pada instalasi bersih melaporkan 0 vulnerabilities. Pemeliharaan versi lint diperiksa kembali sebelum staging.

## Click-through dan bukti browser

| Kontrol | Hasil yang diamati |
| --- | --- |
| Tema Terang/Gelap | Token dan latar berubah sesuai pilihan; latar light rgb(237,240,244), dark rgb(9,10,13) |
| Reload setelah memilih Gelap | Tema dark dan pilihan select tetap dark |
| Ikuti sistem | Atribut data-theme dihapus; CSS mengikuti tema sistem yang saat pengujian dark |
| Cari modul: monitoring | Hanya baris Monitoring API terlihat, selain header tabel |
| Cari modul: tidak-cocok | Pesan tidak ada hasil dan tombol pemulihan terlihat |
| Tampilkan contoh awal dari pencarian kosong | Query dibersihkan; tiga baris modul kembali |
| Kondisi Memuat | Pesan loading berlabel contoh terlihat, tanpa request backend |
| Kondisi Kosong | Pesan kosong dan aksi pemulihan terlihat |
| Tampilkan contoh awal dari state kosong | State normal dan tiga baris modul kembali |
| Kondisi Gagal | Pesan gagal berlabel contoh dan aksi pemulihan terlihat |
| Kembali ke contoh | State normal dan tiga baris modul kembali |
| Periksa batas starter | Dialog native terbuka melalui klik dan Enter |
| Tutup pemeriksaan | Form method=dialog menutup modal |
| Escape pada dialog | Dialog ditutup dan fokus kembali ke tombol pembuka |
| Lewati ke konten | Aktivasi Enter memindahkan fokus ke main dengan ID konten |
| Tab dari pilihan tema | Fokus berpindah ke input pencarian, outline solid 3 px sesuai tema |
| Dialog pada mobile 360 px | Lebar panel sekitar 316 px, tombol tutup 44 px, tanpa overflow halaman |

Seluruh kontrol yang terlihat pada matrix memiliki tinggi minimum 44 px. Dialog tertutup dikecualikan dari pengukuran target karena tidak dapat dioperasikan; tombol dialog diperiksa ketika modal terbuka. Tidak ada page overflow pada sepuluh kombinasi tema/viewport. Bukti ini berlaku pada Chromium in-app dan halaman starter.

| Viewport CSS px | Light | Dark |
| --- | --- | --- |
| 360 | [Screenshot](screenshots/admin-starter-phase1/light-360.jpg) | [Screenshot](screenshots/admin-starter-phase1/dark-360.jpg) |
| 375 | [Screenshot](screenshots/admin-starter-phase1/light-375.jpg) | [Screenshot](screenshots/admin-starter-phase1/dark-375.jpg) |
| 768 | [Screenshot](screenshots/admin-starter-phase1/light-768.jpg) | [Screenshot](screenshots/admin-starter-phase1/dark-768.jpg) |
| 1024 | [Screenshot](screenshots/admin-starter-phase1/light-1024.jpg) | [Screenshot](screenshots/admin-starter-phase1/dark-1024.jpg) |
| 1440 | [Screenshot](screenshots/admin-starter-phase1/light-1440.jpg) | [Screenshot](screenshots/admin-starter-phase1/dark-1440.jpg) |

[Dialog mobile](screenshots/admin-starter-phase1/dark-dialog-360.jpg) direkam sebagai viewport screenshot, bukan seluruh dokumen yang berada di belakang backdrop.

Temuan render yang diperbaiki sebelum bukti akhir:

1. Komponen daisyUI 5.7 ditempatkan pada nested utility layers. Aturan domain yang semula berada pada layer components kalah terhadap vendor, termasuk batas field. Aturan tt-* sekarang berada tanpa sublayer pada layer utilities; latar root dan border field terukur sesuai token tanpa blanket important atau penyalinan CSS vendor.
2. Background field diubah menjadi background-color agar chevron select vendor tetap terlihat.
3. Transisi color/background-color tombol vendor melintasi pasangan berkontras rendah saat tema berganti. Tombol starter kini hanya mentransisikan transform selama 150 ms; pengukuran tema langsung sesudah perubahan lulus.

Semua sebelas screenshot akhir dibuka dan ditinjau. Pada desktop, blok pemeriksaan menjadi fokus utama dan catatan fase mengikuti tinggi kontennya, tanpa isi pengisi. Pada tablet, kedua blok bertumpuk. Pada mobile, field dan label membungkus, identitas resource tetap terlihat, serta badge dapat menjadi dua baris pada lebar tersempit. Catatan teknis memang berada di halaman pemeriksaan pengembangan; bukan copy navigasi/admin operasional final.

## Pembacaan desain dan lingkup review

Fondasi existing memadai; gunakan daily driver Anti-slop + Taste jalur app screen. Tidak dilakukan draw arah baru atau penyusunan ulang sistem desain. ENERGY 2 / RHYTHM 2 / MOTION 1 diwarisi dari `DESIGN.md`.

Pertanyaan halaman starter: apakah tema dan komponen dasar sudah dapat dipakai sebelum migrasi halaman? Blok terbesar adalah pemeriksaan komponen; catatan batas fase menjadi blok pendamping. Logo existing, Inter, surface berlapis, aksen fokus, serta identitas method/route dan source/slug mengaitkan halaman dengan TonzToon. Badge hanya menyatakan integrasi starter belum tersambung; tidak ada KPI atau klaim kesehatan rekaan. Halaman ini merupakan halaman pemeriksaan pengembangan, bukan layout final Overview.

## Delivery Gate Anti-slop: starter

Status akhir **PASS untuk deliverable fase 1**. Tabel berikut menilai source milik aplikasi serta hasil browser yang disebutkan, bukan seluruh fitur admin atau kode vendor yang tidak digunakan. Penerimaan produk lengkap tetap mengikuti fase 2 sampai 4.

| Item | Status dan bukti |
| --- | --- |
| R-01: warna/dekorasi | PASS: surface berasal dari token; tidak menambahkan gradient/glow dekoratif |
| R-02: copy | PASS: copy Indonesia dan dokumen baru diperiksa tanpa em dash |
| R-03: mobile | PASS: sepuluh kombinasi tanpa overflow; kontrol terlihat minimum 44 px |
| R-04: ikon | PASS: memakai logo existing; tidak menambah ikon generik atau pustaka ikon baru |
| R-05: susunan | PASS: blok berisi pemeriksaan komponen dan batas fase, tanpa bagian pemasaran pengisi |
| R-06: tipografi | PASS: Inter sesuai DESIGN.md, font tersedia lokal dan terverifikasi; monospace hanya path/identitas |
| R-07: pola latar | PASS: tidak menambahkan pola grid dekoratif |
| R-08: panah | PASS: tidak menambahkan panah CTA dekoratif; chevron select menyatakan affordance kontrol |
| R-09: badge | PASS: badge dalam baris menyatakan belum terhubung, bukan hiasan di atas heading |
| R-10: glass | PASS: surface opaque, tanpa glass/backdrop blur |
| R-11: radius | PASS: token membedakan panel, inset, field, dan tombol; bukan semua pill |
| R-12: shadow | PASS: panel diam tanpa shadow tambahan; overlay memakai komponen modal |
| R-13: glow | PASS: tidak menambahkan efek glow |
| R-14: pengulangan panel | PASS: dua blok berbeda tugas dan ukuran; tidak membuat feature-card grid |
| R-15: CTA | PASS: label menyebut tindakan seperti Periksa batas starter dan Tampilkan contoh awal |
| R-16: bahasa | PASS: tidak ada klaim pemasaran atau buzzword produk |
| R-17: angka/data | PASS: tidak menampilkan KPI backend rekaan; daftar modul dijelaskan sebagai rencana integrasi |
| R-18: testimonial | PASS: tidak membuat testimonial atau identitas orang rekaan |
| R-19: motion | PASS: feedback transform tombol terbatas; tidak menambah animasi masuk/loop; fallback reduced motion tersedia pada source |
| R-20: identitas | PASS: logo/font/token TonzToon serta motif method+route dan source+slug mengikuti konteks proyek |
| R-21: tema | PASS: terang, gelap, dan sistem bekerja; reload mempertahankan pilihan eksplisit |
| R-22: ilustrasi | PASS: tidak membuat ilustrasi generik atau asset pengganti |
| R-23: asset | PASS: logo disalin dari asset existing dan Inter mengikuti kontrak; tidak membuat avatar/angka baru |
| R-24: navigasi | PASS: satu skip link menuju main yang ada; tidak menampilkan menu menuju route belum dibangun |
| R-25: kontras | PASS: checker sumber dan 27 elemen runtime per tema lulus; batas/fokus memakai pasangan token terukur |
| R-26: fungsi kontrol | PASS: seluruh kontrol starter menghasilkan perubahan yang tercatat pada click-through |
| R-27: state | PASS: normal/memuat/kosong/gagal dan pemulihan benar-benar ditampilkan, dengan label contoh lokal |
| R-28: FAQ | PASS: tidak membuat FAQ template |
| R-29: palette | PASS: peran semantik mengikuti sistem desain existing; tidak membuat palette per halaman |
| R-30: peniruan | PASS: mengikuti desain TonzToon/prototype milik proyek, tanpa menyalin komposisi produk lain |
| R-31: alasan visual | PASS: hierarki, surface, font, radius, dan aksen dijelaskan pada pembacaan desain dan koreksi render |
| R-32: keyboard | PASS: kontrol HTML native berlabel; Tab, skip link, Enter, Escape, dan focus return teruji; outline 3 px terlihat |
| R-33: perubahan source | PASS: source CSS/TSX diedit langsung; tidak menambahkan skrip pengganti string untuk fitur UI |
| R-34: dua tema | PASS: seluruh matrix light/dark ditinjau dan tidak mencatat kerusakan komponen starter |
| R-35: runtime | PASS: hasil next build dijalankan melalui next start dan setiap kontrol diuji; console akhir bersih |
| R-36: klaim | PASS: integrasi backend, keamanan sesi, dan performa tidak diklaim telah selesai |
| R-37: arahan | PASS: DESIGN.md dibaca sebelum menulis UI; dials dan daily driver existing dicatat |
| R-38: konten | PASS: konten contoh lokal berlabel, tanpa log/akun/angka yang disamarkan sebagai data produksi |
| Liveness: dials | PASS: ENERGY 2 / RHYTHM 2 / MOTION 1 dicatat dan tidak diganti |
| Liveness: konsistensi | PASS: surface tenang, ritme menurut tugas, motion hanya feedback |
| Liveness: fokus | PASS: blok pemeriksaan komponen terbesar dan pertama pada screenshot |
| Liveness: ruang | PASS: gutter konsisten, mobile bertumpuk, blok pendamping tidak dipaksa sama tinggi |
| Liveness: aksen | PASS: biru muncul pada logo/fokus, tanpa mewarnai seluruh kontrol |
| Liveness: motif | PASS: identitas multisource dan route muncul dalam manifest modul serta konteks TonzToon |
| Liveness: Design Read | PASS: pembacaan desain dan pertanyaan layar dicatat sebelum serah hasil |
| C-1: intentionality | PASS: keputusan mengikuti kontrak existing dan temuan render konkret |
| C-2: fungsi lengkap | PASS: tidak ada kontrol starter mati; lihat daftar click-through |
| C-3: substansi | PASS: setiap blok memeriksa komponen atau menjelaskan batas fase pengembangan |
| C-4: resilience | PASS: state, dua tema, keyboard yang dicatat, serta lima viewport berhasil pada Chromium in-app |
| C-5: bukti | PASS: klaim dibatasi pada hasil command, source, dan browser yang benar-benar diperiksa |

## Batas yang belum diverifikasi

Migrasi 33 halaman, runtime ERD/Data Flow, login/session store, RBAC, API/backend, schema/migration database, collector/worker, realtime SSE/polling, mutation, Preview Komik, beban, hosting/reverse proxy, dan staging belum menjadi hasil fase starter. Bukti QA prototype dan source backend existing tidak dipakai sebagai bukti fitur tersebut sudah lulus pada aplikasi Next.js.

Matrix penerimaan lengkap untuk landscape, zoom teks 200%, forced colors, aktivasi reduced motion, pergantian preferensi OS langsung, storage ditolak/rusak pada browser, dan browser selain Chromium belum dijalankan pada fase 1. Fallback yang tersedia pada source tidak dilaporkan sebagai pengujian runtime kondisi tersebut. Semua kondisi ini tetap diperiksa pada fase UI/testing yang relevan.

Fase 2 tetap menunggu konfirmasi pengguna. [Server hasil build untuk peninjauan lokal](http://127.0.0.1:3100) berjalan di mesin ini; ini bukan deployment.
