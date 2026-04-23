# PRD_TonzComic

# **Product Requirements Document (PRD): 
Project "TonzToon Comic"**

> **Produk**: Aplikasi mobile baca komik (manga, manhwa, manhua)
> 
> 
> **Platform:** Android & iOS (Flutter)
> 
> **Data**: Rest API
> 

---

## 1. Overview

---

Aplikasi mobile native (Flutter) ini bertujuan untuk dapat membaca komik (Manga, Manhwa, Manhua) dengan pengalaman pengguna yang mulus. 

**TonzToon Comic** adalah aplikasi baca komik yang mengutamakan:
- **Discover cepat
-** Multi Source 
- **Reader nyaman (default Vertical/Webtoon)** dengan opsi **Manga Mode (Paged/Page Style)** melalui **button toggle**, sehingga pengguna bebas memilih format membaca.
- **Progress & Continue Reading** yang akurat
- **Sync Progress & Library** lintas perangkat menggunakan **sistem auth postgresql (supabase) dan RLS**.
- **Library** (Bookmarks, Collections/Koleksi, Favorite Scenes, History, Downloads)
- **Download offline** per chapter / batch: file tersimpan local; saat login, offline wishlist tersinkron ke cloud.

Tujuan utama aplikasi adalah menyediakan platform berbasis mobile untuk membaca komik  (Manga, Manhwa, Manhua) dari berbagai source sehingga pengguna mendapatkan banyak katalog komik secara penuh dan dapat berinteraksi lintas source. 

> Multi Source yang tersedia : Komiku, Komiku Asia, Komikcast, dan Shinigami
> 

---

## 2. Problem Statement

Pengguna membutuhkan aplikasi baca komik yang:
1) Cepat dan stabil di jaringan lambat/putus-putus

2) Reader cocok untuk berbagai format (vertical/webtoon style vs paged)

3) Mudah menemukan judul dan melanjutkan bacaan terakhir

4) Bisa membaca offline untuk chapter atau batch komik yang diunduh

5) Mendukung sesi baca maraton (binge reading) yang minim interupsi dengan kontrol user (Binge Mode ON/OFF / auto-next).

6) Mencari komik dengan lintas 4 source baik Manga, Manhwa, Manhua

---

## 3. Goals, Success Criteria

### 3.1 Goals (MVP)

- Login/Register with Email/Passwort auth supabase dan Google OAuth untuk identitas user (Dapat menjadi guest + opsi sign-in)
- **Cloud sync** untuk **progress + library**
- Browse katalog + detail komik + daftar chapter + chapter reader
- Search + filter + sort
- Reader (vertical & paged) dengan penyimpanan progress
- Simpan progress “Continue/lanjut baca”
- Library (Bookmarks, Collections/Koleksi, Favorite Scenes, History, Downloads)
- Download offline batch (full chapter atau 1 judul komik) / per chapter (queue sederhana)

### 3.2 Success Criteria (MVP)

- Pengguna dapat: **Home → Detail → Baca → Progress tersimpan → Continue Reading muncul → Download → Baca offline**
- Stabilitas: tidak crash saat rotate, background/resume

---

## 4. Target Users & Personas

1. **Reader Harian**: baca rutin, butuh Continue Reading + update chapter + library rapi + notifikasi
2. **Binge Reader**: maraton judul, auto-next chapter, scroll halus
3. **Kolektor**: simpan banyak judul, tracking progress, filter/sort library

---

## 5. Scope & Features (MVP)

### 5.1 Onboarding

- Splash → cek config & cache → cek permission
- Pilih Tema (dark mode / light mode)
- Guest mode (default) + login/register

> **Acceptance Criteria**
- Aplikasi bisa dipakai tanpa login (Guest).
- **Guest:** library, progress, download offline disimpan lokal
- L**ogin:** app menawarkan **migrasi** (progress + library + **Offline Wishlist**) ke cloud via db; menjadi **cloud-first**. 
- **Download Offline (Offline Manifest+ file)** tetap **lokal**
> 

### 5.2 Information Architecture (Bottom Navigation Bar)

- **Home**
- **Search**
- **Library**
- **Settings**

---

## 6. Functional Requirements (FR)

Format ID: **FR-XX** (Functional) dan **AC-XX** (Acceptance Criteria).

### 6.1 Home / Discover

**FR-01** Menampilkan section: Continue Reading, Trending/popular, New Releases, Recommended **(dummy rule-based)**, Genre/tags shortcut.

**AC-01a** Klik item membuka Comic Detail.

**AC-01b** Home tampil < 2 detik (mock/cache).

**FR-02** Continue Reading hanya muncul bila ada progress tersimpan.

**AC-02** Item Continue Reading membuka reader tepat pada chapter & posisi terakhir.

**FR-03** Home mendukung **Pull-to-Refresh** untuk memperbarui data (Continue Reading + sections/data komik).

**AC-03** Saat user pull-to-refresh, tampil indikator loading dan berhasil memperbarui data.

**AC-03a** Refresh sukses, konten Home ter-update tanpa mengubah navigasi; jika gagal (offline/timeout), tampil pesan ringan (toast/snackbar) dan **tetap tampilkan data terakhir dari cache/local**.

### 6.2 Search & Browse

**FR-04** Pencarian berdasarkan judul/author.

**AC-04** Mengembalikan hasil real-time (Debounce 300ms); hasil bisa kosong dengan empty state jelas.

**FR-05** Filter: type/format, genre, status, rating, author, artist; Sort: Popular, update/latest, A–Z/Z-A

**AC-05** Filter/sort tersimpan selama sesi (in-memory) dan bisa di-reset.

### 6.3 Comic Detail

**FR-06** Menampilkan metadata: cover, title, synopsis, type, genre/tags,  ,author/pengarang, released, rating, update info, status

**AC-06** Metadata Comic Detail tampil lengkap sesuai data (cover, title, synopsis, type, genre/tags, author, rating, status, update info) + fallback/empty state jika ada field kosong.

**FR-07** Comic Detail menampilkan CTA utama dan CTA sekunder berikut (sesuai state user): **Read/Continue, Bookmark, Collection/Koleksi, dan Download Komik (Batch)**.

**AC-07** CTA di Comic Detail **(Bookmark/Collection/Download)** menampilkan state yang sesuai data user **(toggle/add/remove/status downloaded)**.

**AC-07a** CTA utama: **Read** jika belum ada progress, **Continue** jika ada progress.

**AC-07b** **Read** membuka chapter awal; **Continue** membuka chapter terakhir dan posisi terakhir sesuai progress (Vertical → `scrollOffset`, Paged → `pageIndex`).

**AC-07c** CTA sekunder tersedia dan stateful: **Bookmark (toggle), Collection/Koleksi (add/remove atau pilih folder), dan Download Komik (Batch)**.

**AC-07d** **Collection/Koleksi** user dapat memilih satu/lebih koleksi (multi-select via bottom sheet / dialog). Status koleksi ditampilkan sebagai checklist.

**AC-07e** Jika user belum punya koleksi, tersedia aksi **Create Collection/Folder** (nama folder) lalu komik langsung masuk ke folder tersebut dan tersimpan pada library; Nama koleksi unik per user (case-insensitive) dan tidak boleh kosong.

**AC-07f** **Download Batch** dapat menjalankan antrian unduhan untuk semua chapter (atau opsi pilih rentang chapter) secara massal, menampilkan status minimal: **pending/downloading/completed/failed**, dan dapat dibatalkan minimal per batch.

**AC-07g** Download Batch hanya tersedia jika ada chapter list sudah termuat; jika tidak, tampil loading/disabled state.

**AC-07h** Setelah batch selesai (atau sebagian selesai), chapter yang sudah terunduh bisa dibaca offline dan status download terlihat di chapter list/detail; tampil status **partial/failed** dan user bisa retry (minimal retry per-chapter atau retry batch).

**FR-08** Daftar chapter (default terbaru di atas) dengan label badge pill NEW ,progress dan read/unread.

**AC-08** Jika ada progress, tersedia aksi **“Jump to last read chapter”** yang meng-scroll dan menyorot chapter terakhir dibaca pada daftar chapter; jika tidak ada progress, aksi tidak ditampilkan.
**AC-08a** Tampilkan progress indicator menampilkan **lastReadPageItemIndex/totalPageItems** (mis. 3/80) pada daftar chapter dan update setelah progress tersimpan.

> **Catatan**: kalau API/dummy belum menyediakan total pages per chapter, kamu perlu:
**(a)** Menambahkan `totalPageItems` pada Chapter model, atau
**(b)** Menghitung saat user membuka chapter (ambil panjang `pages.length`) saat chapter pertama kali dibuka.
> 

### 6.4 Chapter List

**FR-09** Mendukung pagination untuk chapter list.

**AC-09** Scroll mencapai bawah memuat halaman berikutnya tanpa freeze.

### 6.5 Reader (Core)

**FR-10** Mode **Vertical (default)** untuk webtoon, **tanpa jarak antar gambar** (zero gap) agar gambar tersambung mulus tanpa ada celah dan di-render menggunakan **lazy list** (`ListView.builder` / `SliverList`) agar tetap ringan untuk chapter panjang.

**AC-10** Scroll mulus; `padding = 0`; tidak ada margin antar item.

**FR-11** Reader menyediakan **overlay UI** (kontrol mengambang di atas konten komik) yang bersifat **sementara** untuk menjaga pengalaman membaca tetap immersive.

**AC-11** **Tap sekali** → overlay **muncul**. **Tap lagi / tunggu ±3 detik (inactivity) / mulai scroll (vertical) atau swipe (paged)** → overlay **hilang;** Muncul/hilang overlay **tidak mengubah posisi baca** (`scrollOffset`/`pageIndex`); Overlay **tetap tampil** selama user sedang berinteraksi dengan kontrol overlay.

**FR-12** Tersedia **Manga Mode (Paged/Page Style)** yang bisa diaktifkan melalui **button toggle** di Reader, dengan opsi **LTR/RTL**.

**AC-12** Perpindahan mode **Vertical ↔ Paged** berjalan stabil (tanpa crash), gesture swipe/zoom tetap berfungsi, dan mode yang dipilih user **tersimpan sebagai preferensi.**

**FR-13** Reader menjalankan pipeline **prefetch**: **preload** next 1 **page item (image)** (prioritas tinggi) dan **prefetch** 3–5 **page items (images)** ke depan (prioritas lebih rendah) dengan batas concurrency agar loading tidak terasa saat mendekati viewport.

**AC-13** Preload/prefetch tidak menyebabkan memory spike dan tidak mengganggu scroll (vertical) / swipe (paged); Jika gambar gagal, tampil placeholder + tombol retry; retry berjalan tanpa freeze.

**FR-14** Simpan progress membaca: `comicId` + `chapterId` + `timestamp` + posisi sesuai mode (Vertical → `scrollOffset`, Paged → `pageIndex`).

**AC-14** Reopen chapter kembali ke posisi terakhir (± satu layar / satu page).

**FR-15** Menyediakan navigasi **Prev/Next Chapter**. Selain itu tersedia **Binge Mode (ON/OFF)** melalui **button toggle** di overlay Reader. Saat **Binge Mode ON**, aplikasi mengaktifkan **auto-next chapter** untuk pengalaman maraton baca; saat **OFF**, auto-next tidak berjalan dan user berpindah chapter secara manual (Prev/Next).

**AC-15** Jika **Binge Mode ON** dan user mencapai akhir chapter, aplikasi otomatis lanjut ke chapter berikutnya (jika tersedia). Jika **Binge Mode OFF**, aplikasi tidak auto-next dan menunggu aksi user (Prev/Next).

**FR-16** Tersedia aksi **save favorite scene** pada page item (image) chapter
**AC-16** Tombol toggle **Favorite Scene** muncul saat menekan lama salah satu page item (image) chapter; saat ditekan, sistem menyimpan berbagai informasi seperti `comicId`, `chapterId`, `pageItemIndex`, `imageUrl` (atau cache key), dll; Perubahan state langsung tercermin di UI.

**AC-16a** Favorite Scene muncul atau tersimpan di Library (Favorite Scenes) dan dapat dibuka kembali (membuka chapter pada posisi page item tersebut).

> **Catatan**: untuk **mode vertical**, “**page item (image)**” jelas karena list terdiri dari item gambar.
> 

### 6.6 Library

**FR-17** Menu Library berisi: Bookmarks, Collections/Koleksi, Favorite Scenes, History, Downloads.

**AC-17** Data library tampil walau offline (local storage).

**FR-18** User bisa melihat daftar koleksi dan isi tiap koleksi (create/rename/delete); Dapat add/remove bookmark dari detail maupun library.

**AC-18** Perubahan state langsung tercermin di UI (optimistic update) dan persisten.

> **Catatan:** Favorite Scenes dibuat dari Reader (long-press/toggle pada page item), bukan dari Comic Detail.
> 

### 6.7 Downloads Offline

**FR-19** Download batch / per chapter (queue + progress + cancel) dengan status: **pending/downloading/completed/failed** dan tersedia aksi **cancel** (minimal cancel batch atau cancel per chapter).

**AC-19a** Jika app ditutup, download melanjutkan / minimal status tetap konsisten *(status tersimpan dan user bisa retry);* Setelah download selesai, chapter bisa dibaca tanpa internet.

**AC-19b** Status Download Offline disimpan lokal dan menjadi acuan “tersedia offline di perangkat ini”.

**AC-19c** Jika status **completed** tapi file lokal tidak ada (file terhapus/korup), tampil toast/snackbar: *“File offline tidak ditemukan. Silakan download ulang.”* dan menyediakan aksi **Retry Download**.

**AC-19d** Jika file hilang, status berubah ke `missing/not_available` dan memperbarui UI (mis. tombol “Download ulang”).

**FR-20** Kelola storage: hapus batch / per-chapter / clear all.

**AC-20** App menampilkan estimasi ukuran (opsional) atau minimal status downloaded.

### 6.8 Settings

**FR-21** Setting Reader: default mode, RTL/LTR, auto-next, mark read on complete.

**AC-21** Perubahan setting diterapkan di reader berikutnya.

**FR-22** Setting Data: clear cache, download hanya Wi-Fi (opsional).

**AC-22** Clear cache tidak menghapus favorites/bookmarks kecuali user memilih.

### 6.9 Authentication & Cloud Sync

**FR-23** Aplikasi menyediakan **Login** menggunakan Auth Email/Password dan Google OAuth

**AC-23** Sesi login persist saat app dibuka ulang (tidak perlu login ulang setiap kali).

**AC-23a** User dapat **logout**; setelah logout, app kembali ke mode Guest (penyimpanan full local).

**FR-24** **Progress** dan **Library** disimpan dan disinkronkan di DB berdasarkan `userId`. Perilaku penyimpanan mengikuti auth mode: **Guest → local-only**, **Login → cloud sync (DB)** untuk progress dan library. Untuk Download Offline, cloud hanya menyimpan **Offline Wishlist (intent).**

**AC-24a** Saat user membaca, progress (`comicId`, `chapterId`, `timestamp`, `scrollOffset/pageIndex`) tersimpan ke db dan dapat direstore di perangkat lain setelah login.

**AC-24b** Library state (Bookmarks, Collections/Koleksi, Favorite Scenes, History) tersimpan ke db dan tetap tersedia offline melalui mekanisme cache.

**AC-24c** Offline Wishlist dipakai untuk menampilkan item “siap di-download” di perangkat lain, **bukan** tanda bahwa file sudah tersedia offline.

**AC-24d** Saat user login pertama kali, app melakukan **one-time migration** dari local ke db untuk: progress, library dan **Offline Wishlist**.

**AC-24e** Saat user logout, app kembali ke mode Guest (local-first).

**FR-25** Setelah login, jika ada data Guest atau data lokal (progress/library/offline wishlist), tampil modal dialog migrasi di Home/Discover.

**AC-25a** Modal hanya muncul jika ditemukan data lokal yang dapat dimigrasikan(mis. ada progress/library/offline wishlist).

**AC-25b** Modal menampilkan pilihan:

- **Migrate & Sync to Cloud** (default action)
- **Skip** (tetap pakai cloud kosong / tidak mengupload data lokal)
- (opsional) **View details** (ringkasan jumlah: progress items, bookmarks, collections, offline wishlist count)

**AC-25c** Jika user memilih **Migrate & Sync to Cloud**:

- Aplikasi melakukan upload **progress + library + offline wishlist download offline** ke DB (berdasarkan `userId`).
- Setelah migrasi sukses, aplikasi **membersihkan data lokal user state** secara **bersih** (progress/library/offline wishlist). **File offline tidak dihapus.**

**AC-25d** Jika migrasi gagal (timeout/offline), tampil error + opsi retry; data lokal tidak dihapus.

---

## 7. Non-Functional Requirements (NFR)

**NFR-01 Reliability**: aman saat rotate, background/resume, low memory.

**NFR-02 Offline-first**: library/progress tersedia offline.

**NFR-04 Accessibility**: font scaling, dark mode, tap targets memadai.

**NFR-05 Security/Privacy**: progress & library tersimpan aman di db per `userId` (rules: hanya user yang dapat baca/tulis datanya). Downloads (file) tetap local pada device. Minim data personal; mode guest didukung.

---

## 8. Data Model (API-ready)

### 8.0 Storage Split (by Auth Mode)

**Guest Mode (Local-First, tanpa login):**

- **Local (device) adalah source of truth** untuk progress, library (bookmarks/collections/favorite scenes/history), **Download Offline (Offline Manifest + Offline File)**

**Logged-in Mode (Cloud-First):**

- **Cloud (DB) adalah source of truth** untuk progress, library (bookmarks/collections/favorite scenes/history), dan Offline Wishlist.

> **Catatan penting:** **Download Offline (Offline Manifest + Offline File) tetap lokal**, sehingga device lain perlu download ulang meskipun wishlist tersinkron.
> 

---

## 9. Technical Architecture

### 9.1 Flutter Stack (Rekomendasi)

- State: Riverpod (AsyncValue)
- Routing: go_router
- Image cache: cached_network_image
- Auth: Auth Supabase (Email/password) dan Google OAuth
- Cloud DB: security rules/rls berbasis `userId`
- Local storage: Hive
- Local downloads: simpan file chapter di **app documents directory** (path provider) + metadata queue/status di Hive.
- Download manager: implement sederhana + isolate jika dibutuhkan
- Reader rendering: `CustomScrollView + SliverList`
- Prefetch: `precacheImage` / strategi prefetch terbatas (3–5 item) + `ScrollController` untuk deteksi posisi

### 9.2 Error & Empty States (Wajib)

- No internet (fallback cache)
- Timeout + retry
- Image gagal load (placeholder + retry)
- Empty state (search kosong, library kosong)

---