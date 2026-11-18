# Kontrak komponen UI TonzToon

Pembaruan 29 Oktober 2026: styling produksi kini utility-first sesuai [refaktor Tailwind](admin_tailwind_refactor.md). Layout/varian ditulis pada komponen React, token melalui `@theme inline`, dan override utility digabung dengan tailwind-merge. Uraian `tt-*` di bawah yang merujuk stylesheet lama merupakan riwayat kontrak; stylesheet aktif hanya `tokens.css` dan `integrations.css`. Card/Panel serta Dialog menyediakan props class header/body/panel untuk komposisi lokal; Tabs menyediakan compact/hidePanels, dan Select leading dekoratif. API perilaku/aksesibilitas tetap berlaku.

Tanggal: 27 Oktober 2026. Lingkup: fondasi awal fase 2 sebelum migrasi halaman. Acuan: [DESIGN.md](../DESIGN.md), [todo](todo_web_admin_monitoring.md), dan PRD bagian 21. Source: [web/src/components/ui](../web/src/components/ui/index.ts). Halaman pemeriksaan `/` memakai komponen ini dengan contoh lokal.

## Prinsip pemakaian

Gunakan wrapper tipis untuk class semantik daisyUI, HTML native, label/state, dan perilaku bersama. Komponen tidak mengakses backend atau memeriksa otorisasi. Tidak ada dependency UI baru atau component framework kedua. Props native yang relevan diteruskan; `className` dipakai untuk layout/kustomisasi domain, bukan menambahkan class status yang bertentangan dengan props.

State React dan callback interaksi berasal dari Client Component pemakai. Button/Card/Panel/Badge/Alert/Spinner tidak memerlukan state internal. Input/Select/Textarea/Checkbox menggunakan useId untuk hubungan label/hint/error. Dialog dan Drawer menyinkronkan prop open dengan dialog native; header, isi, dan footer tetap semantik.

## Props dan varian

| Komponen | Props bersama/khusus | Dasar daisyUI dan perilaku |
| --- | --- | --- |
| Button | variant: primary, secondary (default), ghost, info, success, warning, error; size; loading; disabled; props button native termasuk ref | btn dan modifier warna/ukuran. Secondary memakai btn-outline dengan surface/border TonzToon. type default button; submit harus eksplisit |
| Input | label wajib; hint, error, invalid, tone, size, loading, fieldClassName; props input/ref | input + modifier tone/ukuran; default netral. Label selalu terhubung ke input |
| Select | Kontrak field yang sama; children berupa option/optgroup native; ref | select + modifier tone/ukuran; chevron bawaan dipertahankan |
| Textarea | Kontrak field yang sama; rows default 3; ref | textarea + modifier tone/ukuran; dapat diperbesar vertikal |
| Checkbox | label, hint, error, invalid, tone, size, loading, disabled, props input/ref selain type/size | checkbox, native boolean/checked. Label menyediakan area tekan minimum 44 px |
| Card | title wajib; description, actions, size, children, props section | card/card-title/card-body, surface datar dan inner radius |
| Panel | Props Card selain surface | Pengelompokan berlapis dengan panel luar dan isi inset dari token existing |
| Table<T> | data, columns (TableColumn<T>[]), caption; globalFilter, columnFilters, sorting/onSortingChange, initialSorting, pagination, pageSize, getRowId, footer; state/message/onRetry/size/captionHidden, emptyState; props table | TanStack Table v9 headless: filter → sort → paginate; markup table milik TonzToon, aria-sort, header keyboard, state ready/loading/empty/error; scroll OverlayScrollbars berlabel/focusable |
| EmptyState | title, description, icon, illustration, action, size sm/md, announce; props div | Ikon/ilustrasi dekoratif, judul, deskripsi dan aksi terpusat. Default requests; search untuk filter kosong. Ukuran fleksibel, dua tema, announcement opsional tanpa pemindahan fokus. |
| Alert | tone, title, children, action, announce, props div/role | alert alert-soft + modifier tone. Default role note; announce=true memakai status atau alert untuk error |
| Badge | tone, appearance soft/outline/solid, size, props span | badge + warna, appearance, ukuran; noninteraktif |
| StatusBadge | status success/warning/error/unknown/loading/disabled; children opsional; props Badge selain tone | Mapping tone dan label Indonesia; status loading menambahkan spinner. Tidak membaca status layanan sendiri |
| Dialog | open, onOpenChange, title wajib; description, actions, closeLabel, size, props dialog selain open/title/ref | modal, native showModal/close, label/description unik, fokus modal, klik backdrop, Escape dan tombol Tutup |
| Drawer | Props Dialog, side start/end, size | Varian overlay samping melalui modal-start/modal-end, memakai primitive modal native yang sama |
| Spinner | size, label, decorative, props span | loading loading-spinner; dekoratif saat berada di tombol/badge yang sudah berlabel |
| Tabs | label wajib, items: TabItem[], value/defaultValue, onValueChange, className | tabs tabs-box/tab/tab-active daisyUI, track netral dengan penanda bergeser; React mengatur pilihan dan panel |

Ukuran bersama `sm`, `md`, `lg`: kontrol sm/md minimum 44 px, lg 48 px. sm juga memakai ukuran font/padding library yang lebih padat. Badge bukan target sentuh: ukuran mengatur tipografi 11/12/14 px. Card/Panel dan overlay mengatur padding 16/20/24 px. Dialog mengatur batas lebar 24/32/40 rem. Drawer sm 20 rem; md/lg dibatasi 22.5 rem (360 px) sesuai kontrak, dengan padding lg lebih luas. Batas viewport tetap didahulukan. Dialog/Drawer tidak mengekspos ref imperatif; kendalikan open dari parent.

Tone bersama: neutral, info, success, warning, error. `invalid`, error yang berisi pesan, atau aria-invalid=true memilih modifier error untuk field. aria-describedby existing digabungkan dengan ID hint/error. Loading menonaktifkan kontrol, memasang aria-busy, dan menampilkan indikator pada Input/Select/Checkbox/Textarea. Disabled native mencegah aksi serta mempunyai warna terbaca sendiri. Readonly tetap focusable dan dapat disalin.

Alert memakai pola pesan semantik sesuai referensi pengguna: surface soft tema, border aksen awal 4 px, radius khusus `--tt-radius-alert` 12 px, padding 16 px, dan gap 12 px. Ikon status berada dalam bingkai bulat 32 px melalui `--tt-alert-icon-size`, dengan glyph SVG 18 px. Netral memakai simbol pesan, info huruf i, sukses centang, peringatan tanda seru, dan error silang. Warna ikon/border mengikuti tone; judul dan isi memakai foreground tema. Ikon dekoratif aria-hidden tidak menjadi target fokus atau announcement terpisah. Teks serta status pesan tetap harus jelas tanpa bergantung pada warna/ikon saja.

Bingkai ikon memakai ripple statis dua lapis: cincin luar soft selebar 4 px (campuran tinta tone 10% dan surface tone), dengan lingkaran dalam lebih tegas (tinta tone 20%). Glyph memakai tinta tone solid tanpa opacity. Total diameter tetap 32 px; glyph tetap 18 px. Tidak ada pulse, animasi, transisi, atau efek hover pada ikon. Ini menggantikan outline solid tipis awal sesuai koreksi referensi pengguna, dan berlaku pada semua tone serta kedua tema.

Grid Alert menempatkan ikon di samping teks yang dapat membungkus; action opsional berada di baris berikut sejajar teks. Container query memindahkan teks/action ke lebar penuh di bawah ikon jika ruang isi Alert kurang dari 11rem, termasuk saat teks diperbesar. Tidak ada tinggi tetap atau pemotongan pesan. Pola berlaku untuk Alert berjudul maupun tanpa judul, termasuk hasil validasi dan feedback lokal. Semantik role/announce dan callback aksi tetap mengikuti pemakai. Kustomisasi ini berada pada wrapper Alert bersama; Badge dan varian field tidak terpengaruh.

Dialog/Drawer meminta penutupan melalui onOpenChange(false); parent dapat menahan perubahan ini untuk konfirmasi draft. onCancel dapat membatalkan Escape melalui preventDefault. Native close event tetap disinkronkan; event close lama setelah reopen diabaikan. Tombol Tutup bukan submit form. actions tidak dibungkus form otomatis sehingga form isi tidak menjadi nested form. Pemakai yang menjalankan native close lewat method=dialog tetap harus menerima sinkronisasi state; gunakan callback terkontrol untuk kebijakan pembatalan.

Klik/tap backdrop meminta penutupan hanya jika pointer utama dimulai dan diakhiri di luar panel. Klik di dalam panel, klik kanan, pointer yang dibatalkan, dan drag melintasi batas panel tidak menutup overlay. Handler onClick/onPointerDown/onPointerCancel pemakai tetap dipanggil; preventDefault pada onClick atau onPointerDown membatalkan penutupan backdrop. Jalur ini memakai onOpenChange(false) yang sama sehingga animasi keluar dan pengembalian fokus tetap mengikuti kontrak native.

Backdrop Dialog/Drawer memakai token overlay gelap tema: rgba(15,23,42,0.60) pada terang dan rgba(6,9,15,0.72) pada gelap. Blur tipis 4 px memakai token bersama `--tt-overlay-blur`, mengikuti prototype dan DESIGN.md. Backdrop native diaktifkan dengan display block; background elemen dialog dibuat transparan untuk menggantikan scrim bawaan daisyUI, sehingga lapisan gelap tidak bertumpuk. Blur hanya pada backdrop; panel/isi tetap memakai surface opaque. Browser tanpa dukungan backdrop-filter tetap mendapat lapisan gelap sebagai fallback.

Motion Dialog memakai fade dan scale 0.96 ke 1 selama 200 ms; Drawer memakai fade dan slide dari sisi start/end selama 280 ms. Backdrop memudar dengan durasi yang sama, menggunakan easing cubic-bezier(0.4,0,0.2,1). Alias durasi/easing berada di tokens.css. Override ini mereset translate/scale individual vendor agar transform panel mempunyai satu pengarah.

`@starting-style` menetapkan frame awal setiap pembukaan. Transisi discrete display/overlay mempertahankan render dan top layer sampai exit selesai meskipun native close sudah dijalankan. Callback close/focus return tetap mengikuti dialog native, tanpa timer JavaScript. Browser tanpa dukungan transisi discrete tetap dapat membuka/menutup modal secara native, tetapi exit dapat langsung selesai. `prefers-reduced-motion: reduce` menonaktifkan transisi panel, container dan pseudo-element backdrop. Pendekatan native mengikuti [panduan animasi dialog MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog#animating_dialogs).

## Token dan urutan style

**Soft gelap transparan (revisi terbaru 28 Oktober 2026):** background shade950 opaque diganti warna shade500 dengan alpha: blue500/14%, green500/14%, yellow500/12%, red500/14%. Token memakai `rgb(... / alpha)`, setara konsep utility Tailwind `bg-blue-500/14`, agar konsisten pada Alert, Button soft, Badge dan StatusBadge. Yellow memakai alpha sedikit lebih rendah karena luminansinya lebih tinggi. Teks/ikon tetap shade400 dengan opacity penuh; tidak memakai opacity pada seluruh elemen. Hover soft mencampur tinta 10% pada background untuk feedback. Warna akhir dikompositkan dengan surface di belakangnya sehingga kontras harus diperiksa terhadap hasil komposit. Soft terang tetap shade50/700, solid mengikuti kontrak sebelumnya.

**Koreksi terbaru atas permintaan pengguna (28 Oktober 2026):** solid success tetap green600 #16a34a tetapi content menjadi putih; warning solid memakai yellow500 #eab308 dengan content putih di kedua tema. Mapping soft terang tetap 50/700. Soft gelap mengikuti referensi: blue950 #172554 / blue400 #60a5fa; green950 #052e16 / green400 #4ade80; yellow950 #422006 / yellow400 #facc15; red950 #450a0a / red400 #f87171. Ini menggantikan teks solid gelap dan soft 50/700 pada dark mode dalam kontrak sebelumnya. Hover/active solid memakai fill solid dicampur hitam 10% dan tetap putih, tidak memakai tinta soft400 sebagai fill. Content token juga berlaku pada Badge solid dan kontrol terpilih daisyUI.

Pilihan putih di atas success600 dan warning500 mengikuti arahan visual pengguna: rasio 3.30:1 dan 1.92:1. Keduanya tidak memenuhi AA untuk teks normal; warning juga tidak memenuhi rasio teks besar. Hasil ini dicatat sebagai batas aksesibilitas, bukan diklaim PASS kontras. Soft tetap memakai pasangan tinta/latar terpisah.

**Kontrak warna terbaru (28 Oktober 2026, menggantikan mapping warna sebelumnya):** solid semantik memakai shade 600, soft memakai shade 50 untuk background dan 700 untuk tinta, pada kedua tema sesuai permintaan pengguna. Info blue: #2563eb / #eff6ff / #1d4ed8; success green: #16a34a / #f0fdf4 / #15803d; warning yellow: #ca8a04 / #fefce8 / #a16207; error red: #dc2626 / #fef2f2 / #b91c1c. Urutan nilai: solid/background soft/tinta soft. Netral mengikuti surface/muted tema. Solid blue/red memakai putih, green memakai #052e16, yellow #0f172a agar kontras tidak dikorbankan demi teks putih. Hover/active solid memakai shade 700 dan teks putih. Alert dan Badge soft memakai tinta 700, termasuk pada dark mode di atas surface 50. Toast tetap kartu netral terpisah.

Button kini menerima `appearance="solid" | "soft" | "outline"`. Default secondary soft abu-abu panel/foreground tanpa border; appearance outline memakai surface tema dengan teks foreground dan border line netral tipis sesuai gambar referensi. Primary dan ghost tetap mengikuti hierarki existing. Tone semantik memakai modifier daisyUI; override appearance mengecualikan disabled. Ukuran/keyboard/fokus mengikuti Button bersama. Contoh outline teks/ikon dan empat soft tone tersedia pada galeri starter.

Revisi Alert 28 Oktober 2026: hanya border aksen awal 4 px yang dipertahankan. Border atas/bawah/akhir dihapus. Shadow bersama `--tt-alert-shadow` memakai offset 0/2 px, blur 6 px, warna slate opacity 6% pada terang dan hitam 18% pada gelap untuk pemisahan surface yang halus. Radius 12 px dan ripple ikon statis tetap mengikuti kontrak Alert. Mode forced colors mempertahankan border sistem sebagai fallback aksesibilitas.

Warning produksi (28 Oktober 2026) memakai tiga peran warna bersama: tinta `--warning` (#805b00 terang, #f5c451 gelap), fill solid `--warning-solid` (#f5b932 terang, #f5c451 gelap), dan content solid `--on-warning` (#172b46). `--color-warning`/content daisyUI memakai pasangan solid sehingga berlaku pada Button, Badge solid, dan kontrol terpilih. Alert, Badge soft/outline, StatusBadge warning dan ikon memakai tinta serta surface soft (#fff8e1 / #302918). Border Input/Select/Textarea/Checkbox warning memakai tinta untuk tetap terlihat di surface; disabled/readonly/invalid tetap mengungguli warning. Tidak ada token warna khusus tombol.

Palette merek tidak diubah. Semantic info/success/warning/error daisyUI memetakan tinta status + content yang cocok untuk varian solid. Info gelap memakai canvas sebagai content agar kondisi hover tetap melampaui 4.5:1. Soft Badge/Alert memakai token background status existing. Primary memakai foreground/canvas; warna primary merek tetap menjadi aksen/fokus. Secondary tetap surface/foreground dengan border control.

Alias tt-* pada tokens.css memusatkan radius, padding, tinggi target, focus ring, dan lebar overlay. Radius: tombol 8 px, Input/Select 18 px melalui `--tt-radius-field`, Textarea multiline 16 px melalui `--tt-radius-textarea`, card mandiri 16 px, panel/dialog 24 px, badge pill. Readonly, disabled, loading dan invalid mempertahankan radius komponen yang sama. Surface isi langsung di dalam Panel memakai radius turunan `--tt-radius-panel-inner`: radius panel dikurangi `--tt-panel-inset`, yaitu 24 - 4 = 20 px. Padding luar memakai token inset yang sama agar lapisan merata pada sisi dan sudut; perubahan radius panel/inset otomatis memperbarui radius isi. Selector radius global daisyUI tidak dipaksakan menjadi pill karena juga digunakan oleh checkbox.

Vendor versi ini mengeluarkan komponen dalam nested utility layers. Override domain berada tanpa sublayer di layer utilities. Pemisahan berikut mencegah tone/state tertimpa:

1. Base tt-control/tt-button mengatur geometri, bentuk, shadow, dan transisi yang diperlukan.
2. Warna netral field hanya berlaku pada data-tone=neutral yang aktif dan tidak invalid. Warna secondary/ghost hanya berlaku pada varian itu dan tidak disabled.
3. Modifier library menentukan warna status field/solid button. Badge/Alert soft/outline memakai pasangan token status yang dipilih melalui data-tone.
4. Disabled diatur terpisah, tanpa opacity rendah. Readonly juga mempunyai treatment tersendiri. Pesan error tidak dijadikan bagian dari style disabled kontrol.
5. Focus ring berukuran 3 px/offset 3 px. Default memakai aksen; Input/Select/Textarea/Checkbox dengan tone error atau aria-invalid=true memakai danger melalui token lokal `--tt-field-focus`. Disabled dikecualikan dari override error. Select juga memakai ring yang sama pada focus/focus-within/open, karena saat picker native terbuka fokus dapat berpindah ke option dan focus-visible pada select tidak selalu aktif. Ring tidak mengubah border tone/invalid. Tombol hanya mentransisikan transform agar perpindahan tema tidak melintasi pasangan warna berkontras rendah.

## Contoh pemakaian

### Tabs

Revisi motion konten: panel memakai crossfade opacity 220 ms ease-in-out, tanpa translate. Grid menempatkan panel keluar/masuk pada area yang sama selama fade; transisi display allow-discrete menunda penyembunyian visual panel lama sampai exit selesai, dan starting-style menyediakan frame awal opacity 0 untuk panel masuk. Panel nonaktif langsung hidden/inert/aria-hidden agar tidak menerima fokus atau announcement selama exit. Reduced motion mematikan transisi; browser tanpa dukungan transisi discrete tetap berpindah panel tetapi fade keluar dapat langsung selesai. Motion ini menggantikan fade/translate 180 ms sebelumnya; penanda tab tetap bergerak 300 ms.

`TabItem` berisi `value` unik/stabil, `label: ReactNode`, `content: ReactNode`, dan `disabled?`. `Tabs` menerima nama aksesibel `label`, `items`, `defaultValue` untuk uncontrolled, atau `value` dan `onValueChange` untuk controlled. Pilihan yang tidak ditemukan/nonaktif fallback ke tab aktif pertama; semua nonaktif/daftar kosong tidak memilih panel. Konten tetap mounted dengan hidden agar nilai field bertahan, tetapi panel nonaktif tidak tampil dan tidak masuk urutan fokus.

Track netral abu-abu radius 8 px/padding 4 px; penanda surface radius 6 px dengan shadow tipis bergerak 300 ms ease-out. Tab minimum 44 px dengan teks 14 px. ResizeObserver mengukur posisi/ukuran tombol sehingga marker selaras setelah resize, perubahan label/font dan tema. Ukuran/posisi marker merupakan nilai layout dinamis, bukan style statis di JSX. Panel masuk fade/translate 3 px selama 180 ms; reduced motion meniadakan gerak. Scroll horizontal dibatasi region tab untuk label panjang, tanpa membuat halaman melebar.

Semantik tablist/tab/tabpanel memakai useId untuk relasi id/aria-controls/aria-labelledby. Satu tab terpilih berada pada urutan Tab; panah kiri/kanan memindahkan fokus sekaligus memilih (mengikuti direction RTL), Home/End memilih ujung aktif, disabled dilewati. Enter/Space tetap memakai klik button native. Fokus terlihat; marker dekoratif tidak menerima interaksi. Tidak ada Alpine atau global event. Gaya segmented ini berlaku untuk komponen Tabs berdasarkan referensi pengguna; chart tabs bergaris bawah pada prototype tetap mengikuti kontraknya sendiri.

```tsx
<Tabs label="Pengaturan lokal" defaultValue="profile" items={[
  { value: "profile", label: "Profil", content: <ProfileForm /> },
  { value: "preferences", label: "Preferensi", content: <Preferences /> },
]} />
```

### Toast

#### Action dan promise

`action.onClick` menerima callback sync atau async. Tombol memakai loading/disabled selama promise aksi berjalan dan mengunci klik ganda. Default menutup setelah berhasil; `closeOnClick: false` mempertahankan Toast. Jika callback throw/reject, Toast tetap terbuka dengan pesan error lokal dan tombol bisa dicoba ulang. Pesan beraksi default persisten. Menutup Toast tidak membatalkan pekerjaan async; pembatalan request tetap tanggung jawab pemakai.

`toast.promise<T>(task, options)` menerima `Promise<T>` atau factory `() => Promise<T>`, lalu mengembalikan `{ id, promise: Promise<T> }`. `options` berisi `loading`, `success`, `error`, serta `position?`/`duration?`. Pesan dapat berupa string atau objek opsi Toast; success/error juga dapat berupa formatter data/error. Loading memakai spinner, aria-busy dan durasi 0. Hasil memperbarui ID yang sama, tone success/error dan timer terminal baru (default 5 detik, atau persisten untuk konten/aksi). `duration` pada pesan terminal mengungguli durasi umum. Formatter yang gagal memakai pesan fallback; hasil operasi asli tetap dipertahankan.

Promise hasil mengembalikan data asli atau reject dengan error asli; pemakai yang await tetap harus try/catch. Handler internal mencegah unhandled rejection ketika hasil hanya dipakai untuk notifikasi. Toast yang dismissed atau provider unmounted tidak dimunculkan kembali oleh hasil terlambat. Tidak ada pembatalan otomatis, retry request otomatis atau penggantian hasil gagal dengan sukses.

```tsx
const { toast } = useToast();
toast({ title: "Periksa hasil", action: {
  label: "Buka", closeOnClick: false, onClick: async () => { await openResults(); },
} });
const { id, promise } = toast.promise(() => saveChanges(), {
  loading: "Menyimpan…",
  success: data => ({ title: "Tersimpan", description: data.message }),
  error: { title: "Gagal menyimpan", description: "Periksa koneksi lalu coba lagi." },
});
try { const data = await promise; /* gunakan hasil aktual */ }
catch { /* tampilkan recovery inline jika diperlukan */ }
// dismiss(id) hanya menutup notifikasi, tidak membatalkan saveChanges.
```

Koreksi tombol tutup Toast: glyph 14 px dengan permukaan hover/fokus bulat berdiameter 28 px. Hit area transparan tetap 44 x 44 px, border-radius 50%, focus ring keyboard tetap tersedia. Background persegi hover Button ghost dinetralkan secara lokal melalui selector tt-toast-close.

`ToastProvider` dipasang sekali di root layout. Client Component memakai `useToast()` yang mengembalikan `toast(options)`, `dismiss(id)` dan `dismissAll()`. `toast` mengembalikan ID. Opsi: `title` wajib berupa string, `description`, `tone` netral/info/success/warning/error, `position` top/bottom-left/center/right (default top-right), `duration` dalam ms (default 5000, 0 persisten), `content` berupa ReactNode, dan `action: { label, onClick }`. Konten/aksi custom default persisten. Tidak ada Alpine, window.toast, CustomEvent atau penyisipan HTML mentah.

Provider menerima `layout="stacked"` (default) atau `"expanded"`. Tiap posisi mempunyai tumpukan independen, terbaru di depan. Hover/fokus membentangkan daftar; tombol Bentangkan tersedia bagi keyboard dan layar sentuh. Pesan di belakang tumpukan bersifat inert dan timer dijeda hingga terlihat. Timer juga berhenti selama hover/fokus pada region atau tab browser tersembunyi, lalu melanjutkan sisa durasi. Tidak ada batas antrean yang membuang pesan diam-diam. Daftar expanded dapat digulir jika melebihi tinggi viewport.

Toast menggunakan struktur presentasi sendiri, bukan komponen Alert: container `toast`/placement daisyUI, kartu surface netral selebar 352 px yang mengikuti viewport, border line tipis, radius 8 px, shadow 0 4px 14px hitam 8%. Ikon solid 18 px sejajar judul 13 px/weight 500; deskripsi 12 px sejajar teks judul, tanpa ripple atau aksen kiri Alert. Default/netral tanpa ikon sesuai referensi. Tinta judul foreground dan deskripsi muted; warna status hanya pada ikon. Close selalu terlihat dengan target 44 px di dalam kartu.

ResizeObserver mengukur tinggi masing-masing kartu termasuk konten custom. Posisi tumpukan memakai transform: kartu belakang bergeser 8/16 px dan scale 0.97/0.94; expanded memakai jumlah tinggi kartu ditambah gap 12 px. Transform/tinggi region bertransisi 220 ms; surface masuk/keluar 200 ms, arah mengikuti atas/bawah. Reduced motion meniadakan animasi/transisi. Override placement lebih spesifik menahan width/inset/translate vendor agar kartu tidak menyusut menjadi selebar tombol expand. Pemunculan tidak memindahkan fokus; penutupan lewat kontrol Toast mengembalikan fokus ke pemicu bila masih tersedia. Announcement teks terpisah: status polite untuk pesan biasa, alert untuk error, ikon dekoratif. Toast merupakan pendamping hasil inline sesuai DESIGN.md. Overlay native tetap berada pada top layer; hasil penting di dialog harus tersedia inline di dialog itu sendiri.

```tsx
const { toast } = useToast();
toast({ title: "Pemeriksaan selesai", description: "Hasil contoh lokal tersedia.", tone: "success" });
toast({ title: "Perlu diperiksa", tone: "warning", duration: 0,
  action: { label: "Lihat hasil", onClick: () => setResultsOpen(true) } });
```

```tsx
"use client";

import { useState } from "react";
import { Button, Dialog, Input, Panel, StatusBadge } from "@/components/ui";

export function Example() {
  const [open, setOpen] = useState(false);
  return <Panel title="Pemeriksaan lokal">
    <StatusBadge status="unknown">Belum terhubung</StatusBadge>
    <Button onClick={() => setOpen(true)}>Buka pemeriksaan</Button>
    <Dialog open={open} onOpenChange={setOpen} title="Pemeriksaan">
      <Input label="Nama pemeriksaan" hint="Contoh lokal." />
    </Dialog>
  </Panel>;
}
```

Field dengan pesan error otomatis invalid. Tetap berikan validasi server pada fase integrasi; perubahan border bukan validasi backend. State Table dipilih dari hasil request/filter, bukan dari child count tersembunyi. Kegagalan API tidak boleh diganti contoh sukses. Pilihan status pada halaman pemeriksaan hanya menguji varian, bukan metrik/kondisi layanan.

## Validasi

Token teks/surface semantik mengikuti palette prototype pada kedua tema. `accent-solid`, `success-solid`, dan `danger-solid` memisahkan fill varian solid daisyUI dari tinta semantik; selector hover solid membaca token fill tersebut. Netral/outline tidak boleh menimpa status berwarna. Urutan layer CSS eksplisit: theme, base, vendor, components, utilities, sehingga style vendor OverlayScrollbars dapat dikustomisasi token tema.

Koreksi fidelitas shell/Overview menambahkan `Icon`, `ThemeToggle`, `ScrollArea` dan `Tooltip` (popover manual dengan hover/fokus/Escape). `ScrollArea` kini memakai OverlayScrollbars React: props label, axis vertical/both, className, refreshKey; autoHide leave 700 ms, focus keyboard mempertahankan thumb, update setelah drawer/ukuran berubah. `Tabs` menerima appearance segmented/underline. `Table` menerima captionHidden agar caption tetap aksesibel tanpa baris visual tambahan. `Dialog`/`Drawer` menerima headerContent dan closeIcon. Overlay native mengunci scroll halaman. Lihat [migrasi tabel/scroll](admin_table_scroll_migration.md) untuk API dan bukti terbaru.

Build/lint/typecheck dan hasil browser untuk revisi ini dicatat di [laporan fondasi komponen fase 2](admin_ui_components_review.md). Source prototype dipertahankan. Bukti ini belum membuktikan migrasi halaman, BFF, otorisasi, atau integrasi backend selesai.
