import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/comic_filter_sort_sheet.dart';

/// Holds the active filter/sort selection for the search screen. Search
/// filtering is performed client-side over the already-fetched results, so
/// this only needs to expose the current selection — no fetching lives here.
final searchFilterProvider =
    NotifierProvider<SearchFilterController, ComicFilterSortState>(
      SearchFilterController.new,
    );

class SearchFilterController extends Notifier<ComicFilterSortState> {
  @override
  ComicFilterSortState build() {
    return const ComicFilterSortState(sort: ComicSortOption.relevance);
  }

  void apply(ComicFilterSortState filters) {
    state = filters.normalized();
  }
}
