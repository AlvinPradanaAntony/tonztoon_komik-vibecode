# Ringkasan Refactor Frontend — Sesi Ini

Dokumen ini merangkum seluruh perubahan codebase `frontend/lib/src` selama sesi refactor.
Format: **Before → After**, to the point. Status `flutter analyze`: **No issues found** di setiap tahap.

> Catatan kejujuran: tidak semua "kandidat" dikerjakan. Bagian **Belum Dilakukan** di bawah
> menandai hal yang sempat diidentifikasi tapi sengaja tidak/ belum dieksekusi.

---

## 1. Pecah File Modul Raksasa (SoC)

6 file screen berukuran 2000–3100+ baris dipecah per tanggung jawab via `part` / `part of`,
tanpa mengubah identifier private (zero perubahan API).

**Before**
```
features/comic/comic_detail_screen.dart     ~3000 baris (semua: UI + logic + dialog + helper)
features/reader/reader_screen.dart          3121 baris
features/settings/settings_screen.dart      2918 baris
features/library/library_screen.dart        2773 baris
features/home/home_screen.dart              2416 baris
features/auth/auth_screen.dart              2038 baris
```

**After** (contoh comic; pola sama untuk semua modul)
```
features/comic/
  comic_detail_screen.dart        (library utama + screen)
  controller/                     (logic/state)
  models/                         (view models)
  helpers/                        (formatter)
  dialogs/                        (collection_picker, download_picker)
  widgets/                        (detail_hero, chapter_panel, bottom_read_bar, dst)
```
Subfolder per tanggung jawab: `controller/ models/ helpers/ dialogs/ screens/ widgets/`.
Penamaan file semantik per komponen UI (bukan `comic_detail_widgets.dart` generik).

---

## 2. Pisah Modul Auth Per Alur

**Before**
```
auth/screens/auth_password_screens.dart   580 baris (Forgot + Reset + Callback digabung)
auth/widgets/auth_password_widgets.dart    546 baris (widget Forgot + Reset campur)
```

**After**
```
auth/screens/forgot_password_screen.dart
auth/screens/reset_password_screen.dart
auth/screens/auth_callback_screen.dart
auth/widgets/forgot_password_widgets.dart
auth/widgets/reset_password_widgets.dart
auth/widgets/auth_flow_widgets.dart        (widget dipakai bersama 2 alur)
```
Login + Register tetap 1 `AuthScreen` (memang 1 layar dengan toggle mode).

---

## 3. Shimmer / Loading / Error / Empty → Reusable

**Before** — tiap fitur punya implementasi sendiri (~9 error-state, ~7 empty-state, 3 grid-card-shimmer duplikat).
```dart
// di library, search, catalog, home, section... masing-masing:
Column(children:[ Icon(cloud_off), Text(friendlyErrorMessage(...)), FilledButton(...) ])
Column(children:[ DecoratedBox(circle+icon), Text(title), Text(message) ])
```

**After** — komponen global di `widgets/`.
```dart
widgets/app_error_state.dart    → AppErrorState   (icon opsional, message/error, retry, messageStyle)
widgets/app_empty_state.dart    → AppEmptyState   (icon bubble + title + message + action)
widgets/comic_card.dart         → ComicGridCardShimmer (+ ComicListCardShimmer yang sudah ada)
widgets/app_async_view.dart     → AppAsyncView kini delegasi error ke AppErrorState
```
Dipakai di: library (×2), search, catalog, home, comic_section, continue_reading, reader,
notifications, chapter panel.

Sengaja TIDAK disatukan (beda desain/perilaku): `_NotificationEmptyState` (kartu elevation),
`_PrivacySecurityError` (kartu kompak), `_ReaderPageError` (retry per-halaman + spinner).

---

## 4. Satukan Duplikasi "Library Panes"

Dua library terpisah (`library_screen` part-tree & `library_shared_panes`) masing-masing
mendefinisikan 5 kelas identik.

**Before**
```
library/widgets/library_panes.dart        : _AsyncPane, _LibraryList, _LoadingPane, _ErrorPane
library/widgets/library_common.dart       : _EmptyState
library/library_shared_panes.dart         : _AsyncPane, _LibraryList, _LoadingPane, _ErrorPane, _EmptyState
                                            (≈130 baris duplikat 2×)
```

**After**
```
library/widgets/library_async_pane.dart   : AsyncPane, LibraryList, LoadingPane,
                                             LibraryErrorPane, LibraryEmptyState (sumber tunggal)
→ kedua pemakai pakai typedef / wrapper tipis (offline-copy via parameter)
```
Logika `.when()` + `RefreshIndicator` + snackbar-refresh kini hanya di 1 tempat.

---

## 5. Formatter Duplikat → `utils/formatters.dart`

**Before**
```dart
_progressValue(...)        // identik 3×: home_helpers, library_helpers, continue_reading (inline)
_progressPageText(...)     // identik 2×
_formatCompactViews/_formatCompactDecimal  (home)   // logika K/M/B
_formatBookmarkMetric/_formatBookmarkDecimal (library) // logika sama, beda nama
```

**After**
```dart
utils/formatters.dart:
  readingProgressValue(item)       // fraksi progress bar
  readingProgressPageLabel(item)   // "Halaman x/y"
  formatCompactCount(value)        // 1.5K / 2M / 3B
```
6 fungsi duplikat dihapus; call site pakai wrapper tipis `=> global(...)`.

Sengaja TIDAK disatukan (output beda): comic `_relativeDateLabel`
("Hari ini"/"Kemarin") vs library `_dateLabel` ("baru saja"/"menit lalu").

> **Update (Prioritas 1):** `_compactNumber` di comic SUDAH dihapus dan
> didelegasikan ke `formatCompactCount` — lihat bagian 13. Keputusan lama
> ("sengaja tidak disatukan") dibatalkan: output praktis sama dan kini total view
> komik konsisten dengan home (drop ".0", dapat tier "B").

---

## 6. Komponen UI Identik → Global

**Before**
```dart
library_hero.dart        : class _SectionHeader { ... }   // identik
library_shared_panes.dart: class _SectionHeader { ... }   // identik
comic/.../_sourceLabel(...)  // title-case source, sama dengan comicSourceNameLabel global
```

**After**
```dart
library/widgets/library_async_pane.dart : LibrarySectionHeader (1 kelas, dipakai via typedef)
comic _sourceLabel(...)  => comicSourceNameLabel(...)   // delegasi ke global yang sudah ada
```

Sengaja TIDAK disatukan (varian visual beda, bukan duplikat sejati):
bottom/top fade (8 varian — beda tinggi/stops/kurva), load-more footer (catalog punya spinner),
source badge (3 gaya warna/bentuk berbeda).

> **Update (Prioritas 2):** keputusan "load-more footer" & "source badge" di atas
> SUDAH direvisi sebagian setelah ditinjau ulang per-keluarga — lihat bagian 14
> (load-more footer disatukan jadi `LoadMoreFooter`) dan bagian 15 (source badge:
> Keluarga A→`SourceTag`, Keluarga B→`ComicSourceBadge(prominent:)`).

---

## 7. State Kompleks → Riverpod Notifier (catalog & search)

**Before** — business state nyangkut di `State<Widget>`.
```dart
// full_catalog_screen.dart
ComicFilterSortState _filters; List<ComicSummary> _comics; SourceInfo? _activeSource;
int _page, _total, _totalPages, _requestSerial;   // race-guard manual
bool _isFirstPageLoading, _isLoadingMore, _hasLoadedCatalog;
Future<void> _loadFirstPage() { ...setState... }   // fetch + pagination di widget
```

**After**
```dart
features/catalog/controller/catalog_controller.dart:
  CatalogState (immutable)                         // comics, page, total, totalPages, isLoadingMore
  CatalogFilterController : Notifier<...>          // apply() / clear()
  CatalogController       : AsyncNotifier<CatalogState>  // build() watch filter, loadNextPage(), refresh()

features/search/controller/search_filter_controller.dart:
  SearchFilterController  : Notifier<ComicFilterSortState>
```
- Race-guard `_requestSerial` hilang (digantikan rebuild `build()` + cek state terkini).
- Search hanya filter (Notifier) karena filtering-nya client-side — TIDAK perlu AsyncNotifier.
- Sisa `setState` di kedua screen = ephemeral UI saja (`_isGrid`, debounce, indikator filter).

Perilaku dipertahankan: merge-on-refresh, dedup key, snackbar load-more & refresh-failure.

---

## 8. Pecah `library_shared_panes.dart` (lanjutan bagian 4)

Setelah duplikasi pane-nya disatukan (bagian 4), file induknya yang masih monolitik akhirnya dipecah.

**Before**
```
library/library_shared_panes.dart   1445 baris (2 pane publik + semua widget offline + actions + model)
```

**After**
```
library/library_shared_panes.dart    265 baris (library: imports + FavoriteScenesPane + OfflineDownloadsPane)
library/panes/
  offline_pane_scaffold.dart          (typedef pane + konstanta copy offline + _SubHeader)
  offline_groups.dart                 (model _OfflineChapterGroup/_DownloadEntryGroup + helper grouping/key)
  scene_widgets.dart                  (_SceneCard, _showScenePreview)
  offline_chapter_widgets.dart        (_OfflineBatchTile, _OfflineChapterTile, group tile/screen, badge, hint)
  download_entry_widgets.dart         (_DownloadEntryTile, group tile/screen)
  offline_actions.dart                (refresh* publik + _open*/_showMessage/navigasi)
```
Via `part`/`part of` — zero perubahan API. Nama file utama dipertahankan, importer (`library_screen`, `settings_screen`) tak disentuh.

---

## 9. Bottom/Top Fade → `AppEdgeFade` global (revisi keputusan bagian 6)

Bagian 6 sempat menyatakan fade "TIDAK disatukan". Setelah ditinjau ulang per-keluarga, varian yang strukturnya sama (Keluarga A & B) disatukan; hanya varian reader (kurva hitam `pow()`) yang tetap lokal.

**Before** — 5 implementasi gradient tersebar (3 bottom + 2 top).
```dart
BottomViewportFade / _ComicDetailBottomFade / _NotificationsBottomFade   // beda height/stops/alpha
_HomeTopViewportFade (AnimatedOpacity+visible) / _SearchTopFade (DecoratedBox)
```

**After** — 1 komponen global ber-parameter.
```dart
widgets/app_edge_fade.dart → AppEdgeFade(
  background, edge: top/bottom, height, midStop, midAlpha,
  opacity, opacityDuration, opacityCurve)   // opacity utk varian home yg teranimasi
```
Dipakai 9 pemanggil di 6 modul (comic, notifications, home ×2 + app-bar, library ×2, search).
Tampilan tiap call site dipertahankan persis (nilai lewat parameter).
**Keluarga C (reader)** sengaja tetap lokal — gradien kurva hitam berbeda fundamental.

---

## 10. Helper Navigasi → `core/navigation_helpers.dart`

**Before** — route string `/comic/` & `/reader/` diduplikat di banyak file.
```dart
// home, library, search, offline_actions, catalog, comic_section, reader — masing-masing:
void _openComicDetail(ctx, comic) {
  context.push('/comic/${Uri.encode(comicRouteSource(comic))}/...', extra: comic);
}
// _openComicDetail(BuildContext,ComicSummary) IDENTIK byte-per-byte di 7 lokasi
```

**After**
```dart
helpers/navigation_helpers.dart:   // dipindah dari core/ di bagian 18
  openComicDetail(ctx, comic)
  openReaderForComic(ctx, comic, chapterNumber)
  openReaderForProgress(ctx, progress, {includeLatestChapter})  // jembatani beda 1-baris home vs library
```
Semua call site jadi delegasi tipis `=> openX(...)`; 4 import `go_router` yang jadi yatim dipangkas.

> **Update (audit lanjutan):** ternyata 3 call-site terlewat saat refactor awal — masih menulis
> literal route. Sudah ditambal jadi delegasi: `linked_sources_card` (`/comic/` → `openComicDetail`),
> `offline_actions._openSceneReader` & `_openOfflineChapter` (`/reader/` → `openReaderForComic`).
> Sengaja DIBIARKAN (bukan duplikat sejati, hindari over-engineering): 2 literal di
> `reader_screen_state` (pakai `pushReplacement`/`go` + logika `canPop`/fallback `/`, beda perilaku
> dari helper yang pakai `push`) dan `home_helpers` route section `/comic/.../section/...`
> (pemanggil tunggal, tak ada duplikat). Sisa literal `/library/...`, `/auth/...` di `repositories/`
> adalah **API endpoint paths** (HTTP backend), bukan route navigasi — di luar cakupan ini.

---

## 11. Pecah Screen Monolitik notifications & onboarding (SoC)

Dua screen terakhir yang belum mengikuti pola subfolder modul lain.

**Before**
```
notifications/notifications_screen.dart   817 baris (13 class)
onboarding/onboarding_screen.dart         550 baris (9 class)
```

**After**
```
notifications/  notifications_screen.dart (27) + controller/ + widgets/ (×2) + helpers/ + models/
onboarding/     onboarding_screen.dart (20)    + controller/ + widgets/ + models/
```
Via `part`/`part of` — zero perubahan perilaku. Kini 12/12 modul fitur menerapkan SoC.

---

## 12. Konfirmasi setState vs Notifier (via Context7)

Divalidasi dokumentasi resmi Riverpod (`/rrousselgit/riverpod`): *providers untuk shared business
state; ephemeral state (toggle, form, animasi) pakai `setState`/hooks — kalau salah scope bisa
merusak tombol back*. Audit kode terkini:
- ✅ filter + pagination catalog/search SUDAH di Notifier/AsyncNotifier (bagian 7).
- ✅ Sisa `setState` (grid toggle, `_isSearching`, indikator filter) memang ephemeral → **tepat dipertahankan**.

Kesimpulan: tidak ada migrasi `setState` lanjutan yang diperlukan — kondisi sudah sesuai prinsip.

---

## 13. Prioritas 1 — Pecah File Infrastruktur + Tutup Duplikat Formatter

Audit ulang menemukan blind spot: 4 file terbesar codebase justru di luar `features/`
(`providers.dart`, `library_repository.dart`, `reader_controller.dart`, `comic_card.dart`).
Plus 2 screen yang ternyata MASIH monolitik (klaim "12/12 modul SoC" di bagian 1 tidak akurat).
Sesi ini mengerjakan yang ROI-nya tertinggi & paling aman. Semua via `part`/`part of` —
zero perubahan API, importer tak disentuh. `flutter analyze lib` = **No issues found**.

**13a. `_compactNumber` duplikat → dihapus**
```
features/comic/helpers/comic_detail_formatters.dart : _compactNumber()  // K/M, tanpa "B"
  → dihapus; call-site comic_detail_view_models.dart pakai formatCompactCount() global
```
Menutup utang bagian 5.

**13b. Pecah `providers.dart` (grab-bag ~50 provider)**

**Before**
```
repositories/providers.dart   1603 baris (auth + catalog + library + offline + notif + UI + reader + core campur)
```
**After**
```
repositories/providers.dart            134 baris (imports + core wiring: config, api, store, semua repository provider)
repositories/providers/
  auth_providers.dart          146     (AuthController + security overview)
  catalog_providers.dart       223     (source/genre/home/comic/chapter/progress)
  library_providers.dart       286     (bookmarks, collections, history, PaginatedAsyncController)
  offline_providers.dart       447     (OfflineQueueController — download batch)
  settings_providers.dart      223     (theme, reading-time, reader prefs)
  notification_providers.dart  147     (push prefs + NotificationsController)
  search_providers.dart         22     (query + results)
```
Part file berbagi 1 library scope → cross-reference antar grup (mis. catalog watch auth) resolve tanpa wiring tambahan.

**13c. Pecah `search_screen.dart` (monolit 916 baris)**
```
search_screen.dart   916 → 430 baris (screen + state logic)
  models/search_view_models.dart        (_SearchComicUi)
  widgets/search_input.dart             (_SearchBox, _SearchStickyControls)
  widgets/search_results.dart           (grid/list/tile + _openComicDetail)
  widgets/search_shimmers.dart          (loading placeholders)
  widgets/search_states.dart            (empty/error/centered/section title/filter strip)
```

**13d. Pecah `full_catalog_screen.dart` (monolit 791 baris)**
```
full_catalog_screen.dart   791 → 297 baris (screen + state logic)
  models/catalog_view_models.dart       (_CatalogEntry)
  widgets/catalog_hero.dart             (_CatalogHero, _SortPill)
  widgets/catalog_lists.dart            (_CatalogGrid, _CatalogList, _LoadMoreFooter)
  widgets/catalog_states.dart           (loading/error/empty/filter indicator/shimmer)
```
Catalog kini ikut pola subfolder SoC seperti modul lain → klaim "12/12 modul" (bagian 1/11) akhirnya benar-benar tercapai.

> Blind spot Prioritas 2+: `comic_card.dart` SUDAH dipecah (lihat bagian 16).
> Yang masih ditunda: `library_repository.dart` (string-similarity & guest-migration)
> dan `reader_controller.dart` (god-object) — risiko regresi tinggi vs. frekuensi sentuh rendah.

---

## 14. Load-More Footer → `LoadMoreFooter` global (revisi keputusan bagian 6)

Bagian 6 sempat menyatakan load-more footer "TIDAK disatukan (catalog punya spinner)".
Ditinjau ulang: yang catalog tulis ulang sebenarnya cuma blok teks "selesai" (byte-identik
dengan `SectionLoadMoreFooter` yang sudah dipakai 4 call-site). Spinner-nya memang beda,
tapi itu concern terpisah — di home section pun spinner sudah jadi sliver tersendiri.

**Before**
```
features/home/section/section_shared.dart : SectionLoadMoreFooter (teks-selesai, dipakai 4×)
features/catalog/.../catalog_lists.dart   : _LoadMoreFooter (spinner + teks-selesai + guard totalCount)
                                            // blok teks-selesai duplikat byte-per-byte
```

**After**
```
widgets/load_more_footer.dart → LoadMoreFooter (teks-selesai, nama umum lintas-halaman)
  → dipakai 5 call-site di 3 modul: home (comic_section, continue_reading),
    library (bookmarks, history), catalog
catalog: spinner dipisah jadi sliver _CatalogLoadingMore di atas footer (ikut pola section)
```
`section_shared.dart` dihapus; `SectionLoadMoreFooter` → `LoadMoreFooter` (pindah ke `widgets/`).
**Catatan perilaku:** guard `totalCount` catalog dihapus (redundant — `hasNextPage` dari
controller sudah jadi sumber kebenaran, `loadedCount == 0` cegah teks di list kosong).

---

## 15. Source Badge → `SourceTag` + `ComicSourceBadge(prominent:)` (revisi keputusan bagian 6)

Bagian 6 menyebut "source badge (3 gaya)". Audit ulang menemukan **5 rendering**, mengelompok
jadi 3 keluarga. 2 keluarga layak disatukan; 1 (inline list) sengaja tetap lokal.

**Before** — 5 kelas tersebar
```
widgets/comic_card.dart         : ComicSourceBadge (overlay gelap, radius 14)        [Keluarga B]
                                  _ComicListSource (inline, tanpa pill)              [Keluarga C]
comic/.../detail_hero.dart      : _SourceInfoBadge (overlay gelap + border, radius 18) [Keluarga B]
library/.../library_bookmark.dart: _SourceBadge (pill secondaryContainer)            [Keluarga A]
                                   _LinkedSourceBadge (pill tertiaryContainer + ikon link) [Keluarga A]
```

**After**
```
Keluarga A → widgets/source_tag.dart → SourceTag(sourceName, style: primary|linked)
  → ganti _SourceBadge + _LinkedSourceBadge; dipakai 3 call-site (bookmark ×2, dialog)
Keluarga B → ComicSourceBadge(label, prominent: false|true)
  → param `prominent` membundel beda border/radius/padding/ikon/teks;
    _SourceInfoBadge dihapus, hero pakai ComicSourceBadge(prominent: true)
Keluarga C → _ComicListSource TETAP lokal (idiom inline list, bukan pill — bukan duplikat)
```
2 kelas Keluarga A + 1 kelas Keluarga B dihilangkan. Tampilan tiap call-site dipertahankan persis
(nilai lewat parameter/style). Keluarga C tetap lokal sesuai keputusan.

---

## 16. Pecah `comic_card.dart` (blind spot Prioritas 2)

Salah satu dari 4 file terbesar di luar `features/` (lihat bagian 13). Hub widget global
yang di-import banyak fitur, tapi mencampur kartu + shimmer + 6 badge + 6 sub-widget list +
8 helper fungsi dalam 1 file.

**Before**
```
widgets/comic_card.dart   1204 baris (~25 deklarasi tercampur)
```

**After**
```
widgets/comic_card.dart   281 baris (ComicCard grid + painter/clipper chapter-badge tightly-coupled)
widgets/comic_card/
  comic_list_card.dart        480   (ComicListCard + 6 sub-widget list:
                                      _ComicListSource, _ComicListGenreStrip, _ComicUpdateTime,
                                      _ComicListViewCount, _ComicLatestChapterBadge, _ComicListRatingBadge)
  comic_badges.dart           246   (6 badge publik: ComicNewBadge, ComicSourceBadge, ComicMetaBadge,
                                      ComicTypeFlagBadge, ComicGenreBadge, ComicStatusBadge)
  comic_card_shimmers.dart     81   (ComicListCardShimmer, ComicGridCardShimmer)
  comic_card_formatters.dart  124   (helper: comicSourceNameLabel, comicGenreColor, comicStatusStyle,
                                      _formatCompactMetric, dll + ComicStatusStyle)
```
Via `part`/`part of` — zero perubahan API. Pakai `part` (bukan import publik) karena banyak member
privat (`_formatCompactMetric`, `_comicStatusLabel`, painter grid) saling dipakai antar-grup;
import publik akan memaksa banyak hal jadi publik = ubah API. Painter/clipper chapter-badge
sengaja tetap di file utama (hanya dipakai `ComicCard`, tightly-coupled posisi grid).

> Sisa blind spot Prioritas 2+: `library_repository.dart` SUDAH dipecah (lihat bagian 17).
> Yang masih ditunda: `reader_controller.dart` (god-object) — risiko regresi tinggi vs.
> frekuensi sentuh rendah.

---

## 17. Pecah `library_repository.dart` (blind spot Prioritas 2)

File terbesar codebase: 1 kelas raksasa `LibraryRepository` mencampur data access (remote/lokal)
+ algoritma title-similarity + bookmark-linking + guest-migration.

**Before**
```
repositories/library_repository.dart   1800 baris (1 kelas, ~40 method + helper + _LocalBookmarkLink)
```

**After**
```
repositories/library_repository.dart   443 baris (kelas inti: fields, constructor, _isLoggedIn,
                                         comic-state, bookmarks dasar, reader prefs, summary,
                                         semua _local* reader bersama, _LocalBookmarkLink)
repositories/library/
  bookmark_links_repository.dart  603   (extension: scan kandidat, save links, read-status sync + propagasi)
  collections_repository.dart     229   (extension: CRUD collections + membership)
  scenes_downloads_repository.dart 295  (extension: favorite scenes, history, downloads, reading-time)
  guest_migration_repository.dart 230   (extension: ringkasan + import snapshot guest→cloud)
core/string_similarity.dart        43   (fungsi pure titleSimilarity — reusable, testable)
```

Beda dari split widget/screen: ini 1 kelas, bukan kumpulan kelas. Dipecah lewat **extension dalam
`part`** pada `LibraryRepository` — divalidasi via Context7 (privasi Dart = library-level, jadi
extension di part bisa akses & memutasi field privat instance: `_api`, `_store`, state scan bookmark).

Keputusan & jebakan yang ditemukan:
- **Konstanta** `static const` → top-level private constant (static class member tak ter-resolve
  via bare-name dari extension).
- **`title-similarity` diekstrak jadi fungsi pure** di `core/` (tanpa dep instance → importable & testable).
- **`providers.dart` menambah `export 'library_repository.dart'`**: extension method butuh
  defining-library dalam scope di call-site; call-site mengimpor `providers.dart`, bukan repository
  langsung. Satu baris export menutup semua call-site tanpa menyentuh kodenya.
- **Test-seam tetap di kelas inti**: `getBookmarks` + `getReaderPreferences`/`saveReaderPreferences`
  TIDAK boleh jadi extension — `_FakeLibraryRepository implements LibraryRepository` meng-`@override`-nya,
  dan extension method bukan anggota interface (tak bisa di-override, resolve statis ke extension asli).
  Pasangan reader-prefs dikembalikan ke kelas inti karena ini.

Zero perubahan API & perilaku. `flutter analyze` (lib + test) = **No issues found**.

> **Update validasi:** kegagalan test lama karena Firebase/push service sudah ditutup lewat seam
> push notification di bagian 21. Test suite penuh sekarang hijau: **100 tests passed**.

---

## 18. Reorganisasi `core/` → `core/` + `utils/` + `helpers/`

`core/` sempat jadi "double duty" — mencampur infrastruktur/service, util murni, dan helper UI.
Dipecah jadi 3 folder berdasarkan **ketergantungan**: butuh layer Flutter UI atau tidak.

**Before**
```
core/   (21 file campur: service + util + helper)
```

**After**
```
core/      infrastruktur/service (api_client, storage, token_store, config, push_* ×4,
           reader_image_cache, app_update_service, app_theme, app_navigation, avatar_image)
utils/     util murni — Dart polos tanpa Flutter UI:
           string_similarity, formatters, app_assets, app_error (hanya `foundation`)
helpers/   helper app-coupled — butuh BuildContext/Flutter:
           navigation_helpers, app_snackbar, app_responsive, app_icons
```

Kriteria pembagian (berbasis import nyata, bukan tebakan):
- **`utils/`** = tanpa `package:flutter` UI → benar-benar reusable & testable tanpa harness widget.
- **`helpers/`** = butuh `BuildContext`/widget/route → glue level-app, sengaja TIDAK di `utils/`
  (mis. `navigation_helpers` pakai `go_router` + route string app — bukan util generik).
- **`core/`** = sisanya: service stateful & wiring infrastruktur.

8 file dipindah via `git mv` (rename terlacak, blame utuh). 66 baris import disesuaikan di ~32 file.
Jebakan yang ditemukan: `main.dart` & `app.dart` pakai path non-`../core/` (tak tertangkap sed
massal, diperbaiki manual); `app_error` di-import bare oleh 2 service push yang tetap di `core/`
(jadi `../utils/app_error.dart`); `app_snackbar`→`app_error` lintas folder baru (`../utils/`).

> Catatan: `features/*/helpers/` (helper per-fitur, mis. `comic_detail_formatters`) berbeda dari
> `helpers/` global ini — yang global hanya helper app-coupled lintas-fitur.

Zero perubahan API & perilaku. `flutter analyze` (lib + test) = **No issues found**.

---

## 19. Satukan Genre-Cache Duplikat (search ↔ catalog)

Audit ulang menemukan duplikasi sejati yang lolos dari §13: trio helper genre-options di
`search_screen` & `full_catalog_screen` **byte-identik kecuali 1 string log**.

**Before**
```dart
// search_screen.dart & full_catalog_screen.dart — masing-masing punya:
List<String> _cachedGenreOptions() { ...getCachedGenres()... }
Future<List<String>> _refreshGenreOptions() async { ...refreshGenres() + snackbar... }
List<String> _genreNames(List<Genre>) { ... }
// ~30 baris duplikat; beda cuma logContext 'search' vs 'catalog'
```

**After**
```dart
helpers/genre_options.dart:
  cachedGenreOptionNames(ref)
  refreshGenreOptionNames(ref, context, {required logContext})   // snackbar guard pakai context.mounted
```
Kedua screen jadi delegasi tipis; `Genre`-mapping & error-handling kini 1 sumber. Di `helpers/`
(bukan `utils/`) karena butuh `BuildContext` + provider. `logContext` lewat parameter mempertahankan
label log per-screen. Efek samping bersih: `providers.dart` jadi yatim di catalog → dipangkas.

Zero perubahan perilaku. `flutter analyze lib` = **No issues found**.

> Audit juga menemukan (TIDAK dikerjakan, sengaja): pagination `comic_section` ↔ `continue_reading`
> tampak duplikat tapi **dangkal** (beda load-bearing: cached-first-page, multi-source, side-effect
> LatestStats) — mixin/AsyncNotifier bersama = abstraksi dipaksakan. Penamaan folder `controller/`
> yang menyesatkan SUDAH dikoreksi — lihat bagian 20.

---

## 20. Rename Folder `controller/` → `state/` untuk Widget-State (koreksi penamaan)

Audit bagian 19 menemukan penamaan menyesatkan: 6 dari 8 file di folder `controller/` sebenarnya
`ConsumerState<Screen>` (widget state via `part of`), **bukan** controller/Notifier. Hanya search &
catalog yang punya controller asli (`Notifier`/`AsyncNotifier`).

**Before → After**
```
features/auth/controller/auth_controller.dart                 → state/auth_screen_state.dart
features/home/controller/home_controller.dart                 → state/home_screen_state.dart
features/notifications/controller/notifications_controller.dart → state/notifications_screen_state.dart
features/onboarding/controller/onboarding_controller.dart     → state/onboarding_screen_state.dart
features/reader/controller/reader_controller.dart             → state/reader_screen_state.dart
features/settings/controller/settings_controller.dart         → state/settings_screen_state.dart

TETAP di controller/ (controller asli):
features/search/controller/search_filter_controller.dart   (SearchFilterController : Notifier)
features/catalog/controller/catalog_controller.dart        (CatalogController : AsyncNotifier)
```
6 file `git mv` (rename terlacak); tiap file `part of '../X_screen.dart'` → cuma direktif `part`
di file induk yang diperbarui (`part 'controller/...'` → `part 'state/...'`). `state/` & `controller/`
sama-sama 1 level di bawah feature, jadi `part of '../'` tetap valid. Kini `controller/` = controller
sejati, `state/` = widget state — konvensi konsisten.

Zero perubahan API & perilaku. `flutter analyze` (lib + test) = **No issues found**.

---

## 21. Push Notification Seam: Auth/App Tidak Bergantung ke Firebase Konkret

Audit validasi pasca-refactor menemukan coupling yang masih bocor: `AuthController`,
`TonztoonApp`, dan settings row membaca `remotePushNotificationServiceProvider` langsung.
Efeknya, unit/widget test yang hanya ingin menguji auth/routing/preference bisa ikut membuat
`RemotePushNotificationService`, lalu menyentuh `FirebaseMessaging.instance` sebelum Firebase app
tersedia.

**Before**
```dart
// auth/app/settings langsung bergantung ke service konkret
ref.read(remotePushNotificationServiceProvider).syncRegistration();
ref.read(remotePushNotificationServiceProvider).initialize();
ref.read(remotePushNotificationServiceProvider).requestPermissions();

// constructor service eager menyentuh FirebaseMessaging.instance
_messaging = messaging ?? FirebaseMessaging.instance;
```

**After**
```dart
abstract interface class PushRegistrationService {
  Future<bool> requestPermissions();
  Future<void> syncRegistration();
  Future<void> unregisterDevice();
}

abstract interface class PushNotificationLifecycleService {
  Future<void> initialize();
}

final pushRegistrationServiceProvider = Provider<PushRegistrationService>(...);
final pushNotificationLifecycleServiceProvider =
    Provider<PushNotificationLifecycleService>(...);
```

Call site sekarang bergantung ke kontrak:
```
app.dart                         → pushNotificationLifecycleServiceProvider.initialize()
auth_providers.dart              → pushRegistrationServiceProvider.sync/unregister
settings/widgets/settings_rows   → pushRegistrationServiceProvider.requestPermissions()
notification_providers.dart      → preferensi push sync/unregister via PushRegistrationService
```

`RemotePushNotificationService` tetap implementasi produksi, tetapi akses ke
`FirebaseMessaging.instance` dibuat lazy (`_firebaseMessaging`) setelah bootstrap FCM berhasil.
`initialize()` juga berhenti lebih awal jika `_startMessageListeners()` mengembalikan `false`,
sehingga drain/sync tidak berjalan saat FCM tidak tersedia.

Efek testability:
- `repository_test.dart` memakai noop push overrides untuk test auth/preference.
- `widget_test.dart` memakai noop lifecycle/registration service + auth guest controller siap-pakai.
- Assertion lama untuk fade detail comic disesuaikan dari key internal ke kontrak shared
  `AppEdgeFade(edge: bottom, height: 120)`.

Hasilnya: test tidak lagi bergantung pada Firebase runtime untuk jalur yang tidak sedang menguji
push notification.

---

## Yang BELUM / TIDAK Dilakukan (jujur)

| Item | Status | Catatan |
|------|--------|---------|
| **Aksi mutasi → controller** | ➖ Tidak perlu | bookmark/collection/favorite/download dipanggil `ref.read(repo).xxx()` dari UI. Ditinjau ulang: polanya `delete + invalidate(provider) + snackbar` — mutasi sederhana, 1 call-site/aksi, tanpa shared state, dan snackbar/error butuh `BuildContext` (justru TIDAK boleh masuk Notifier). Library juga belum punya `controller/`, jadi memindahkannya = menciptakan layer baru hanya untuk membungkus 1 baris invalidate = boilerplate, bukan SoC. Pindahkan HANYA jika nanti butuh optimistic update / dipakai >1 tempat / pakai Mutation API. |
| **Pisah Login/Register jadi 2 screen** | ❌ Tidak | Keputusan: tetap 1 layar dengan toggle. |
| **Satukan load-more footer** | ✅ Selesai | Disatukan jadi `LoadMoreFooter` global (5 call-site, 3 modul) — lihat bagian 14. |
| **Satukan source-badge** | ✅ Sebagian | Keluarga A→`SourceTag`, Keluarga B→`ComicSourceBadge(prominent:)` — lihat bagian 15. Keluarga C (inline list) sengaja tetap lokal. |
| **Migrasi state reader/home** | ❌ Tidak | `setState` di sana mayoritas animasi/scroll/viewport — memang ephemeral (dikonfirmasi bagian 12). |
| **Push notification seam** | ✅ Selesai | Auth/app/settings kini bergantung ke interface kecil, bukan implementasi Firebase konkret — lihat bagian 21. |
| **Pecah `reader_screen_state.dart` lebih lanjut** | ➖ Ditunda | Masih file terbesar (~1400 baris). Kandidat refactor berikutnya, tapi perlu hati-hati karena menyentuh gesture, pagination, progress sync, dan deep-link reader. |

---

## Catatan Verifikasi

Validasi otomatis terakhir:

```text
flutter analyze lib test
No issues found

flutter test --reporter compact --timeout 2x
100 tests passed

git diff --check
No whitespace errors
```

Catatan: `git diff --check` hanya menampilkan warning normalisasi line ending `LF will be replaced
by CRLF` di Windows/Git config, bukan whitespace error.

Analyze dan test hijau, tetapi tetap disarankan tes manual di device untuk:
scroll-to-load & pull-refresh katalog, ganti/reset filter (indikator "Memproses hasil filter..."),
dan alur auth (forgot/reset/callback).

Khusus Prioritas 1 (bagian 13) — pemindahan kode murni tanpa ubah logika, risiko rendah,
tapi tetap smoke-test: layar search (debounce, grid/list toggle, filter sheet), katalog
(scroll-to-load, pull-refresh, filter), dan angka total view di comic detail (kini drop ".0").

Prioritas 2 (bagian 14–15) — penyatuan widget tampilan, tetap smoke-test:
- Load-more footer: scroll katalog/section/bookmark/history sampai habis (teks "selesai" muncul
  sekali) & saat load-more (spinner di atas, tidak dobel dengan teks).
- Source badge: tab bookmark library (badge sumber + sumber-tertaut), dialog scan kandidat,
  cover grid card, home recommendation, dan hero comic detail (badge besar berbingkai).
- Pecah `comic_card.dart` (bagian 16): grid card (home/catalog/search), list card (catalog/search
  list-mode), shimmer loading, dan semua badge (tipe/genre/status/new/meta).

Pecah `library_repository.dart` (bagian 17) — menyentuh banyak alur kritis, smoke-test lebih teliti:
toggle bookmark, scan & save bookmark-links, comic detail (state merge), CRUD collection,
simpan/hapus favorite scene, download chapter, reader preferences, dan migrasi guest→cloud saat
login pertama.

Push notification seam (bagian 21) — smoke-test di Android device/emulator dengan konfigurasi
Firebase valid: toggle push notification di settings, login/logout, foreground notification,
tap notification deep link, dan token refresh/registrasi perangkat.
