const libraryDownloadsLocation = '/library?tab=downloads';
const libraryBookmarksLocation = '/library';
const libraryCollectionsLocation = '/library?tab=collections';
const libraryScenesLocation = '/library?tab=scenes';
const libraryHistoryLocation = '/library?tab=history';

int libraryTabIndexFromName(String? tab) {
  return switch (tab) {
    'collections' || 'koleksi' => 1,
    'scenes' || 'scene' => 2,
    'history' || 'riwayat' => 3,
    'downloads' || 'unduhan' => 4,
    _ => 0,
  };
}

String libraryLocationForTabIndex(int index) {
  return switch (index) {
    1 => libraryCollectionsLocation,
    2 => libraryScenesLocation,
    3 => libraryHistoryLocation,
    4 => libraryDownloadsLocation,
    _ => libraryBookmarksLocation,
  };
}
