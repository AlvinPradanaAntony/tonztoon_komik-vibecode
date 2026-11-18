# Implementasi frontend fase 2

Tanggal: 30 Oktober 2026. Acuan: [todo](todo_web_admin_monitoring.md), [PRD 1.5](prd_web_admin_monitoring.md), [DESIGN.md](../DESIGN.md), dan 33 HTML [prototype](../web/prototype/README.md). Mode Anti-slop **during** dipilih pengguna pada sesi ini. Daily driver: Anti-slop + Taste, jalur app screen, tanpa menyusun ulang fondasi desain.

Status: **fase 2 selesai untuk frontend contoh terisolasi**. Seluruh 33 halaman prototype terpetakan dan interaksi P0 frontend telah diperiksa. Laporan ini menggantikan checkpoint awal; fase 3 tetap menunggu konfirmasi pengguna.

## Cakupan implementasi

| Kelompok | Frontend dan route |
| --- | --- |
| Sesi | `/login`: field berlabel, validasi, respons contoh 401/403/kedaluwarsa; tidak membuat sesi autentikasi |
| Overview | `/overview`: satu snapshot untuk KPI, bucket, distribusi status HTTP, quantile, coverage dan tabel endpoint; simulator terhubung ke halaman monitoring |
| Endpoint | `/endpoints`, `/endpoints/[id]`: inventaris termasuk tanpa trafik, pencarian/filter/urutan, histogram nonkumulatif, grafik, referensi kontrak dan request terkait |
| Request | `/requests`, `/requests/[id]`: filter, metadata tersanitasi, pagination URL, pause/batch/resume, batas 1.000 event dan korelasi |
| Runtime | `/runtime-logs`, `/runtime-logs/[id]`: Terminal/Terstruktur dari event sama, filter, jeda, event baru, autoscroll, wrap, perluas, clear lokal, salin, traceback dan inspector |
| Health / alert | `/health`, `/alerts`, `/alerts/[id]`: coverage/jadwal, probe unknown, komponen terpisah; pending/firing/resolved/unknown dan timeline evaluator contoh dengan ambang/hold |
| Katalog / chapter | `/data/comics`, detail/edit/new, daftar/tambah chapter per komik, detail/edit chapter: source/override/efektif, identitas tetap, nomor pecahan, arsip/pulih |
| Genre / source | `/data/genres`, editor/new dan detail; `/data/sources`, detail registry baca saja |
| Akun / library | `/data/accounts`, detail/edit/new akun reader, masking email, status akun dan `/library` terbatas baca saja |
| Helpdesk / audit | Daftar/detail helpdesk, editor status/catatan; daftar/detail audit, filter, diff katalog aman serta operation/request ID yang tersedia |
| Preview / reader | `/comic-preview`, detail `(source, slug)`, seluruh metadata chapter aktif dan reader chapter; antrean tiga transfer, prefetch dua page, stop/retry/reset, status HTTP/body/decode dan timeline attempt |
| Diagram | `/data-flow`: card DOM + SVG custom; `/data-model`: empat ERD React Flow readonly, dictionary, pencarian, relasi, inspector dan alternatif daftar |

Seluruh 33 HTML memiliki padanan pada [peta migrasi todo](todo_web_admin_monitoring.md#peta-migrasi-33-halaman-prototype). Catch-all Data memakai parser route ber-allowlist, dengan `new`, detail, edit, library dan chapter parent yang dibedakan. Path di luar peta direspons not-found. Tambah/edit genre memakai route form bersama, sementara prototype memakai dialog. Helpdesk tidak mempunyai aksi tambah/hapus pada P0.

Perubahan berkas terkonsentrasi pada [route aplikasi](../web/src/app/), [komponen admin](../web/src/components/admin/), [Data Flow](../web/src/components/data-flow/) dan [ERD](../web/src/components/erd/); adapter/fixture/controller berada di [lib](../web/src/lib/). Komponen bersama Button/Card/Table/styles disesuaikan untuk reflow, heading panjang dan pagination terkontrol. Tambahan lain adalah [script QA](../web/scripts/), [salinan placeholder reader](../web/public/demo-reader/), stylesheet diagram, `.env.example`, README dan laporan/checklist. Tidak menambahkan dependency baru atau mengubah lockfile.

## Batas data dan arsitektur

- Mode contoh membutuhkan **`ADMIN_FRONTEND_DEMO=true` di server**. Nilai bawaan pada `.env.example` adalah `false`. Console tidak menampilkan workspace contoh ketika sakelar mati; route fixture gambar mengembalikan 404. Sakelar ini bukan autentikasi dan tidak boleh menjadi pengganti sesi/RBAC fase 3.
- [Tipe domain](../web/src/lib/admin-data/types.ts), [fixture katalog](../web/src/lib/demo/catalog.ts) dan [repository contoh](../web/src/lib/admin-data/demo-repository.ts) terpisah dari view. State repository hidup dalam memori tab; reload mengembalikan baseline. Draft editorial memakai sessionStorage dengan fallback saat storage ditolak. Password/email utuh akun tidak masuk draft, URL atau audit.
- Repository contoh memeriksa revision, identitas duplikat, relasi chapter, role reader, idempotency payload, operasi tertunda/rekonsiliasi, serta immutability. Arsip/pulih mempertahankan relasi. Audit dibatasi 200 event contoh; tindakan tertunda dibatasi 100. Ini pengujian perilaku frontend, bukan transaksi database atau keamanan server.
- [Snapshot monitoring](../web/src/lib/monitoring/demo-store.ts) dibagi lintas halaman. Satu pump lokal bertick ketika demo berjalan dan tab aktif. Raw event/probe berbatas 1.000; agregat hanya dihitung dari event contoh yang masih tersimpan. Coverage historis yang tidak lengkap tetap ditampilkan.
- Request ID pada audit historis yang tidak terdapat pada fixture monitoring hanya menjadi referensi; UI menjelaskan ketidaktersediaan tanpa membuat detail request/runtime rekaan.
- [Reader](../web/src/lib/comic-preview/reader-controller.ts) mengambil salinan **tiga SVG placeholder existing** dari prototype. Blob yang sama dipakai untuk pengukuran dan display tanpa image optimizer/unduhan diagnostik kedua. HTTP 403/404/413/503/504, HTML 200 dan bytes korup berasal dari route fixture lokal yang terisolasi. Timeout/body failure/payload invalid berlabel simulasi. Hasil ini tidak menguji source/CDN/image proxy produksi.
- Data Flow tidak mengimpor React Flow. CSS domain hanya menambahkan keyframe dash dan integrasi vendor ERD; layout tetap utility Tailwind dan komponen daisyUI/TonzToon. Gerak arah hanya pada mode demonstrasi eksplisit; edge belum diukur tidak memperoleh angka aktivitas. Reduced motion, stale/gap dan tab tidak aktif menghentikan indikasi gerak.
- Manifest ERD A/B mengikuti subset kontrak/model existing. C/D menampilkan **rancangan PRD**, berlabel usulan. Source backend sudah memiliki beberapa tabel admin/monitoring dengan nama/struktur berbeda dari diagram PRD. Penerapan DB, nullability yang belum diverifikasi, rekonsiliasi migration dan manifest server tetap pekerjaan audit fase 3. Tidak ada introspeksi DB dari browser.

## Bukti pemeriksaan

Build yang diuji dijalankan dengan `next start` pada loopback, mode contoh diaktifkan secara eksplisit. Browser QA menggunakan Chromium headless nyata melalui helper CDP Taste lokal. Script browser memerlukan instalasi skill tersebut dan Chrome/Edge; ini bukan klaim pipeline CI browser sudah disiapkan.

| Pemeriksaan | Hasil akhir |
| --- | --- |
| Lint | `npm run lint` lulus setelah koreksi source final |
| Typecheck / build | `npm run typecheck` dan build produksi Next.js 16.4.3 lulus; build final juga menjalankan pemeriksaan TypeScript |
| Invarian adapter/editor/reader | `check-admin-phase2.mjs` lulus: identitas immutable/duplikat/pecahan, versi, idempotency, pending/rekonsiliasi, arsip, agregasi/retensi/redaksi, payload gambar, route dan rentang kustom |
| Regresi Overview / Table / style | Lulus; Node mengeluarkan warning module-type pada dua script existing, bukan error aplikasi |
| Route / tema / viewport | Build final: 33 route × 2 tema × 2 lebar (1440/360 px) = 132 kombinasi, ditambah 72 state; 0 kegagalan, 0 exception browser tercatat |
| Interaksi | Build final: 15 kelompok, 102 assertion; 0 kelompok gagal, 0 exception browser. Termasuk Enter/Escape diagram dan badge insiden sidebar ringkas |
| Kontras / keyboard / responsive tambahan | 36 kombinasi pada 375/768/1024 px, 422 sampel kontras dan 6 kondisi khusus (landscape, teks 200%, forced-colors, storage ditolak); 0 error |
| Taste app-screen inspector | Build final pada 1440/768/390 px: 0 FAIL, 0 WARN; keenam screenshot yang dicantumkan inspector dibuka dan ditinjau |
| Isolasi mode contoh | Build final dengan flag mati: console tidak menampilkan katalog contoh dan fixture gambar mengembalikan 404 |
| Batas perubahan | `git diff --check` lulus; tidak ada perubahan sesi ini pada `DESIGN.md`, `web/prototype`, atau backend; perubahan staged sebelumnya dipertahankan |

Folder bukti: [screenshot dan JSON](screenshots/admin-phase2-complete/). Script yang dapat dijalankan dari `web/`: `scripts/check-admin-phase2.mjs`, `scripts/check-admin-phase2-browser.mjs`, `scripts/check-admin-phase2-interactions.mjs`, dan `scripts/check-admin-phase2-accessibility.mjs`.

Temuan yang diperbaiki selama pemeriksaan: judul endpoint panjang menyebabkan overflow ponsel; angka jumlah chapter/relasi perlu rata akhir; breadcrumb masih menyebut Monitoring pada modul Data; SVG `<title>` dengan beberapa potongan children menyebabkan hydration mismatch; draft belum dibersihkan setelah rekonsiliasi berhasil; label tombol meluber saat teks diperbesar; link aksi membawa shadow vendor; serta selection keyboard ERD belum diteruskan ke state terkontrol. Koreksi terakhir diperiksa pada build produksi yang diserahkan.

Catatan pengujian: dispatch Enter pada harness CDP menyertakan karakter carriage return agar menghasilkan aktivasi native, lalu menunggu perubahan URL sebelum memeriksa inspector. Navigasi antar-kelompok menerima unload guard draft secara sengaja. JSON menyimpan pengulangan final yang lulus; temuan yang dikoreksi dirangkum di atas.

Inventaris click-through tersedia per assertion di `interactions.json`. Alur yang diperiksa meliputi validasi dan empat hasil login; preview/diff/Escape/fokus/save/reset editor; draft/conflict/copy/pending/reconciliation; archive/restore; filter/reset/pagination/kembali; editor genre/chapter pecahan/akun/helpdesk; pemulihan state dan izin contoh; pause/batch/resume request; korelasi request ke runtime; mode/filter/copy/wrap/expand/clear runtime; health unknown dan evaluator alert; rentang kustom dan cutoff; urutan feed/search/chapter/reader/HTTP/bytes/decode/retry/reset; selection/pan/zoom/fit/reset/motion Data Flow; empat ERD/search/dictionary/relasi/zoom; drawer/sidebar dan seluruh 15 tujuan navigasi. Kontrol bersama memakai perilaku native dan kontrak komponen yang telah diperiksa pada tahap 2.0.

Skill codebase-memory dibaca sesuai instruksi terbaru. Tool graph/index tidak tersedia pada sesi ini, sehingga pemeriksaan source memakai pencarian path/simbol yang dibatasi dan pembacaan source langsung. Tidak ada klaim cakupan graph atau audit backend menyeluruh.

## Kritik render dan arah desain

Tidak melakukan draw arah baru: font Inter, logo existing, navigasi netral, token dua tema, shell 80/240 px, drawer, kontrol dan radius mengikuti kontrak. Dials tetap **ENERGY 2 / RHYTHM 2 / MOTION 1**, dengan MOTION 2 hanya pada demonstrasi Data Flow. Tidak membuat cover, avatar atau logo baru. Placeholder reader diberi label file contoh.

Pertanyaan per layar mengikuti tugasnya: Overview menjawab kondisi API; daftar mengarahkan ke resource; detail membandingkan metadata/relasi; editor menunjukkan perubahan sebelum konfirmasi; reader memisahkan transfer dan decode; diagram menjelaskan hubungan tanpa mengarang measurement. Focal point mengikuti tugas, bukan dekorasi. Angka dan grafik berasal dari fixture deterministik yang berlabel; identitas `(source, slug)` menghubungkan katalog, preview dan inspector.

Perbandingan visual memakai screenshot prototype existing dan hasil produksi dua tema. Perbedaan yang disengaja: primitive produksi yang sudah disepakati, editor React reusable, pagination/filter URL, Terminal PRD 1.5, serta pemisahan renderer Data Flow dan ERD. `DESIGN.md` dan source prototype tidak diubah untuk menyesuaikan bukti implementasi.

Kritik mengikuti tujuh pertanyaan app-screen Taste, bukan penilaian halaman pemasaran yang mewajibkan foto atau gerak dekoratif:

| Pertanyaan render | Penilaian dan bukti |
| --- | --- |
| Tugas terbaca pertama | Katalog mendahulukan judul, tambah dan daftar resource; editor mendahulukan field serta pemeriksaan perubahan. Reader memisahkan hasil attempt dari isi page. Lihat screenshot 12, 14 dan 31. |
| Tepi dan ruang konsisten | Header, panel dan konten memakai gutter shell existing. Filter beralih empat, dua, lalu satu kolom; tidak menambahkan panel kosong untuk menyamakan tinggi. Screenshot Taste desktop/tablet/mobile memperlihatkan reflow. |
| Warna dan font | Inter existing; navigasi netral. Warna status menunjukkan keadaan, aksen pada fokus/data, aksi utama memakai foreground/canvas. Shadow bawaan link tambah dihapus agar konsisten dengan Button. |
| Angka konsisten | Jumlah relasi memakai angka tabular rata akhir. Snapshot bersama menghitung jumlah/status/error rate/quantile dari event yang sama; script invarian dan regresi menghitung ulang agregat, coverage serta cutoff. |
| Nol, missing dan antrean berbeda | Endpoint tanpa sampel memakai missing, slot probe belum diamati tetap unknown. Badge sidebar hanya menghitung pending/firing dan diberi noun insiden, tanpa angka insiden statis prototype. |
| Legend dan label | Warna seri mengikuti token dan tabel alternatif memakai nilai yang sama. Histogram tidak kumulatif. Edge Data Flow berlabel belum diukur; demonstrasi arah tidak menjadi bukti request per-hop. |
| Ponsel | Sidebar menjadi drawer. Diagram adaptif menjadi daftar; canvas dapat dipilih secara eksplisit dengan zoom/pan. Tabel lebar mempunyai scroll lokal berlabel; dokumen tidak meluber horizontal. |

Screenshot prototype yang ditinjau: `comics-light/dark.png`, `preview-reader-mobile-light.png`, `data-flow-light.png`, dan `data-model-light.png`. Perbandingan mempertahankan identitas dan tugas tiap layar. Perubahan komponen netral, token produksi, bentuk tombol, dan sidebar mengikuti koreksi tahap 2.0/kontrak root yang sudah disepakati, meskipun beberapa screenshot prototype lebih lama masih memakai aksi/sidebar berwarna. Tidak ada draw atau seed arah baru.

## Delivery Gate frontend

Gate ini berlaku pada frontend contoh fase 2. PASS menyatakan hasil dalam cakupan bukti lokal di atas, bukan sertifikasi aksesibilitas menyeluruh atau penerimaan backend produksi. Catatan click-through per assertion berada pada [interactions.json](screenshots/admin-phase2-complete/interactions.json); pemeriksaan komponen reusable juga mengikuti bukti tahap 2.0.

| Hard Gate | Hasil dan bukti |
| --- | --- |
| R-02 | PASS: pencarian source UI tidak menemukan em dash; copy memakai kalimat biasa dan label teknis. |
| R-03 | PASS: matriks route, reflow tambahan, landscape dan teks 200% tidak menemukan overflow dokumen; tabel lebar memakai scroll lokal. Judul endpoint dan label tombol yang meluber telah dikoreksi. |
| R-17 | PASS: KPI, jumlah, grafik dan alert berasal dari fixture deterministik berlabel contoh; agregat diverifikasi ulang oleh script. |
| R-18 | PASS: tidak ada testimonial, avatar orang rekaan atau klaim pelanggan. |
| R-23 | PASS: logo/navigasi existing dipakai ulang; cover dan tiga page SVG adalah placeholder yang ditandai. Tidak membuat aset visual baru. |
| R-24 | PASS: seluruh 15 tujuan sidebar, login dan halaman pemeriksaan komponen dibuka lewat browser; parser Data menolak path di luar allowlist. |
| R-25 | PASS: 422 sampel teks pada dua tema memenuhi ambang AA yang berlaku pada sampel; warna status dan teks tetap memakai token bersama. Bukan audit seluruh pasangan piksel. |
| R-26 | PASS: inventaris kontrol P0 pada laporan interaksi mempunyai href/handler dan hasil yang terlihat; aksi contoh berlabel, permission guard dan disabled menjelaskan batasnya. |
| R-27 | PASS: loading/empty/filter kosong/error/denied/stale/partial/timeout/gap/down tersedia; 72 state modul diuji pada browser. |
| R-28 | PASS: tidak menambahkan FAQ atau blok copy pengisi. |
| R-32 | PASS: keyboard dialog/drawer, focus return, Enter/Escape diagram dan focus forced-colors diperiksa. Data Flow tidak memilih hanya karena fokus; ERD mengirim selection controlled ke inspector. |
| R-33 | PASS: implementasi ditulis pada source React/TypeScript/CSS; script QA hanya menjalankan dan memeriksa aplikasi. Tidak ada injeksi source/CSS runtime untuk membangun fitur. |
| R-34 | PASS: seluruh route diperiksa pada tema light/dark; inisialisasi tema dan storage ditolak mempunyai fallback. |
| R-35 | PASS: lint, typecheck, build produksi dan browser nyata dijalankan; 15 kelompok/102 assertion click-through lulus, tanpa exception yang tercatat pada pengulangan final. |
| R-36 | PASS: UI dan laporan menyatakan simulasi lokal; tidak ada klaim sesi aman, collector aktif, uptime atau performa produksi. |
| R-37 | PASS: Design Read memakai root DESIGN.md dan fondasi yang disepakati; dials ENERGY 2 / RHYTHM 2 / MOTION 1 dinyatakan sebelum migrasi. |
| R-38 | PASS: fixture katalog/akun/helpdesk dan monitoring ditandai contoh; source/override/efektif serta existing/usulan/belum diukur dibedakan. |

| Purpose-Gate | Hasil dan alasan |
| --- | --- |
| R-01 | PASS: tidak menambahkan gradient atau glow; hierarki memakai surface dan tipografi existing. |
| R-04 | PASS: ikon SVG existing menjelaskan modul atau aksi; buku untuk katalog/reader, panah untuk navigasi, dan ikon diagram untuk relasi. |
| R-06 | PASS: Inter mengikuti identitas; monospace hanya untuk output runtime/ID/URL yang perlu dibandingkan, tanpa judul monospace dekoratif. |
| R-07 | PASS: koordinat diagram dan garis grafik menjelaskan topologi/data, bukan pola background dekoratif. |
| R-08 | PASS: panah menyatakan arah relasi atau sebelumnya/berikutnya; tidak ditambahkan ke seluruh CTA sebagai ornamen. |
| R-09 | PASS: badge menyampaikan status resource, scope contoh, existing/usulan atau antrean insiden yang perlu diperiksa. |
| R-10 | PASS: tidak memakai glassmorphism. |
| R-12 | PASS: surface memisahkan panel; shadow mengikuti kontrak overlay/Alert existing. Link aksi tidak membawa shadow vendor. |
| R-13 | PASS: tidak menambahkan glow pada tombol, kartu, ikon atau background. |
| R-14 | PASS: pengulangan row/card memudahkan perbandingan resource dan node; editor, detail, chart dan terminal memakai susunan sesuai tugasnya. |
| R-19 | PASS: gerak hanya feedback/overlay/loading; demonstrasi dash Data Flow eksplisit, berhenti pada reduced motion, stale/gap dan tab tidak aktif. |
| R-22 | PASS: tidak menambahkan ilustrasi generik; placeholder reader berasal dari aset prototype dengan penjelasan batasnya. |

| Liveliness | Hasil dan bukti |
| --- | --- |
| Dials eksplisit | PASS: ENERGY 2 / RHYTHM 2 / MOTION 1; pengecualian MOTION 2 hanya demo arah Data Flow. |
| Dials sesuai render | PASS: tidak ada entrance/dekorasi bergerak; layout operasional tetap tenang, feedback berfungsi dan reduced motion diuji. |
| Focal point | PASS: judul/tugas dan data utama mendahului kontrol sekunder; tujuh pertanyaan kritik render dicatat di atas. |
| Ruang struktural | PASS: gutter shell, jarak section dan kelompok field konsisten pada screenshot desktop/tablet/mobile yang ditinjau. |
| Aksen disengaja | PASS: aksen mengikuti token fokus/data, warna semantik mengikuti status; navigasi netral dan primary memakai foreground/canvas. |
| Motif identitas | PASS: logo, Inter, shell inset dan surface bertingkat existing berulang; identitas source + slug menautkan katalog dan reader. |
| Design Read | PASS: migrasi prototype dengan fondasi memadai memakai Anti-slop + Taste app-screen; tidak melakukan draw atau revisi global desain. |

| Craftsmanship / Quality Locks | Hasil dan bukti |
| --- | --- |
| C-1 | PASS: pilihan utama diturunkan dari DESIGN.md dan tugas tiap layar; tidak menyusun arah visual default baru. |
| C-2 | PASS: kontrol P0 mempunyai hasil yang tercatat; penolakan izin dan ketidaktersediaan integrasi diberi penjelasan. |
| C-3 | PASS: komposisi berasal dari monitoring, CRUD editorial, diagnosis reader dan diagram; tidak ada section pemasaran pengisi. |
| C-4 | PASS: dua tema, breakpoint, sembilan state, keyboard, teks 200%, forced-colors dan storage ditolak diperiksa sesuai cakupan bukti. |
| C-5 | PASS: tidak mengubah simulasi menjadi klaim pengguna, performa atau layanan produksi. |
| R-05 | PASS: daftar/detail/editor/terminal/diagram memakai pola tugas berbeda; tidak memakai hero atau bento pemasaran generik. |
| R-11 | PASS: kontrol, panel, badge dan tombol ikon memakai radius kontrak masing-masing; tidak semuanya berbentuk kapsul. |
| R-15 | PASS: CTA menyebut tindakan: tambah komik, periksa perubahan, salin log, retry page, fit ERD dan pulihkan. |
| R-16 | PASS: copy menjelaskan tindakan dan batas contoh; tidak ada slogan atau buzzword AI. |
| R-20 | PASS: source + slug, chapter pecahan, source/override/efektif dan diagnosis transfer/decode membuat konten khusus TonzToon. |
| R-21 | PASS: tema mengikuti preferensi tersimpan lalu sistem; pilihan dua tema tetap tersedia dengan fallback storage. |
| R-29 | PASS: core palette dan warna status memakai token root existing, tanpa palette tambahan per halaman. |
| R-30 | PASS: mempertahankan shell/prototype TonzToon; tidak mengambil identitas produk lain atau arah desain baru. |
| R-31 | PASS: alasan layout, font, warna, diagram dan aset dijelaskan dalam cakupan, batas arsitektur dan kritik render laporan ini. |

## Batas penerimaan berikutnya

Tidak menguji atau mengimplementasikan sesi/RBAC server, BFF produksi, SSE/polling backend, collector/probe/worker nyata, mutation database, image proxy/source eksternal, migration terpasang, benchmark atau staging. Semua itu tetap fase 3/4. Hasil frontend contoh tidak membuktikan keamanan, kesehatan atau konsistensi deployment produksi.

Browser yang diperiksa adalah Chromium nyata; engine lain dan pengujian screen reader menyeluruh belum dijalankan. Pengukuran kontras adalah sampel computed style pada konten yang terlihat, bukan sertifikasi WCAG seluruh aplikasi. Catatan `consoleErrors` pada helper CDP merekam exception runtime, termasuk hydration error; bukan inventaris seluruh pesan console/network. Respons HTTP gagal yang memang diminta pada fixture reader tetap merupakan bagian diagnosis contoh.

Checkpoint berikutnya mengikuti todo: **laporkan cakupan halaman, bukti browser, dan batas integrasi, lalu tanyakan konfirmasi untuk fase 3**. Fase 2 selesai tidak mengizinkan integrasi backend, migration atau deployment secara otomatis.
