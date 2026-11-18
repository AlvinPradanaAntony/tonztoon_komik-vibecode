# Empty state reusable

Komponen `web/src/components/ui/empty-state.tsx` menampilkan ikon existing, judul, deskripsi dan aksi opsional di tengah. Props `illustration` dapat menggantikan ikon dengan visual dekoratif; `size` sm/md mengatur ruang. `announce` menambahkan role status tanpa autofocus. Visual tidak dianimasikan.

Pemakaian: seluruh tabel reusable menerima `emptyState` untuk kustomisasi; default membedakan filter tanpa hasil dengan data yang belum tersedia. Starter memakai search untuk pencarian dan overview untuk daftar modul; Reset tabel memulihkan query/state. Overview memakai health untuk environment/rentang yang belum memiliki data. Loading dan error tetap terpisah.

Empty state tabel berada di luar viewport horizontal, dengan baris kosong semantik di dalam tabel. Ini menjaga posisi tengah berdasarkan lebar panel yang terlihat, bukan keseluruhan lebar kolom.

## Validasi

- PASS: `npm run lint`, `npm run typecheck`, `npm run build`.
- PASS: browser starter pencarian tanpa hasil menampilkan satu empty state dan satu tombol Reset tabel. Enter pada Reset tabel mengembalikan dua baris pertama serta pagination; hasil dikonfirmasi melalui accessibility tree. Kondisi Kosong eksplisit tanpa query menampilkan ikon modul dan teks berbeda. Navigasi Tab menuju Reset tabel menampilkan ring fokus.
- PASS: tema terang dan gelap ditinjau pada desktop. Pada emulasi mobile 375 px, dokumen 375 px, empty state lebar 295 px mulai x=40, selisih pusat ikon terhadap container 0 px.
- PASS: contrast-check.py untuk deskripsi/surface terang 7.58:1, gelap 9.52:1. Ikon/surface terang 6.47:1, gelap 6.45:1. Judul memakai foreground tema yang lebih kontras.
- Bukti [desktop gelap](screenshots/admin-empty-state/dark-desktop.png), [kondisi kosong terang dengan fokus keyboard](screenshots/admin-empty-state/light-desktop.png), dan [viewport mobile gelap](screenshots/admin-empty-state/dark-mobile.png). Screenshot mobile diambil dari bagian atas halaman; seluruh empty state berada lebih bawah. Override viewport pengujian telah dikembalikan ke ukuran normal.

Browser beberapa kali timeout pada dispatch/CDP. Matriks viewport penuh, teks 200%, visual ilustrasi custom, serta click-through baru untuk empty Overview belum selesai diperiksa. Tidak ada klaim pengujian backend atau console bersih; badge issues browser terlihat pada screenshot.

## Delivery Gate Anti-slop, lingkup komponen

- **Hard Gate PASS:** UI dibangun dan dijalankan; pencarian/reset berfungsi, status kosong berbeda dari error/loading; kontras terukur; mobile tidak melebar; ikon existing atas permintaan pengguna; tidak menambah navigasi, statistik atau klaim produk. Keyboard Enter pada aksi baru terverifikasi, tanpa autofocus.
- **Purpose Gate PASS:** search menjelaskan hasil pencarian kosong, overview menjelaskan daftar modul, health menjelaskan belum adanya observasi. Tidak memakai gambar generik, gradien, glow atau animasi dekoratif.
- **Liveliness PASS:** ENERGY 2 / RHYTHM 2 / MOTION 1 existing dipertahankan. Ikon 56 px dan judul terpusat membentuk fokus lokal, sedangkan deskripsi serta aksi membantu pemulihan. Tidak ada perubahan shell atau token global.
- **Craftsmanship PASS:** satu primitive bertipe, props native diteruskan, visual dekoratif disembunyikan dari accessibility tree, layout memakai tinggi minimum dan teks membungkus; center mobile diukur 0 px. Batas pengujian tambahan dicatat di atas dan tidak dinyatakan PASS.
