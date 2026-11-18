# TonzToon Admin Web

Starter Next.js berada langsung di root `web/`, sesuai keputusan pengguna pada 26 Oktober 2026. [Prototype HTML](prototype/README.md) tetap berada di `web/prototype/`, dengan dependency dan build stylesheet tersendiri. Prototype tidak menjadi route atau public asset aplikasi Next.js.

Status implementasi frontend fase 2: seluruh 33 HTML sudah memiliki padanan route React, termasuk login, monitoring, editor data, preview/reader, Data Flow custom dan ERD React Flow. Halaman `/` tetap memeriksa komponen. Cakupan, bukti dan status verifikasi akhir berada pada [laporan fase 2](../docs/admin_frontend_phase2_completion.md). Sesi/RBAC server, BFF produksi, telemetry, SSE, mutation database dan akses source/proxy nyata tetap fase 3.

Lihat [todo dan checkpoint fase](../docs/todo_web_admin_monitoring.md), [PRD 1.5](../docs/prd_web_admin_monitoring.md), dan [DESIGN.md](../DESIGN.md). Fase berikutnya selalu menunggu konfirmasi pengguna.

## Runtime dan dependency

Versi yang terpasang pada bootstrap:

| Komponen | Versi |
| --- | --- |
| Node.js | 24.14.0, tercatat pada `.nvmrc` |
| npm | 11.18.0 |
| create-next-app / Next.js | 16.4.3 |
| React / React DOM | 19.3.0 |
| TypeScript | 5.9.3 |
| Tailwind / integrasi Turbopack | 4.3.3 |
| daisyUI | 5.7.50 |
| React Flow `@xyflow/react` | 12.12.0 |
| Inter `@fontsource-variable/inter` | 5.3.0 |

`package-lock.json` adalah acuan versi dependency transitif. `engines` menetapkan keluarga runtime yang dipakai starter; minimum Next.js yang dilaporkan paket ini adalah Node.js 20.9.0. Build tidak memerlukan akses ke Google Fonts: Inter disajikan dari dependency npm lokal, dengan fallback sistem. Font monospace memakai font sistem.

## Instalasi dan menjalankan

Dari direktori `web/`:

```powershell
rtk proxy npm ci --include=dev
rtk npm run dev
```

Buka [localhost:3000](http://localhost:3000). Untuk pemeriksaan hasil produksi:

Console contoh perlu diaktifkan secara eksplisit pada lingkungan lokal/terisolasi. Tambahkan nilai berikut pada `.env.local` lokal atau environment proses server, tanpa mengganti konfigurasi lain yang sudah tersedia:

```dotenv
ADMIN_FRONTEND_DEMO=true
```

Nilai bawaan contoh konfigurasi adalah `false`. Saat mati, console menampilkan status integrasi belum aktif dan route fixture gambar mengembalikan 404. Sakelar ini hanya membuka fixture frontend; tidak membuat autentikasi atau akses backend.

```powershell
rtk npm run lint
rtk npm run typecheck
rtk npm run build
rtk npm run start
```

`typecheck` menjalankan `next typegen` sebelum `tsc --noEmit`, sehingga dapat dijalankan dari checkout bersih. Lint dijalankan terpisah dari build. Build stage/CI harus memasang dev dependency karena Tailwind, daisyUI, dan TypeScript digunakan saat kompilasi. Jangan memakai static export: fase integrasi membutuhkan BFF dan sesi server runtime Node.js.

## Asal scaffold

Starter dihasilkan oleh CLI resmi, bukan konfigurasi framework yang ditulis ulang. Karena `web/` sudah berisi prototype, generator dijalankan pada staging kosong, kemudian seluruh hasilnya dipindahkan ke `web/` setelah pemeriksaan benturan nama:

```powershell
rtk proxy npx --yes create-next-app@latest .codex-bootstrap/web --ts --eslint --tailwind --app --src-dir --import-alias "@/*" --use-npm --disable-git --yes --no-agent-feedback
```

Staging sudah dibersihkan setelah pemindahan. Tidak ada Git repository bersarang. Dependency tambahan dipasang dari `web/`:

```powershell
rtk npm i -D daisyui@latest
rtk npm install @xyflow/react @fontsource-variable/inter server-only
```

Scaffold stable ini menghasilkan konfigurasi Tailwind **Turbopack loader**, Cache Components, dan Partial Prefetching pada `next.config.ts`. Konfigurasi tersebut dipertahankan; tidak ditambahkan konfigurasi PostCSS alternatif. Periksa dokumentasi yang dibundel di `node_modules/next/dist/docs/` dan `AGENTS.md` hasil generator sebelum mengubah API/config versi ini.

## Struktur dan batas implementasi

```text
web/
  prototype/                    referensi HTML existing, dipertahankan
  public/logo.png               salinan logo existing
  src/app/layout.tsx            Server Component, metadata dan bootstrap tema
  src/app/page.tsx              halaman pemeriksaan starter
  public/demo-reader/           tiga placeholder SVG existing, berlabel contoh
  src/app/login/                frontend login dan state sesi contoh
  src/app/(console)/            shell, monitoring, Data, preview dan diagram
  src/app/api/demo-reader/      respons diagnostik lokal, dibatasi sakelar contoh
  src/app/api/                  placeholder BFF produksi fase 3
  src/components/ui/            komponen bersama dengan props/state bertipe
  src/components/admin/        halaman, editor dan pola domain reusable
  src/components/data-flow/     viewer DOM/SVG custom
  src/components/erd/           viewer React Flow yang dimuat khusus ERD
  src/lib/admin-data/           kontrak bertipe dan repository contoh
  src/lib/demo/                 fixture deterministik, bukan akses backend
  src/lib/monitoring/           snapshot bersama dan adapter tampilan
  src/lib/comic-preview/        controller diagnosis reader
  src/lib/diagrams/             manifest topology dan subset schema
  src/styles/tokens.css         tema dan mapping token semantik
  src/styles/integrations.css   integrasi native/vendor bersama
  src/styles/data-flow.css      keyframe dashed arrow custom
  src/styles/erd.css            integrasi variabel/control React Flow
```

Route aktif berada pada `(console)`; folder `.gitkeep` yang tersisa hanya placeholder. [Batas modul](src/lib/README.md) menjelaskan Server/Client Components dan data sensitif. React Flow beserta CSS resminya dimuat melalui import dinamis khusus ERD. Data Flow tetap DOM/SVG custom. Tidak ada import framework/script prototype ke aplikasi; tiga file SVG reader disalin sebagai fixture lokal.

Tailwind memindai `src/` secara eksplisit melalui `source(none)` dan `@source`; ESLint/TypeScript mengecualikan `prototype/`. Tidak ada import script, stylesheet terkompilasi, atau vendor prototype ke bundle aplikasi. Tabel memakai `@tanstack/react-table` v9 headless; scroll reusable memakai `overlayscrollbars` dan `overlayscrollbars-react`. Kontrak dan verifikasi ada di [migrasi tabel/scroll](../docs/admin_table_scroll_migration.md).

Styling aplikasi memakai Tailwind utility-first. Gunakan komponen `src/components/ui/`, props varian, dan class statis; `cx` memakai `tailwind-merge` agar override utility konsisten. Token semantik berada di `tokens.css`; pengecualian native/vendor yang beralasan berada di `integrations.css`. Stylesheet layout `components.css`, `admin.css`, dan `toast.css` sudah dihapus. Detail kontrak dan validasi: [refaktor Tailwind](../docs/admin_tailwind_refactor.md).

## Konfigurasi server

Fase 1 dapat dijalankan tanpa `.env.local` atau credential. [.env.example](.env.example) berisi nama konfigurasi untuk fase integrasi:

| Variabel | Kegunaan pada fase 3 |
| --- | --- |
| `ADMIN_FRONTEND_DEMO` | Khusus frontend fase 2: `true` hanya pada lingkungan contoh terisolasi; default `false` |
| `BACKEND_BASE_URL` | Target backend dari allowlist server |
| `ADMIN_WEB_ORIGIN` | Pemeriksaan Origin/CSRF dan origin cookie admin |
| `ADMIN_SESSION_DATABASE_URL` | Session store dengan identitas DB terbatas |
| `ADMIN_SESSION_ENCRYPTION_KEY` | Enkripsi token pada session store server |

Nilai contoh bukan koneksi yang sudah diuji. Jangan memasukkan secrets ke `NEXT_PUBLIC_*`, source, props Client Component, localStorage, atau URL. Modul pembaca secrets nantinya wajib mengimpor `server-only`. Konfigurasi sesi, validasi target/izin, dan koneksi DB/BFF dibuat pada fase 3.

## Tema dan pemeriksaan komponen

Tema custom daisyUI bernama `light` dan `dark` menggunakan token `DESIGN.md`; tema vendor bawaan dinonaktifkan. Primary memetakan foreground/canvas; aksen biru tetap untuk identitas/fokus/data yang relevan. Surface, input, badge, table, alert, dan dialog memakai sumber token yang sama. Pada versi terpasang, komponen daisyUI berada dalam nested utility layers; aturan domain TonzToon ditempatkan tanpa sublayer di layer utilities agar mengungguli vendor. Utility layout biasa tetap dapat menyempurnakan layout. Latar field hanya mengubah background-color agar chevron select vendor tetap terlihat. Tombol hanya mentransisikan transform, sehingga pergantian tema tidak melintasi warna berkontras rendah.

Pilihan tema eksplisit disimpan pada `localStorage` dengan kunci `tt-admin-theme`. Bootstrap inline konstan pada head menerapkannya sebelum isi halaman; saat pilihan sistem aktif, CSS mengikuti perubahan `prefers-color-scheme` tanpa listener JavaScript. Storage yang ditolak/rusak kembali ke tema sistem. Pilihan tema ini tidak menyimpan token autentikasi dan terpisah dari preferensi prototype.

Di halaman `/`, periksa pencarian dan empat kondisi tabel, tujuh varian Button, loading/disabled, Badge/StatusBadge, ukuran/tone field, invalid, readonly, serta Dialog/Drawer kedua sisi. Seluruh komponen memakai props bersama di [kontrak komponen](../docs/admin_ui_components.md). Default netral dipisahkan dari status, disabled, dan readonly; gunakan props varian, bukan class status yang bertentangan. Dialog/Drawer mengelola fokus awal, pembungkusan Tab/Shift+Tab, Escape, dan focus return melalui modal native.

Semua kondisi tersebut lokal; tidak ada pengiriman data atau pengukuran kesehatan backend. Shell dan Overview berada pada `/overview`, sementara `/` tetap halaman pemeriksaan komponen.

## Pemeriksaan frontend fase 2

Jalankan dari `web/`:

```powershell
rtk proxy node scripts/check-admin-phase2.mjs
rtk proxy node scripts/check-overview-demo.mjs
rtk proxy node scripts/check-table-model.mjs
rtk proxy node scripts/check-ui-styles.mjs
```

Pemeriksaan browser memakai Chrome/Edge headless dan helper CDP skill Taste lokal di `.agents/skills/taste-skill/`. Jalankan server hasil build dengan mode contoh terlebih dahulu. URL bawaan script adalah `http://127.0.0.1:3102`; `ADMIN_QA_URL` dapat mengubahnya.

```powershell
rtk proxy node scripts/check-admin-phase2-browser.mjs
rtk proxy node scripts/check-admin-phase2-interactions.mjs
rtk proxy node scripts/check-admin-phase2-accessibility.mjs
```

Bukti disimpan pada `docs/screenshots/admin-phase2-complete/`. Script browser ini adalah tooling verifikasi lokal, terpisah dari source prototype dan belum menjadi pipeline CI/staging.

Hasil bootstrap dicatat pada [laporan fase 1](../docs/admin_starter_phase1.md), dan fondasi komponen pada [laporan tahap 2.0](../docs/admin_ui_components_review.md). Bukti akhir 33 halaman, 132 kombinasi route, 102 pemeriksaan interaksi, kontras dan Delivery Gate berada pada [laporan penyelesaian fase 2](../docs/admin_frontend_phase2_completion.md). Integrasi dan staging tetap belum dijalankan.

## Referensi konfigurasi

Dokumentasi diperiksa melalui Context7 dan dicocokkan dengan paket terpasang:

- [Next.js create-next-app](https://nextjs.org/docs/app/api-reference/cli/create-next-app).
- [Next.js CLI typegen](https://nextjs.org/docs/app/api-reference/cli/next#next-typegen-options).
- [daisyUI custom themes](https://daisyui.com/docs/themes/) dan [config](https://daisyui.com/docs/config/).
- [Tailwind source detection](https://tailwindcss.com/docs/detecting-classes-in-source-files) dan [theme variables](https://tailwindcss.com/docs/theme).
