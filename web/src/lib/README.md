# Batas modul aplikasi

- `server/`: konfigurasi server, session store, enkripsi, pemeriksaan izin, dan client backend. Modul yang membaca secrets wajib mengimpor `server-only`. Belum diimplementasikan pada fase 1.
- `monitoring/`: tipe snapshot, filter, metrik, serta pengendalian SSE/polling.
- `runtime-logs/`: event tersanitasi, buffer/cursor, dan proyeksi Terminal/Terstruktur.
- `comic-preview/`: run diagnosis, handle gambar opaque, pembatalan, dan korelasi.
- `admin-data/`: kontrak resource, ETag, idempotensi, dan hasil mutation.
- `diagrams/`: manifest topology/schema bersama. Controller serta viewport Data Flow dan ERD tetap terpisah.

Folder domain masih berupa tempat implementasi fase 2/3. Berkas `.gitkeep` bukan endpoint atau fitur. Jangan membuat fallback data contoh untuk menutupi kegagalan integrasi produksi.

Layout/page menggunakan Server Components. Interaksi browser diisolasi dalam Client Components. BFF nantinya menggunakan Route Handlers runtime Node.js, memeriksa sesi/izin, memvalidasi target dari allowlist server, dan mengirim respons private/no-store. Token, URL bertoken, dan credential database tidak boleh menjadi props Client Component atau variabel `NEXT_PUBLIC_*`.
