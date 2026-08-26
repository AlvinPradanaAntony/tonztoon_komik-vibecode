# Audit Performa dan Kualitas Backend

Tanggal audit: 2 Juni 2026
Ruang lingkup: `backend/app`, `backend/scraper`, `backend/scripts`, model SQLAlchemy, migration Alembic, dan database Supabase terhubung.
Metode: audit statis codebase ditambah inspeksi read-only Supabase MCP: advisor, schema, extension, ukuran tabel, `pg_stat_statements`, statistik scan, policy RLS, log PostgreSQL, dan `EXPLAIN` estimasi. Audit ini tidak mengubah schema atau data dan belum menjalankan `EXPLAIN (ANALYZE, BUFFERS)` maupun load test terhadap database produksi.

Catatan status: snapshot `chapter_image_jobs` di bawah adalah historis. Queue
browser worker Komiku Asia sudah dihapus dari runtime dan tabelnya dihapus oleh
migration Alembic `d3f8a1c9e6b2` pada 25 Agustus 2026.

## Ringkasan Eksekutif

Backend sudah memiliki beberapa keputusan yang baik: SQLAlchemy async digunakan secara konsisten, katalog utama memakai pagination, beberapa endpoint katalog memakai `noload(Comic.chapters)`, detail komik memakai correlated count agar tidak mengambil JSONB gambar, dan history list sudah memakai projection ringan.

Namun masih ada hotspot nyata. Prioritas tertinggi adalah:

| Prioritas | Area | Risiko utama | Dampak saat data membesar |
|---|---|---|---|
| P0 | Backfill chapter images | Setiap batch menghitung backlog dengan scan dan evaluasi JSONB terhadap sekitar 1,15 juta chapter | Query count backlog rata-rata memakan sekitar 8-10 detik dan dipanggil ribuan kali |
| P0 | ORM relationship default | `Comic.chapters` otomatis dimuat dengan `selectin`, termasuk JSONB `images`, pada banyak query yang hanya membutuhkan metadata | Transfer DB, RAM, serialisasi, dan latensi meningkat tajam |
| P0 | Batch download | Lookup `UserDownloadEntry` dilakukan satu per satu di dalam loop chapter | Pola N+1 nyata; ratusan round-trip DB per request |
| P0 | Sync import | Setiap item snapshot memanggil service ber-query dan ber-`commit()` sendiri | Request panjang, partial import, beban DB berlipat |
| P0 | Image proxy | Proxy menerima hampir semua URL HTTP, mengikuti redirect, dan tidak membatasi ukuran stream | Risiko SSRF, open proxy, bandwidth exhaustion, dan koneksi origin berlebih |
| P1 | Lookup komik scraper | Fallback lookup memakai `(source_url, source_name)`, tetapi belum memiliki composite index selaras | Lookup fallback tercatat rata-rata sekitar 532 ms |
| P1 | Daftar chapter | Seluruh JSONB `images` diambil hanya untuk menghitung `len()` | Query menjadi sangat berat untuk komik dengan banyak chapter |
| P1 | Search | Pencarian memakai `%keyword%` dengan `ILIKE`; index B-tree title biasa tidak banyak membantu | Full scan saat katalog membesar |
| P1 | Scraper incremental | Query dan `commit()` per item listing, upsert per chapter, serta upsert genre per item | Durasi job panjang dan DB chatter tinggi |

Kesimpulan: risiko utama bukan hanya classic N+1. Ada kombinasi N+1 nyata, over-fetch relasi, JSONB payload amplification, query chatty, dan endpoint yang dapat dipakai untuk menghabiskan resource.

## Referensi Context7

Audit ini menggunakan dokumentasi resmi SQLAlchemy 2.0 melalui Context7:

| Topik | Referensi resmi | Relevansi |
|---|---|---|
| Lazy loading dan N+1 | [Relationship Loading Techniques](https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html) | Lazy loading dapat memicu masalah N+1; `raiseload()` dapat dipakai untuk mendeteksi akses relasi yang tidak direncanakan |
| `selectinload()` | [Select IN loading](https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html#select-in-loading) | Umumnya efisien untuk collection karena related rows diambil dengan secondary `SELECT ... WHERE ... IN (...)`, tetapi tetap berbahaya bila collection besar atau memuat blob |
| `joinedload()` | [Joined Eager Loading](https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html#joined-eager-loading) | Cocok untuk kebutuhan tertentu, tetapi menambah lebar row dan perlu kehati-hatian untuk collection |
| Bulk DML | [ORM-Enabled INSERT, UPDATE, and DELETE statements](https://docs.sqlalchemy.org/en/20/orm/queryguide/dml.html) | SQLAlchemy mendukung bulk INSERT/UPDATE dengan daftar parameter agar tidak mengeksekusi satu statement per item |
| PostgreSQL `ON CONFLICT` | [PostgreSQL dialect `INSERT ... ON CONFLICT`](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html) | Dipakai untuk bulk upsert batch download dan import snapshot yang idempotent |
| Transaction async | [`AsyncSession.begin()`](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html) | Context manager transaction menjamin commit hanya setelah seluruh import sukses dan rollback saat satu selector atau write gagal |
| Batas list payload | [Pydantic standard library types](https://github.com/pydantic/pydantic/blob/main/docs/api/standard_library_types.md) | `Field(max_length=...)` membatasi payload batch dan snapshot sebelum query database dijalankan |
| `AsyncSession` | [Asyncio Integration](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html) | Satu `AsyncSession` tidak aman dibagi ke beberapa concurrent task; codebase sudah benar saat background prefetch membuat session sendiri |
| PostgreSQL multicolumn index | [Multicolumn Indexes](https://www.postgresql.org/docs/current/indexes-multicolumn.html) | Index B-tree paling efektif saat filter memakai kolom paling kiri; relevan untuk lookup `(source_name, source_url)` |
| PostgreSQL trigram | [`pg_trgm`](https://www.postgresql.org/docs/current/pgtrgm.html) | GIN atau GiST trigram dapat membantu `LIKE` dan `ILIKE`, termasuk pola leading-wildcard |
| PostgreSQL RLS | [`CREATE POLICY`](https://www.postgresql.org/docs/current/sql-createpolicy.html) | Jika RLS aktif tetapi tidak ada policy yang berlaku, PostgreSQL menerapkan default-deny |
| PostgreSQL `SECURITY DEFINER` | [`CREATE FUNCTION`](https://www.postgresql.org/docs/current/sql-createfunction.html) | Function privileged perlu `search_path` aman dan privilege `EXECUTE` yang dibatasi |
| Supabase performance debugging | [Debugging and monitoring](https://supabase.com/docs/guides/database/debugging-performance) | `EXPLAIN`, statistik query, dan observability dipakai untuk memvalidasi bottleneck |
| Supabase database advisor | [Database Advisors](https://supabase.com/docs/guides/database/database-advisors) | Advisor membantu mendeteksi missing index, duplicate index, dan isu security |

Catatan penting: `selectinload()` mengurangi classic N+1 menjadi secondary query terkelompok. Ia tidak otomatis membuat query ringan jika relasi yang dimuat berisi ribuan row atau JSONB besar.

## Validasi Runtime Supabase MCP

Inspeksi berikut dilakukan secara read-only pada 2 Juni 2026. Angka dapat bergerak karena scraper masih aktif. Statistik `pg_stat_statements` saat audit berasal dari periode sejak reset pada 12 April 2026 pukul 19:56 WIB.

### Snapshot Data

| Tabel | Row saat inspeksi | Ukuran total perkiraan | Catatan |
|---|---:|---:|---|
| `chapters` | 1.152.378 | 333 MB | Tabel terbesar; sekitar 261 MB heap dan 68 MB index |
| `comics` | 22.321 | 51 MB | Sekitar 41 MB heap dan 10 MB index |
| `comic_genre` | 95.737 | 5,5 MB | Advisor menemukan FK `genre_id` belum memiliki covering index |
| `chapter_image_jobs` | 65 | kecil | Seluruh 65 job berstatus `completed`; memiliki duplicate index pada `chapter_id` |

Distribusi JSONB `chapters.images`:

| Kondisi | Jumlah row | Proporsi |
|---|---:|---:|
| Total chapter terukur | 1.150.118 | 100% |
| Array kosong | 1.051.933 | 91,5% |
| Array berisi URL gambar | 98.185 | 8,5% |
| Total storage kolom JSONB `images` | 74 MB | - |
| Ukuran maksimum satu nilai JSONB | 10.493 byte | - |

Implikasinya: query yang memeriksa validitas `images` bukan sekadar membaca metadata kecil. Ia memindai sekitar 1,15 juta row dan mengevaluasi ekspresi JSONB, walau mayoritas row hanya berisi array kosong.

### Hotspot Terukur

| Query atau alur | Calls | Rata-rata | Bukti dan interpretasi |
|---|---:|---:|---|
| Count backlog chapter images seluruh source | 5.634 | 8.039 ms | Hotspot tertinggi; scan JSONB berulang pada setiap loop batch |
| Count backlog chapter images source-scoped | 823 | 9.061 ms | Filter source belum membuat operasi murah karena ekspresi backlog tetap berat |
| Ambil batch chapter images pending | 548 | 10.779 ms | Query batch memilih row backlog setelah evaluasi predicate JSONB |
| Group count komik per source | 853 | 1.064 ms | Layak dipantau dan dapat diganti summary teragregasi bila sering dipanggil |
| Lookup komik berdasarkan `source_url` dan `source_name` | 722 | 532 ms | Belum memiliki composite index yang mengikuti bentuk lookup |
| Upsert chapter satu per satu | 2.187.539 | 0,34 ms | Masing-masing cepat, tetapi jumlah panggilan menunjukkan scraper sangat chatty |

Sumber kode count backlog:

| Bukti | Penjelasan |
|---|---|
| `backend/scraper/sync_chapter_images.py:355-387` | Predicate pending dibangun dari `CASE` dan inspeksi JSONB |
| `backend/scraper/sync_chapter_images.py:422-444` | `_count_pending()` menjalankan count penuh |
| `backend/scraper/sync_chapter_images.py:712` | Count dipanggil ulang pada setiap iterasi batch |
| `backend/scripts/check_pending_chapter_images.py:64-107` | Preflight script menjalankan varian count total dan per-source |
| `backend/app/services/chapter_service.py:122-147` | Service aplikasi memiliki ekspresi validitas images serupa |

Predicate mahal ini tersebar di beberapa file. Selain duplikasi kode, perubahan aturan validitas berisiko membuat worker, preflight, dan aplikasi memberi jawaban berbeda.

### Hasil `EXPLAIN` Estimasi

`EXPLAIN` dijalankan tanpa `ANALYZE`, sehingga tidak mengeksekusi query berat. Ia cukup untuk menunjukkan bentuk rencana planner.

| Query | Rencana penting | Kesimpulan |
|---|---|---|
| Count backlog chapter images | `Parallel Seq Scan chapters` lalu filter JSONB dan aggregate | Scan besar memang terjadi; menambah index biasa pada JSONB belum tentu menyelesaikan masalah |
| Lookup komik `source_name + source_url` | Bitmap scan `uq_source_slug`, lalu filter `source_url` dari sekitar 10.027 kandidat untuk `komikcast` | Tambahkan composite B-tree `(source_name, source_url)` |
| Search `%solo%` | Index scan untuk urutan lalu filter `ILIKE '%solo%'` pada title dan alternative title | B-tree title tidak memecahkan substring search; uji `pg_trgm` |
| Latest feed per source | Filter source, incremental sort, dan correlated subplan release date | Index feed saat ini belum selaras dengan source; refactor query atau materialisasi metadata latest release layak diuji |
| Daftar chapter satu komik | Backward index scan pada `uq_comic_chapter` | Filter dasarnya baik, tetapi projection masih perlu diringankan agar tidak mengambil JSONB penuh |

### Statistik Scan dan Cache

| Metrik | Nilai | Interpretasi |
|---|---:|---|
| `chapters.seq_scan` | 3.231 | Scan tabel chapter sudah sering terjadi |
| `chapters.seq_tup_read` | 2.089.086.846 | Sekitar 2,09 miliar tuple chapter telah dibaca melalui sequential scan |
| Table cache hit ratio | 93,2% | Di bawah target health check 95%; scan besar kemungkinan ikut menekan cache |
| Index cache hit ratio | 99,2% | Sehat |
| `chapters.n_dead_tup` | 120.096 | Masih perlu dipantau karena worker sering melakukan update |
| Invalid index | 0 | Tidak ditemukan |
| Bloated index | 0 | Tidak ditemukan oleh health check |

Autovacuum dan autoanalyze berjalan. Sampel log PostgreSQL terbaru tidak menunjukkan error yang jelas, tetapi checkpoint tulis periodik tetap terlihat. Ini konsisten dengan workload scraper aktif, bukan bukti insiden tersendiri.

### Advisor Performa

| Advisor | Object | Tindakan yang disarankan |
|---|---|---|
| Unindexed foreign key | `comic_genre.genre_id` | Tambahkan index `comic_genre (genre_id)` jika delete/update genre atau join dari genre cukup sering |
| Duplicate index | `chapter_image_jobs_chapter_id_key` dan `ix_chapter_image_jobs_chapter_id` | Pertahankan unique constraint index; hapus index non-unique duplikat setelah verifikasi |
| Unused index | `ix_comics_latest_feed_order` | Jangan langsung hapus; statistik menunjukkan `idx_scan = 0`, tetapi query feed perlu diperbaiki dan diuji lebih dulu |
| Unused index | Beberapa index tabel library user | Evaluasi setelah observability window; beberapa index tertutup oleh unique atau composite index lain |

Health check juga menunjukkan beberapa index tertutup oleh index lain, termasuk `ix_chapters_comic_id` yang tertutup oleh `uq_comic_chapter`. Penghapusan index harus dilakukan setelah review query dan observability window, bukan otomatis berdasarkan snapshot.

### Advisor Security

Temuan security tidak selalu memperlambat query, tetapi perlu masuk backlog karena audit Supabase MCP menemukannya langsung.

| Severity | Temuan | Risiko atau keputusan yang diperlukan |
|---|---|---|
| Warn | Role `anon` dan `authenticated` dapat mengeksekusi tiga function `SECURITY DEFINER`: `handle_new_auth_user_defaults()`, `handle_new_auth_user_reader_preferences()`, dan `rls_auto_enable()` | Verifikasi pemakaian trigger, lalu revoke privilege RPC yang tidak diperlukan |
| Info | RLS aktif tanpa policy pada tabel katalog dan backend: `comics`, `chapters`, `genres`, `comic_genre`, `source_stats`, `chapter_image_jobs`, dan `alembic_version` | PostgreSQL menerapkan default-deny. Ini aman bila tabel memang hanya diakses backend, tetapi perlu dicatat sebagai keputusan arsitektur |
| Warn | Leaked-password protection Supabase Auth belum aktif | Aktifkan melalui konfigurasi Auth bila sesuai tier dan kebutuhan produk |

Tabel library user sudah memiliki policy own-user untuk role `authenticated`. Untuk function privileged, dokumentasi PostgreSQL menyarankan `search_path` yang hanya memuat schema tepercaya dan pembatasan privilege `EXECUTE`.

### Kandidat Migration untuk Diuji

Berikut draft, bukan perubahan yang sudah diterapkan:

```sql
create index concurrently if not exists ix_comic_genre_genre_id
    on public.comic_genre (genre_id);

create index concurrently if not exists ix_comics_source_name_source_url
    on public.comics (source_name, source_url);

drop index concurrently if exists public.ix_chapter_image_jobs_chapter_id;
```

Untuk search substring, extension `pg_trgm` tersedia tetapi belum terpasang:

```sql
create extension if not exists pg_trgm;

create index concurrently if not exists ix_comics_title_trgm
    on public.comics using gin (title gin_trgm_ops);

create index concurrently if not exists ix_comics_alternative_title_trgm
    on public.comics using gin (alternative_titles gin_trgm_ops);
```

Jalankan `CREATE INDEX CONCURRENTLY` sebagai langkah migration terkontrol di luar transaction block, lalu bandingkan `EXPLAIN (ANALYZE, BUFFERS)` sebelum dan sesudah. Jangan menambah semua index sekaligus: setiap index menambah storage dan biaya write scraper.

### Rekomendasi P0 untuk Backfill Images

Count backlog JSONB perlu diperbaiki sebelum tuning kecil lain. Opsi yang paling kuat:

1. Simpan state terdenormalisasi seperti `images_status`, `images_ready`, atau `image_count` yang diperbarui saat images ditulis.
2. Index state ringan tersebut, idealnya partial index untuk row pending.
3. Hentikan count penuh di setiap loop batch; tampilkan progress berbasis counter periodik atau estimasi.
4. Konsolidasikan predicate validitas images di satu helper atau satu kontrak state.
5. Pisahkan backlog source bila worker memang selalu bekerja per-source.

Status implementasi lokal pada 2 Juni 2026: `P01` sudah disiapkan melalui stored generated column `chapters.images_are_invalid`, partial index `ix_chapters_images_are_invalid_pending`, dan refactor query backlog worker, preflight, serta enqueue aplikasi. `P02` juga sudah disiapkan: worker hanya menghitung backlog penuh saat mulai dan menggunakan estimasi selama batch berikutnya. Migration belum diterapkan ke Supabase produksi. Jadwalkan deployment pada maintenance window karena penambahan stored generated column menghitung state awal seluruh row `chapters`.

Edge case yang perlu diuji:

| Edge case | Risiko |
|---|---|
| Worker images berjalan bersamaan dengan full sync chapter | State images dapat kembali pending atau counter tidak sinkron |
| JSONB `null`, object, string, atau array kosong | Backfill dapat skip row invalid atau memproses row berulang |
| Retry sesudah scraper origin gagal sebagian | Row perlu kembali retryable tanpa masuk loop scan global mahal |
| Beberapa worker source berjalan bersamaan | Claim job harus atomik agar chapter tidak di-fetch dua kali |
| Migration state baru terhadap 1,15 juta row | Backfill kolom dan pembuatan index perlu chunking serta monitoring lock |

## Flow dan Real Case Sebelum-Sesudah

### P01-P06 - Hotspot Query dan Over-Fetch

Perubahan `P01-P06` sudah tersedia secara lokal, tetapi migration belum diterapkan ke Supabase produksi. Angka sebelum berasal dari inspeksi Supabase MCP pada 2 Juni 2026. Dampak sesudah merupakan perilaku query yang sudah diverifikasi secara statis dan target yang perlu dikonfirmasi kembali setelah rollout.

#### Ringkasan Dampak

| ID | Sebelum | Sesudah | Dampak yang diharapkan |
|---|---|---|---|
| `P01` | Query pending mengevaluasi JSONB `images` untuk row chapter secara berulang | PostgreSQL menyimpan generated boolean `images_are_invalid`; partial index hanya memuat row pending | Pencarian backlog tidak lagi memindai dan mem-parsing JSONB seluruh tabel |
| `P02` | Worker menjalankan `_count_pending()` pada setiap iterasi batch | Worker menghitung backlog sekali saat mulai, lalu menurunkan estimasi saat fetch berhasil | Menghilangkan count berulang di antara batch |
| `P03` | Lookup fallback scraper memfilter `source_url` setelah memakai kandidat `source_name` atau slug | Composite index `(source_name, source_url)` tersedia melalui migration | Lookup fallback langsung menuju kandidat yang relevan |
| `P04` | `Comic.chapters` memakai default `lazy="selectin"` sehingga query comic dapat ikut memuat seluruh chapter | Default menjadi `lazy="raise"`; query yang butuh relasi harus memilih loader eksplisit | Over-fetch chapter dan JSONB terdeteksi lebih cepat dan tidak terjadi diam-diam |
| `P05` | Daftar chapter memilih entity `Chapter` penuh, termasuk JSONB `images`, hanya untuk menghitung panjang array | Query hanya memilih metadata chapter dan `jsonb_array_length(images)` sebagai `total_images` | Payload DB turun tanpa mengubah response API |
| `P06` | Endpoint genre membaca `len(comic.chapters)` sehingga memuat seluruh chapter setiap komik | Endpoint genre memakai correlated `COUNT(chapters.id)` dan `noload(Comic.chapters)` | Daftar genre tidak membawa body chapter dan JSONB |

#### P01 dan P02 - Worker Backfill Images

Flow lama:

```text
Mulai worker
  -> scan sekitar 1,15 juta chapter
  -> evaluasi jsonb_typeof, jsonb_array_length, dan jsonb_path_exists
  -> hitung pending
  -> scan lagi untuk mengambil batch
  -> fetch dan simpan images
  -> ulangi count penuh pada batch berikutnya
```

Flow baru:

```text
Metadata chapter dibuat atau images berubah
  -> PostgreSQL menghitung images_are_invalid otomatis
  -> row pending masuk partial index

Mulai worker
  -> hitung pending sekali melalui state ringan
  -> ambil batch dari row images_are_invalid = true
  -> fetch dan simpan images
  -> PostgreSQL menghitung ulang state dan mengeluarkan row siap dari partial index
  -> batch berikutnya memakai estimasi pending tanpa count penuh ulang
```

Real case produksi sebelum perbaikan:

| Query | Calls | Rata-rata |
|---|---:|---:|
| Count backlog semua source | 5.634 | 8.039 ms |
| Count backlog per-source | 823 | 9.061 ms |
| Ambil batch pending | 548 | 10.779 ms |

Contoh satu run 100 chapter dengan `batch_size=10`: sebelumnya worker dapat menjalankan sekitar 10 count backlog penuh. Sesudah `P02`, worker menjalankan satu count awal. `P01` membuat count awal dan pencarian batch memakai state terindeks.

#### P03 - Lookup Fallback Scraper

Flow lama:

```text
Scraper gagal menemukan comic melalui slug
  -> lookup source_url + source_name
  -> planner memakai index yang belum selaras
  -> filter source_url terhadap banyak kandidat source
```

Flow baru:

```text
Scraper gagal menemukan comic melalui slug
  -> lookup source_name + source_url
  -> composite B-tree index menemukan kandidat secara langsung
```

Real case produksi sebelum perbaikan:

| Metrik | Nilai |
|---|---:|
| Lookup fallback tercatat | 722 calls |
| Rata-rata latency | 532 ms |
| Kandidat bitmap untuk contoh `komikcast` | sekitar 10.027 row |
| URL komik terpanjang saat audit | 281 byte |

Migration lokal `c8e3a1f6b4d2` memakai `CREATE INDEX CONCURRENTLY` agar pembuatan index tidak memblokir write normal.

#### P04 - Guard Over-Fetch Relasi Chapter

Flow lama:

```text
Query mengambil Comic
  -> relationship Comic.chapters default selectin
  -> ORM dapat menjalankan secondary SELECT chapter
  -> setiap Chapter ikut membawa JSONB images
```

Flow baru:

```text
Query mengambil Comic
  -> Comic.chapters tidak dimuat otomatis
  -> akses tanpa loader eksplisit memunculkan error pengembangan
  -> endpoint yang hanya butuh metadata memakai noload atau projection
```

Real case: daftar 100 bookmark untuk komik dengan masing-masing 300 chapter dapat berpotensi menarik puluhan ribu row chapter yang tidak dikirim ke client. `lazy="raise"` mengubah risiko tersembunyi tersebut menjadi akses yang harus direncanakan secara eksplisit.

#### P05 - Daftar Chapter Ringan

Flow lama:

```sql
SELECT chapters.*
FROM chapters
WHERE comic_id = :comic_id;
```

API hanya menggunakan metadata chapter dan `len(chapter.images)`, tetapi database tetap mengirim array URL gambar.

Flow baru:

```sql
SELECT
    chapter_number,
    title,
    release_date,
    created_at,
    CASE
        WHEN jsonb_typeof(images) = 'array' THEN jsonb_array_length(images)
        ELSE 0
    END AS total_images
FROM chapters
WHERE comic_id = :comic_id;
```

Response API tidak berubah. Field `total_images` tetap tersedia, sedangkan JSONB URL gambar hanya dikirim oleh endpoint reader yang memang membutuhkannya.

#### P06 - Endpoint Genre Ringan

Flow lama:

```text
Ambil halaman comic untuk genre
  -> eager load genres
  -> default Comic.chapters ikut dimuat
  -> Python menghitung len(comic.chapters)
```

Flow baru:

```text
Ambil halaman comic untuk genre
  -> correlated COUNT(chapters.id) menghasilkan total_chapters
  -> noload(Comic.chapters)
  -> response tetap mengirim total_chapters tanpa memuat entity chapter
```

Contoh halaman genre berisi 20 komik dengan rata-rata 300 chapter: sebelumnya ORM berpotensi mengambil sekitar 6.000 row chapter beserta JSONB. Sesudah perbaikan, endpoint hanya menerima 20 hasil count bersama row comic.

### P07-P10 - Library Backend

Perubahan `P07-P10` tersedia secara lokal tanpa migration schema baru dan tanpa perubahan wire format Flutter.

| ID | Sebelum | Sesudah | Dampak yang diharapkan |
|---|---|---|---|
| `P07` | Batch download melakukan lookup dan update `UserDownloadEntry` per chapter | Chapter dipilih dengan projection ringan, existing ID dicari sekali, lalu `INSERT ... ON CONFLICT DO UPDATE` per chunk 500 dengan satu commit | Query count tidak lagi tumbuh linear terhadap jumlah chapter |
| `P08` | Import snapshot memanggil helper publik yang ber-query dan `commit()` per item | Selector comic dan chapter di-resolve bulk; seluruh kategori ditulis bulk dalam satu `AsyncSession.begin()` | Tidak ada partial import ketika selector atau write di tengah batch gagal |
| `P09` | Summary menjalankan enam count serial dan state comic mengambil entity chapter penuh | Summary count menjadi satu `UNION ALL`; progress dan download memakai projection serta menghitung `jsonb_array_length()` hanya untuk row terpilih | Round-trip dan transfer JSONB berkurang |
| `P10` | List collection memuat seluruh association dan comic; detail satu ID mengambil semua collection user | Summary memakai `LEFT OUTER JOIN + COUNT`; detail query langsung satu `collection_id`; relationship default `lazy="raise"` | List dan state tidak lagi menarik seluruh isi collection |

#### P07 - Batch Download 500 Chapter

```text
Sebelum: load chapter penuh termasuk images
  -> 500 kali SELECT existing download
  -> mutasi entity satu per satu
  -> commit

Sesudah: SELECT id, comic_id, chapter_number
  -> satu SELECT existing chapter_id IN (...)
  -> satu bulk upsert chunk 500
  -> satu commit
```

Retry batch yang sama menghasilkan `created_total=0` dan `updated_total=500` tanpa duplikasi. Payload explicit di atas 5.000 chapter ditolak oleh Pydantic; mode `chapter_numbers=null` tetap mendukung seluruh chapter komik.

#### P08 - Import Snapshot Atomic

```text
Sebelum: bookmark commit -> collection item commit -> progress commit -> ...
  -> chapter invalid di tengah batch
  -> data sebelum error sudah tersimpan sebagian

Sesudah: validate batas payload
  -> resolve comic dan chapter selector bulk
  -> bulk upsert seluruh kategori dalam satu transaction
  -> commit hanya jika semua langkah sukses
```

Batas longgar yang diterapkan: maksimum 2.000 item per kategori, 200 collection, 1.000 comic per collection, dan 10.000 item total termasuk isi collection. Oversized snapshot ditolak `422`; snapshot lokal frontend tetap tersedia untuk retry karena penghapusan lokal hanya dilakukan setelah response sukses.

#### P09 dan P10 - Summary, State, dan Collection

```text
Sebelum: enam SELECT count serial
  -> load progress entity + chapter JSONB
  -> load detail seluruh collection dan item comic

Sesudah: satu UNION ALL untuk enam count
  -> projection progress, history, dan download
  -> aggregate COUNT association collection
  -> detail collection query tepat satu ID saat diminta
```

Contoh user dengan 100 collection dan 1.000 association: membuka picker collection sekarang mengembalikan 100 row summary aggregate. Isi association dan comic baru dimuat eksplisit ketika user membuka satu detail collection.

### P12 - Feed Latest dan Popular Per-Source

Perubahan `P12` tersedia lokal melalui migration `d7a9e4c2f6b1`. Migration belum diterapkan ke Supabase produksi.

```text
Sebelum: filter source_name
  -> urutkan marker feed memakai index global tanpa prefix source_name
  -> latest ikut menghitung correlated MAX(chapters.release_date) untuk fallback sort
  -> planner dapat scan kandidat source lalu sort

Sesudah: filter source_name
  -> urutkan marker feed canonical dengan fallback updated_at dan id deterministik
  -> B-tree source-prefixed mengikuti filter dan ORDER BY endpoint
  -> correlated latest release tetap dihitung untuk payload row halaman terpilih,
     tetapi tidak lagi menjadi bagian ORDER BY feed
```

Index lokal baru:

| Index | Urutan kolom |
|---|---|
| `ix_comics_source_latest_feed_order` | `source_name`, `latest_feed_batch_at DESC NULLS LAST`, `latest_feed_page ASC NULLS LAST`, `latest_feed_position ASC NULLS LAST`, `updated_at DESC`, `id` |
| `ix_comics_source_popular_feed_order` | `source_name`, `popular_feed_batch_at DESC NULLS LAST`, `popular_feed_page ASC NULLS LAST`, `popular_feed_position ASC NULLS LAST`, `rating DESC NULLS LAST`, `total_view DESC NULLS LAST`, `updated_at DESC`, `id` |

`EXPLAIN` read-only sebelum rollout untuk bentuk query latest target pada source `komikcast` masih menunjukkan sequential scan sekitar 9.980 kandidat lalu sort. Simulasi hypothetical index belum dapat dijalankan karena extension `hypopg` tidak tersedia di server. Sesudah rollout, ulangi `EXPLAIN (ANALYZE, BUFFERS)` untuk memastikan planner memakai index baru sebelum mempertimbangkan penghapusan index feed global lama.

Endpoint latest, popular, dan source search juga kembali memakai `selectinload(Comic.genres)`. Response memang mengirim genre, sehingga `noload(Comic.genres)` sebelumnya dapat menghasilkan list genre kosong.

### P11 dan P13 - Search Trigram dan Index Genre

Perubahan `P11` dan `P13` tersedia lokal melalui migration `e3b8c5d7a9f2`. Migration belum diterapkan ke Supabase produksi.

```text
Search sebelum: WHERE title ILIKE '%keyword%' OR alternative_titles ILIKE '%keyword%'
  -> B-tree title dapat dipakai untuk urutan
  -> filter substring tetap dievaluasi pada kandidat yang besar

Search sesudah: extension pg_trgm aktif
  -> GIN trigram index untuk title dan alternative_titles
  -> planner memiliki opsi bitmap index scan untuk LIKE/ILIKE substring
```

```text
Genre sebelum: filter genre dapat mulai dari comic/title ordering
  -> cek comic_genre_pkey per comic
  -> tidak ada index tunggal pada FK child comic_genre.genre_id

Genre sesudah: index comic_genre(genre_id)
  -> planner memiliki opsi mulai dari association genre
  -> join dan operasi delete/update parent genre lebih murah saat genre selektif
```

Index lokal baru:

| Index | Tabel | Tujuan |
|---|---|---|
| `ix_comics_title_trgm` | `comics` | Mempercepat `title ILIKE '%keyword%'` dengan GIN trigram |
| `ix_comics_alternative_titles_trgm` | `comics` | Mempercepat `alternative_titles ILIKE '%keyword%'` dengan GIN trigram |
| `ix_comic_genre_genre_id` | `comic_genre` | Mempercepat lookup association dari genre ke comic dan FK maintenance |

`EXPLAIN` read-only sebelum rollout untuk search `%solo%` masih menunjukkan index scan `ix_comics_title` lalu filter substring. Untuk query genre contoh, planner memakai index title lalu mengecek association per comic melalui `comic_genre_pkey`. Sesudah rollout, ulangi `EXPLAIN (ANALYZE, BUFFERS)` pada search global, source search, global genre filter, dan source genre filter untuk memastikan index baru benar-benar dipakai pada pola data produksi.

### P14 - Bulk Scraper per Halaman dan per Comic

Perubahan `P14` tersedia lokal tanpa migration schema baru. Fokusnya mengurangi query dan write kecil berulang pada scraper incremental dan full library.

```text
Incremental latest sebelum: untuk setiap item listing
  -> lookup comic by slug
  -> fallback lookup by source_url
  -> cek latest chapter URL atau max chapter
  -> marker feed update + commit per unchanged comic

Incremental latest sesudah: untuk satu halaman listing
  -> bulk lookup comic by slug/source_url
  -> bulk cek latest chapter URL atau max chapter per comic
  -> bulk marker unchanged dalam satu UPDATE ... FROM VALUES
  -> kandidat detail tetap diproses per comic agar error handling granular
```

```text
Popular sebelum: untuk setiap item ranking
  -> lookup comic existing
  -> marker popular update + commit per existing comic

Popular sesudah: untuk satu halaman ranking
  -> bulk lookup comic by slug/source_url
  -> bulk marker popular existing dalam satu UPDATE ... FROM VALUES
  -> comic baru tetap fetch detail per item
```

```text
Metadata comic/chapter/genre sebelum:
  -> upsert comic lalu SELECT id
  -> upsert chapter metadata satu statement per chapter
  -> upsert genre dan association satu per genre

Metadata comic/chapter/genre sesudah:
  -> upsert comic memakai RETURNING id
  -> chapter metadata multi-row INSERT ... ON CONFLICT
  -> genre bulk upsert + association bulk insert
  -> full library sync memakai helper genre yang sama dengan incremental
```

Real case: halaman latest berisi 20 item dengan 18 unchanged. Sebelumnya scraper dapat menjalankan puluhan query lookup/marker dan 18 commit hanya untuk menandai posisi feed. Sesudah perbaikan, lookup existing dilakukan sekali, validasi latest chapter dikumpulkan, dan 18 marker dikirim dalam satu statement update.

Edge case yang dipertahankan:

| Edge case | Perilaku |
|---|---|
| Listing tanpa `source_url` | Tetap skip invalid dan tidak ditandai marker |
| Comic existing dengan latest chapter baru | Tidak ditandai marker early; marker ditulis oleh `process_comic()` setelah detail/upsert sukses |
| Detail fetch error pada satu kandidat | Error handling per comic tetap berlaku; kandidat lain di page tetap mengikuti flow lama |
| Full library crash di tengah run | Commit tetap per comic, bukan per halaman besar, sehingga checkpoint safety tidak berubah |

### P15, P16, dan P17 - Queue Chapter Image Jobs dan Review Index

Perubahan `P15` dan `P16` tersedia lokal melalui service refactor dan migration `f6c1d8e4b2a9`. Migration belum diterapkan ke Supabase produksi. `P17` dicatat sebagai review snapshot dan observation checklist karena keputusan drop index lain perlu window penggunaan setelah migration P11-P16 benar-benar berjalan.

```text
P15 sebelum: enqueue N chapter
  -> dedupe ID
  -> loop N kali INSERT ... ON CONFLICT
  -> caller commit

P15 sesudah: enqueue N chapter
  -> dedupe ID
  -> bulk INSERT ... ON CONFLICT per chunk 500
  -> caller commit tetap dipertahankan
```

Semantik upsert tetap sama:

| Kondisi row lama | Perilaku tetap |
|---|---|
| `processing` | Status tidak diturunkan ke `pending` |
| `failed` | Status dan `last_error` dipertahankan |
| `completed` | `attempts` reset ke 0, `completed_at` dikosongkan, dan tersedia lagi sebagai `pending` |
| prioritas lebih rendah | Prioritas dinaikkan dengan `greatest(existing, requested)` |

```text
P16 sebelum: chapter_image_jobs.chapter_id punya unique constraint
  + index eksplisit ix_chapter_image_jobs_chapter_id

P16 sesudah: unique constraint/index chapter_image_jobs_chapter_id_key dipertahankan
  -> index eksplisit duplikat ix_chapter_image_jobs_chapter_id dihapus concurrent
```

Snapshot read-only Supabase pada 2 Juni 2026 menunjukkan:

| Index | idx_scan | Ukuran | Keputusan |
|---|---:|---:|---|
| `chapter_image_jobs_chapter_id_key` | 233 | 16 kB | Dipertahankan sebagai unique constraint target |
| `ix_chapter_image_jobs_chapter_id` | 166.869 | 16 kB | Dihapus lokal karena duplikat constraint unique |
| `ix_chapter_image_jobs_status_priority_available` | 168.494 | 16 kB | Dipertahankan untuk worker claim queue |
| `ix_comics_latest_feed_order` | 0 | 2,9 MB | Jangan hapus sampai P12 source-prefixed index punya observation window |
| `ix_comics_source_latest_feed_order` | 0 | 1,2 MB | Baru; validasi setelah rollout |
| `ix_comics_title_trgm` | 0 | 2,8 MB | Baru; validasi setelah rollout P11 |
| `ix_comics_alternative_titles_trgm` | 0 | 6,7 MB | Baru; validasi setelah rollout P11 |
| `ix_comic_genre_genre_id` | 0 | 680 kB | Baru; validasi setelah rollout P13 |

Catatan: beberapa index baru pada snapshot sudah muncul dengan `idx_scan = 0` karena statistik belum memiliki observation window yang setara. Jangan jadikan `idx_scan = 0` sebagai alasan drop sebelum endpoint terkait menerima traffic dan query plan pasca-rollout diverifikasi.

### P18-P20 - Reliability dan Resource Protection

| Item | Sebelum | Sesudah | Real case / edge case |
|---|---|---|---|
| `P18` Image proxy | Endpoint hanya cek `url.startswith("http")`, membuat `AsyncClient` baru, mengikuti redirect otomatis, dan stream tanpa size cap backend. | URL harus `http/https`, host harus masuk allowlist source, DNS dan setiap redirect divalidasi agar tidak menuju IP private/link-local/loopback/reserved, response harus `image/*`, content length dibatasi, dan stream memakai shared client. | Request `https://cdnkomiku.xyz/a.jpg` tetap jalan. Request yang redirect ke `http://127.0.0.1/private.jpg`, content-type `text/html`, atau file di atas batas ditolak sebelum menjadi open proxy/resource drain. |
| `P19` Supabase/Auth outbound request | Banyak operasi auth/admin membuat `httpx.AsyncClient` baru sehingga koneksi TLS dan pool tidak reuse. | Auth service, account manager admin request, upload avatar storage, trigger GitHub, dan proxy image memakai shared clients yang dibuat di lifespan dan ditutup saat shutdown. | Lonjakan login/refresh token tidak terus membuat koneksi baru. Timeout per operasi tetap ada, tetapi connection pooling mengurangi latency setup dan socket churn. |
| `P20` Prefetch cooldown | `_prefetch_cooldowns` process-level dict bertambah monoton selama proses hidup. | Cooldown memakai `OrderedDict` dengan TTL cleanup dan batas 2.048 entry per worker. Entry expired dibuang; jika tetap melebihi batas, entry paling lama dievict. | Jika ribuan komik berbeda dibaca sepanjang hari, memori cooldown tidak tumbuh tanpa batas. Jika user membaca chapter komik yang sama dalam 60 detik, prefetch tetap dicegah seperti sebelumnya. |

#### Checklist Verifikasi P18-P20

- [x] Unit test validasi proxy: scheme, allowlist host, IP private, DNS private, redirect, content-type non-image, dan size cap.
- [x] Unit test shared HTTP client lifecycle: reuse sebelum shutdown dan closed setelah shutdown.
- [x] Unit test cooldown prefetch: TTL unblock, pruning expired, dan batas maksimum entry.
- [ ] Staging test image proxy terhadap host produksi nyata untuk memastikan allowlist tidak terlalu sempit.
- [ ] Pantau metrik request auth/proxy setelah deploy: timeout, upstream 4xx/5xx, connection pool pressure, dan bandwidth egress.

### Validasi Sesudah Rollout

| Pemeriksaan | Target |
|---|---|
| `EXPLAIN (ANALYZE, BUFFERS)` query pending images | Menggunakan partial index `ix_chapters_images_are_invalid_pending` |
| `pg_stat_statements` count backlog images | Calls turun tajam karena tidak lagi dipanggil setiap batch; mean latency jauh di bawah baseline 8-10 detik |
| `EXPLAIN (ANALYZE, BUFFERS)` lookup `source_name + source_url` | Menggunakan `ix_comics_source_name_source_url` |
| Smoke test daftar chapter | Response tetap memiliki `total_images`, tanpa transfer JSONB `images` dari query list |
| Smoke test `/api/v1/genres/{slug}/comics` | `total_chapters` tetap benar dan tidak ada query pemuatan collection chapter |
| Query logging endpoint katalog dan library | Tidak ada secondary load `Comic.chapters` yang tidak direncanakan |
| Load test `/library/downloads/batch` 500 chapter | Lookup existing sekali, bulk upsert satu chunk, dan satu transaction |
| Retry batch download yang sama | Tidak ada duplikasi; seluruh row dihitung update |
| Import snapshot dengan selector invalid di tengah payload | Seluruh kategori rollback |
| Smoke test collection kosong dan berisi item | Aggregate `total_items` tetap benar |
| Query logging `/library/summary`, `/library/state/...`, dan `/library/collections` | Tidak memilih blob `chapters.images`; fungsi panjang array hanya dievaluasi pada row projection terpilih |
| `EXPLAIN (ANALYZE, BUFFERS)` latest dan popular per-source | Memakai index `ix_comics_source_latest_feed_order` dan `ix_comics_source_popular_feed_order`; sort kandidat source berkurang |
| Smoke test latest, popular, dan source search | Genre tetap terisi; urutan marker canonical stabil dengan tie-breaker `id` |
| `EXPLAIN (ANALYZE, BUFFERS)` search global dan source search | Planner memakai GIN trigram index saat pola pencarian cukup selektif |
| `EXPLAIN (ANALYZE, BUFFERS)` filter genre global dan source-scoped | Planner memiliki opsi index `ix_comic_genre_genre_id`; query tidak harus scan comic/title ordering lebih dulu |
| Dry run/log scraper incremental per source | Page latest/popular tidak lagi melakukan lookup dan marker commit per item unchanged |
| Unit/integration test scraper DB ops | Bulk marker memakai `UPDATE ... FROM VALUES`; chapter metadata memakai multi-row upsert |
| Load test enqueue `chapter_image_jobs` 50, 200, dan 600 chapter | Statement upsert per chunk, bukan per chapter; caller masih mengontrol commit |
| `EXPLAIN (ANALYZE, BUFFERS)` lookup `chapter_image_jobs.chapter_id` setelah P16 | Planner memakai `chapter_image_jobs_chapter_id_key` setelah index eksplisit dihapus |
| `pg_stat_user_indexes` setelah observation window | Index baru dievaluasi berdasarkan traffic nyata sebelum keputusan drop lanjutan |

## Temuan Detail

### 1. Over-fetch Relasi `Comic.chapters` ✅

Severity: **tinggi**
Jenis: over-fetch, payload amplification, sumber query raksasa

| Bukti | Penjelasan |
|---|---|
| `backend/app/models/comic.py:135-140` | `Comic.chapters` memakai `lazy="selectin"` secara default |
| `backend/app/models/chapter.py:47-48` | Setiap row chapter membawa kolom JSONB `images` |
| `backend/app/models/library.py:134`, `256-257`, `298-299`, `347-348`, `394-395`, `450-451` | Banyak model library memakai `lazy="joined"` ke `Comic` dan `Chapter` |
| `backend/app/services/library_service.py:426-441`, `801-815`, `913-925`, `987-999` | List bookmark, progress, favorite scene, dan download mengambil ORM entity penuh |

Ini bukan classic N+1 pada relasi chapter karena `selectin` mengelompokkan fetch. Masalahnya adalah setiap `Comic` yang ikut termuat berpotensi memicu secondary query seluruh chapter. Setiap chapter membawa `images`, padahal kebanyakan response library hanya membutuhkan metadata komik atau satu chapter aktif.

Contoh edge case:

| Skenario | Dampak |
|---|---|
| User memiliki 100 bookmark, masing-masing komik memiliki 300 chapter dan JSONB gambar terisi | List bookmark dapat memuat puluhan ribu row chapter yang tidak dikirim ke client |
| Summary memuat 10 progress terbaru dari komik panjang | Endpoint summary ikut menarik history gambar seluruh seri |
| Admin membuka preview relasi user | Query preview dapat ikut membawa blob chapter melalui eager relationship |

Rekomendasi:

1. Ubah default `Comic.chapters` menjadi `lazy="raise"` atau strategi yang tidak otomatis load.
2. Tambahkan loader eksplisit hanya di endpoint yang benar-benar butuh daftar chapter.
3. Untuk list ringan, gunakan projection kolom atau `noload(Comic.chapters)`.
4. Tambahkan test yang gagal bila query list library mengakses relasi tidak direncanakan; `raiseload()` cocok untuk guard ini.

### 2. N+1 Nyata pada Batch Download ✅

Severity: **tinggi**
Jenis: N+1 query, loop write

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/library_service.py:1077-1080` | Semua chapter komik diambil lebih dulu |
| `backend/app/services/library_service.py:1102-1127` | Setiap chapter menjalankan `SELECT UserDownloadEntry` sendiri, lalu insert/update ORM satu per satu |
| `backend/app/schemas/library.py:251-254` | Jika `chapter_numbers` kosong, seluruh chapter diproses |

Untuk komik 500 chapter, request dapat menghasilkan sekitar 1 query chapter + 500 lookup + banyak write saat flush/commit.

Rekomendasi:

1. Ambil seluruh existing entry sekali dengan `WHERE user_id = ... AND chapter_id IN (...)`.
2. Gunakan map `chapter_id -> entry` di memory.
3. Pertimbangkan PostgreSQL bulk `INSERT ... ON CONFLICT DO UPDATE`.
4. Beri limit jumlah chapter per request atau proses batch besar melalui job queue.

### 3. Sync Import Tidak Dibatasi dan Melakukan Commit Berulang ✅

Severity: **tinggi**
Jenis: N+1-like orchestration, transaksi terfragmentasi, endpoint abuse

| Bukti | Penjelasan |
|---|---|
| `backend/app/schemas/library.py:320-333` | Semua list import tidak memiliki `max_length` |
| `backend/app/services/library_service.py:1323-1384` | Import memanggil service per item |
| `backend/app/services/library_service.py:463-464`, `632-633`, `754-764`, `960-965`, `1039-1043` | Service yang dipanggil melakukan `commit()` dan kadang reload per item |

Edge case:

| Skenario | Dampak |
|---|---|
| Snapshot hasil migrasi berisi ribuan history/download | Request dapat berjalan lama dan menekan pool DB |
| Item ke-300 gagal | Sebagian item sebelumnya sudah ter-commit; retry melakukan pekerjaan ulang |
| Client mengirim payload import sangat besar | Endpoint dapat menjadi sumber resource exhaustion |

Rekomendasi:

1. Tambahkan batas item per kategori dan batas total item import.
2. Pisahkan helper mutasi tanpa commit dari helper endpoint tunggal.
3. Gunakan satu transaction boundary per batch atau per chunk.
4. Bulk-resolve comic/chapter dan bulk-upsert bila memungkinkan.
5. Simpan idempotency key atau status import untuk retry.

### 4. Daftar Chapter Mengambil JSONB Penuh Hanya untuk Menghitung Gambar ✅

Severity: **tinggi**
Jenis: query raksasa, over-fetch JSONB

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/sources.py:550` dan `backend/app/services/chapter_service.py:243-249` | Lookup `Comic` sebelum query daftar chapter juga berpotensi memicu default `selectin` seluruh chapter |
| `backend/app/api/v1/sources.py:554-559` | Endpoint daftar chapter mengambil entity `Chapter` penuh |
| `backend/app/api/v1/sources.py:574` | JSONB dipakai hanya untuk `len(chapter.images)` |
| `backend/app/services/library_service.py:91-99` | Beberapa response library juga menghitung `len(chapter.images)` dari blob penuh |

Untuk reader, JSONB gambar memang diperlukan pada endpoint detail chapter. Untuk list chapter dan card library, mengambil seluruh URL gambar hanya untuk count adalah mahal. Pada route daftar chapter, data chapter bahkan berpotensi terambil dua kali: sekali sebagai efek loader default `Comic.chapters`, lalu sekali lagi melalui query eksplisit daftar chapter.

Rekomendasi:

1. Gunakan projection kolom ringan.
2. Hitung `total_images` dengan `jsonb_array_length(images)` atau simpan counter terdenormalisasi yang diperbarui saat images ditulis.
3. Pisahkan schema `ChapterSummary` dan `ChapterReaderPayload`.

### 5. Endpoint Genre Memuat Seluruh Chapter untuk `len()` ✅

Severity: **tinggi**
Jenis: over-fetch relasi

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/genres.py:50-57` | Query comic tidak menonaktifkan `Comic.chapters` |
| `backend/app/api/v1/genres.py:77` | Response menghitung `len(comic.chapters)` |
| `backend/app/api/v1/sources.py:56-60`, `525-535` | Endpoint source detail sudah memiliki pola lebih ringan: correlated chapter count + `noload(Comic.chapters)` |

Rekomendasi: gunakan pola yang sudah ada di `sources.py`: correlated count atau grouped aggregate, lalu `noload(Comic.chapters)`.

### 6. Pencarian Leading-Wildcard Tidak Didukung Index B-tree ✅

Severity: **menengah-tinggi**
Jenis: full scan potensial

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/search.py:50-60` | Query memakai `%{q}%` dan `ILIKE` |
| `backend/app/api/v1/sources.py:490-501` | Search per-source memakai pola sama |
| `backend/app/models/comic.py:90-92` | Ada index title biasa, tetapi tidak ada trigram/full-text index |

Index B-tree biasa umumnya tidak membantu pencarian substring dengan wildcard di awal. Saat jumlah komik membesar, pencarian dapat berubah menjadi sequential scan.

Rekomendasi:

1. Ukur dengan `EXPLAIN (ANALYZE, BUFFERS)`.
2. Pertimbangkan extension PostgreSQL `pg_trgm` dan GIN/GiST trigram index untuk `title` dan bila perlu `alternative_titles`.
3. Batasi query terlalu pendek, misalnya minimum 2-3 karakter, jika UX memungkinkan.

Validasi Supabase MCP: extension `pg_trgm` tersedia tetapi belum terpasang. `EXPLAIN` estimasi untuk `%solo%` masih menunjukkan filter substring setelah index scan, sehingga rekomendasi trigram tetap relevan.

### 7. Image Proxy Dapat Menjadi Open Proxy dan SSRF Surface ✅

Severity: **tinggi**
Jenis: resource exhaustion, keamanan yang berdampak langsung pada performa

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/images.py:42-49` | Validasi hanya `url.startswith("http")`, lalu backend fetch URL dari user |
| `backend/app/api/v1/images.py:45` | Membuat `httpx.AsyncClient` baru pada setiap request |
| `backend/app/api/v1/images.py:45`, `52-60` | Redirect diikuti dan origin dapat di-fetch ulang |
| `backend/app/api/v1/images.py:100-113` | Stream tidak memiliki batas ukuran backend |

Edge case:

| Skenario | Dampak |
|---|---|
| URL mengarah ke file sangat besar atau stream panjang | Bandwidth, socket, dan worker tertahan |
| URL redirect ke private network atau metadata service | SSRF |
| Banyak request cover yang sama setelah cache client miss | Backend mengulang fetch origin; tidak ada shared server cache |

Rekomendasi:

1. Terapkan allowlist host sumber gambar dan validasi hasil redirect.
2. Tolak private, loopback, link-local, dan reserved IP setelah DNS resolution.
3. Batasi response size, content type, durasi, dan jumlah redirect.
4. Gunakan shared `AsyncClient` lifespan agar connection pooling efektif.
5. Pertimbangkan CDN/object storage untuk aset populer.

### 8. Scraper Incremental Chatty ke Database ✅

Severity: **menengah-tinggi**
Jenis: query per item, commit per item

| Bukti | Penjelasan |
|---|---|
| `backend/scraper/main.py:360-386` | Setiap comic listing melakukan lookup comic lalu lookup chapter/max chapter |
| `backend/scraper/main.py:815-839` | Listing latest diproses satu per satu dan item unchanged di-update lalu di-commit |
| `backend/scraper/main.py:955-971` | Popular feed melakukan lookup + update + commit per comic |
| `backend/scraper/main.py:569-607` | Metadata chapter di-upsert per chapter |
| `backend/scraper/db_ops.py:57-88` | Genre diproses per genre dengan insert/select/flush dan insert relasi |

Ini bukan masalah request API langsung, tetapi memperpanjang cron dan meningkatkan beban database. Pola akan terasa ketika jumlah halaman source atau chapter meningkat.

Rekomendasi:

1. Prefetch existing comic IDs untuk seluruh halaman dengan `slug IN (...)`.
2. Bulk-update marker feed per halaman.
3. Bulk-upsert metadata chapter.
4. Cache map genre slug -> id selama satu run dan gunakan bulk insert association.
5. Commit per halaman atau chunk, bukan per comic unchanged.

### 9. Enqueue Chapter Image Job Menjalankan Upsert per Chapter ✅

Severity: **menengah**
Jenis: loop write

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/chapter_image_job_service.py:31-70` | Setiap `chapter_id` membuat dan mengeksekusi statement upsert sendiri |
| `backend/app/services/chapter_image_job_service.py:83-97` | Nearby chapter dapat mengirim beberapa ID sekaligus |

Window saat ini kecil, jadi dampaknya terbatas. Tetap lebih bersih bila memakai bulk insert/upsert.

### 10. Summary Library dan State Comic Terlalu Chatty ✅

Severity: **menengah**
Jenis: banyak query serial

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/library_service.py:1144-1184` | Summary menjalankan enam count terpisah, list progress, list history, list collections, dan dua `get()` |
| `backend/app/services/library_service.py:1220-1289` | State comic menjalankan resolve comic, bookmark, progress, history, collections, favorite count, downloads, dan completed chapters secara serial |

Jumlah query bersifat tetap, bukan N+1, tetapi endpoint ini dipanggil pada screen penting. Bebannya bertambah karena eager relationship yang terlalu lebar.

Rekomendasi:

1. Konsolidasikan count dengan scalar subquery atau `UNION ALL`, seperti pola `backend/app/services/account_manager_service.py:304-343`.
2. Gunakan projection ringan untuk state dan summary.
3. Ambil summary collection dengan aggregate count, bukan memuat seluruh item.

### 11. Collection Summary Memuat Semua Item dan Comic ✅

Severity: **menengah**
Jenis: over-fetch, query redundan

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/library_service.py:508-519` | `list_collections()` selalu `selectinload(items).selectinload(comic)` |
| `backend/app/services/library_service.py:212-220` | Summary hanya membutuhkan `len(collection.items)` |
| `backend/app/api/v1/library.py:282-286` | Detail satu collection mengambil semua collection user lalu mencari satu item di memory |

Rekomendasi:

1. Pisahkan `list_collection_summaries()` dari `get_collection_detail()`.
2. Gunakan aggregate `COUNT(UserCollectionComic.id)` untuk summary.
3. Detail collection harus query berdasarkan `collection_id`, bukan mengambil semua collection.
4. Pastikan comic detail collection memakai projection atau `noload(Comic.chapters)`.

### 12. Query Feed Perlu Diverifikasi dengan Index Source-Scoped ✅

Severity: **menengah**
Jenis: index alignment, correlated subquery

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/sources.py:385-400`, `448-463` | Feed filter berdasarkan `source_name`, lalu order berdasarkan marker feed |
| `backend/app/models/comic.py:75-86` | Index feed tidak diawali `source_name` |
| `backend/app/api/v1/sources.py:63-77` | Feed juga memakai correlated aggregate untuk latest chapter |

Validasi Supabase MCP menunjukkan `ix_comics_latest_feed_order` belum dipakai sejak reset statistik, dengan `idx_scan = 0`. `EXPLAIN` estimasi latest feed per-source masih menunjukkan filter source, incremental sort, dan correlated subplan release date. Index saat ini belum menyelesaikan bentuk query per-source.

Rekomendasi: verifikasi dengan `EXPLAIN (ANALYZE, BUFFERS)` sebelum menambah atau menghapus index. Kandidat index adalah `(source_name, latest_feed_batch_at, latest_feed_page, latest_feed_position)` dan versi popular-nya. Pertimbangkan pula menyimpan metadata latest release pada `comics` agar correlated aggregate tidak dihitung pada setiap request feed.

### 13. In-Memory Prefetch Cooldown Tidak Pernah Dibersihkan ✅

Severity: **rendah-menengah**
Jenis: pertumbuhan memory jangka panjang

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/chapter_service.py:92-95` | Cooldown disimpan dalam dict process-level |
| `backend/app/services/chapter_service.py:499-512` | Entry ditulis, tetapi tidak ada eviction |

Edge case: proses FastAPI hidup lama dan banyak comic berbeda dibaca. Dict tumbuh monoton. Setiap entry kecil, tetapi mudah diperbaiki dengan cleanup periodik atau TTL cache berbatas ukuran.

### 14. Inconsistency: Genre Feed Bisa Selalu Kosong ✅

Severity: **menengah**
Jenis: correctness regression akibat optimasi

| Bukti | Penjelasan |
|---|---|
| `backend/app/api/v1/sources.py:390`, `453`, `495` | Endpoint latest, popular, dan source search memakai `noload(Comic.genres)` |
| `backend/app/api/v1/sources.py:201-204` | Builder tetap membaca `comic.genres` |

Dengan `noload`, collection genre tidak di-fetch. Akibatnya payload feed dapat berisi genre kosong meskipun data ada. Pilih salah satu kontrak: load genres dengan `selectinload`, atau jangan expose genres pada schema card feed.

### 15. Duplikasi Scraper dan Dead Code Menambah Risiko Drift ✅

Severity: **menengah untuk maintainability**, **rendah untuk runtime langsung**
Jenis: duplikasi, dead code, stale comment

| Bukti | Penjelasan |
|---|---|
| `backend/scraper/main.py:533-611` dan `backend/scraper/sync_full_library.py:682-752` | Dua implementasi penyimpanan metadata chapter yang mirip |
| `backend/scraper/main.py:710` dan `backend/scraper/sync_full_library.py:951-963` | Jalur genre berbeda: incremental memakai `sync_comic_genres()`, full library insert association manual |
| `backend/app/services/library_service.py:837-852` | `list_history()` tidak ditemukan dipakai di repo |
| `backend/app/services/chapter_service.py:422-470` | `get_chapter_images_only()` dan versi identity tidak ditemukan dipakai di repo |
| `backend/app/api/v1/library.py:4-7`, `backend/app/models/library.py:13-15` | Comment masih menyebut kontrak auth sementara, sedangkan dependency sekarang memvalidasi bearer token di `backend/app/api/deps.py:20-39` |

Duplikasi genre berpotensi menghasilkan drift: incremental menghapus relasi stale, full library hanya menambah relasi yang belum ada.

Rekomendasi:

1. Konsolidasikan DB operation scraper di `scraper/db_ops.py`.
2. Hapus helper mati setelah memastikan tidak dipakai entrypoint eksternal.
3. Perbarui comment auth agar sesuai implementasi.
4. Pecah file service besar berdasarkan domain; `library_service.py` sudah sekitar 1.386 baris.

### 16. HTTP Client Auth Dibuat Berulang ✅

Severity: **rendah-menengah**
Jenis: connection churn

| Bukti | Penjelasan |
|---|---|
| `backend/app/services/auth_service.py:156`, `184`, `239`, `292`, `317`, `351`, `408`, `433`, `453`, `478`, `506`, `529`, `801` | Banyak operasi membuat `httpx.AsyncClient` baru |
| `backend/app/services/account_manager_service.py:117` | Admin request juga membuat client baru |

Untuk traffic rendah ini dapat diterima. Untuk auth traffic yang meningkat, shared client lifespan mengurangi setup koneksi dan memungkinkan pooling.

## Hal yang Sudah Baik

| Area | Bukti | Nilai positif |
|---|---|---|
| Async DB session | `backend/app/database.py:41-57` | Session dibuat per request |
| Background prefetch | `backend/app/services/chapter_service.py:519` | Task background membuat session sendiri, sesuai panduan `AsyncSession` |
| History list | `backend/app/services/library_service.py:855-910` | Sudah memakai projection ringan dan tidak menarik blob chapter |
| Comic detail source | `backend/app/api/v1/sources.py:525-535` | Sudah memakai count subquery dan `noload(Comic.chapters)` |
| Katalog utama | `backend/app/api/v1/comics.py:60-72` | Sudah paginated dan menonaktifkan chapter load |
| Worker queue | `backend/app/services/komiku_asia_worker.py:67-103` | Claim memakai `FOR UPDATE SKIP LOCKED`, baik untuk overlap worker |
| Counter reading time | `backend/app/services/library_service.py:403-423` | Menggunakan atomic upsert |

## Prioritas Implementasi

| Urutan | Pekerjaan | Expected gain |
|---|---|---|
| 1 | Hilangkan count backlog JSONB penuh pada setiap batch images; gunakan state ringan terdenormalisasi dan index pending | Mengurangi hotspot terukur 8-10 detik per query |
| 2 | Tambahkan composite index `(source_name, source_url)` setelah uji migration | Mempercepat fallback lookup scraper yang terukur rata-rata 532 ms |
| 3 | Hilangkan default over-fetch `Comic.chapters`; gunakan loader eksplisit dan projection | Menurunkan transfer DB dan RAM |
| 4 | Refactor batch download menjadi lookup sekali + bulk upsert | Menghapus N+1 request user-facing |
| 5 | Batasi dan chunk sync import; pisahkan helper mutasi dari `commit()` | Menstabilkan migrasi user |
| 6 | Ringankan daftar chapter dan genre endpoint dari JSONB blob | Menurunkan payload query secara drastis |
| 7 | Kunci image proxy dengan allowlist, DNS/IP validation, size cap, dan shared client | Mengurangi risiko abuse dan koneksi origin |
| 8 | Tambah trigram index search setelah `EXPLAIN ANALYZE` | Menjaga search tetap cepat saat katalog tumbuh |
| 9 | Bulk-kan scraper per halaman/chunk dan konsolidasikan helper duplikat | Mempercepat cron dan mengurangi drift |
| 10 | Review advisor index dan privilege `SECURITY DEFINER` melalui migration terkontrol | Mengurangi write overhead dan menutup akses RPC privileged yang tidak diperlukan |
| 11 | Tambah observability query count, latency, row count, dan payload size | Memastikan perbaikan terukur |

## Todo List Perbaikan

Gunakan checklist ini untuk menandai progres implementasi dan rollout. Item yang sudah selesai hanya berarti perubahan lokal telah tersedia; deployment produksi tetap ditandai terpisah.

### P0 - Dampak Tertinggi

- [x] `P01-A` Implementasikan stored generated column `chapters.images_are_invalid`, partial index pending, dan refactor query backlog lokal.
- [ ] `P01-B` Terapkan migration `b4f7c2d9e6a1` pada maintenance window.
- [ ] `P01-C` Validasi sesudah rollout: cek plan query pending, latency `pg_stat_statements`, dan konsistensi state terhadap sampel JSONB.
- [x] `P02` Kurangi frekuensi `_count_pending()` penuh pada setiap batch worker images.
- [x] `P03-A` Tambahkan migration lokal composite index `comics (source_name, source_url)`.
- [ ] `P03-B` Terapkan migration `c8e3a1f6b4d2` dan validasi lookup scraper pada maintenance window.
- [x] `P04` Hilangkan default eager load `Comic.chapters`; gunakan `lazy="raise"` sebagai guard dan loader eksplisit.
- [x] `P05` Ringankan daftar chapter: hitung `total_images` di PostgreSQL tanpa mengambil JSONB `images`.
- [x] `P06` Perbaiki endpoint genre dengan correlated count tanpa memuat seluruh chapter.

### API Library

- [x] `P07` Refactor batch download menjadi satu lookup existing entry lalu bulk upsert.
- [x] `P08` Batasi dan chunk sync import; hindari `commit()` per item.
- [x] `P09` Ubah summary dan state library agar memakai aggregate dan projection ringan.
- [x] `P10` Pisahkan collection summary dari detail agar list tidak memuat semua item dan comic.

### Search dan Feed

- [x] `P11-A` Tambahkan migration lokal `pg_trgm` dan GIN trigram index untuk `title` serta `alternative_titles`.
- [ ] `P11-B` Terapkan migration `e3b8c5d7a9f2` dan validasi search dengan `EXPLAIN (ANALYZE, BUFFERS)`.
- [x] `P12-A` Refactor latest/popular feed per-source, pulihkan genre response, dan tambahkan migration lokal index dengan prefix `source_name`.
- [ ] `P12-B` Terapkan migration `d7a9e4c2f6b1` pada maintenance window dan validasi dengan `EXPLAIN (ANALYZE, BUFFERS)`.
- [ ] `P12-C` Observasi statistik index sebelum mempertimbangkan penghapusan index feed global lama.
- [x] `P13-A` Tambahkan migration lokal index `comic_genre (genre_id)`.
- [ ] `P13-B` Terapkan migration `e3b8c5d7a9f2` dan validasi filter genre dengan `EXPLAIN (ANALYZE, BUFFERS)`.

### Scraper dan Worker

- [x] `P14-A` Bulk-kan lookup listing, marker feed, chapter metadata, dan genre sync scraper secara lokal.
- [ ] `P14-B` Jalankan dry-run atau sync terbatas per source dan bandingkan query count/log durasi.
- [x] `P15` Bulk upsert enqueue `chapter_image_jobs`.
- [x] `P16-A` Tambahkan migration lokal drop duplicate index `ix_chapter_image_jobs_chapter_id`.
- [ ] `P16-B` Terapkan migration `f6c1d8e4b2a9` dan validasi lookup `chapter_id` memakai unique constraint index.
- [x] `P17-A` Catat snapshot review index dan daftar observation window.
- [ ] `P17-B` Review ulang `pg_stat_user_indexes`, `pg_stat_statements`, dan `EXPLAIN` setelah traffic pasca-rollout stabil.

### Reliability dan Resource Protection

- [x] `P18` Kunci image proxy dengan allowlist host, validasi DNS/IP redirect, size cap, dan shared HTTP client.
- [x] `P19` Gunakan shared `httpx.AsyncClient` untuk auth request.
- [x] `P20` Beri eviction atau bounded TTL cache pada prefetch cooldown.

## Checklist Verifikasi Lanjutan

Audit runtime berikut disarankan sebelum dan sesudah refactor:

| Pemeriksaan | Target |
|---|---|
| `EXPLAIN (ANALYZE, BUFFERS)` count backlog images pada replica atau maintenance window | Ukur buffer read sebelum dan sesudah state pending ringan |
| Pantau `pg_stat_statements` sesudah refactor images | Pastikan mean count backlog turun jauh dari 8-10 detik |
| Uji index `(source_name, source_url)` dengan `EXPLAIN (ANALYZE, BUFFERS)` | Pastikan fallback lookup tidak lagi menyaring ribuan candidate comic |
| SQLAlchemy query logging pada endpoint library | Hitung query per endpoint dan cek apakah `chapters.images` ikut diambil |
| `EXPLAIN (ANALYZE, BUFFERS)` untuk global search dan source search | Pastikan apakah terjadi sequential scan |
| `EXPLAIN (ANALYZE, BUFFERS)` untuk latest/popular source feed | Verifikasi kebutuhan index dengan prefix `source_name` |
| Load test `/api/v1/library/downloads/batch` untuk 50, 200, dan 500 chapter | Pastikan query count tidak linear |
| Load test `/api/v1/library/sync/import` dengan snapshot besar | Pastikan limit, chunking, idempotency, dan timeout terukur |
| Test proxy URL private network, redirect chain, file besar, dan content-type non-image | Pastikan endpoint tidak dapat dipakai sebagai open proxy |
| Test genre latest/popular/search | Pastikan kontrak genre tidak diam-diam berubah menjadi list kosong |

## Catatan Batasan

1. Tidak ada test backend otomatis yang ditemukan di repo.
2. Inspeksi Supabase dilakukan read-only. Tidak ada migration, perubahan schema, update data, atau benchmark tulis yang dijalankan.
3. `EXPLAIN` runtime dijalankan tanpa `ANALYZE`, sehingga bentuk plan diketahui tetapi waktu eksekusi plan spesifik tetap perlu divalidasi terkontrol.
4. Statistik `pg_stat_statements`, row count, dan health check adalah snapshot workload berjalan. Gunakan perbandingan sebelum dan sesudah refactor pada observation window yang setara.
