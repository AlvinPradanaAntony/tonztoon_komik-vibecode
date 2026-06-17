part of '../providers.dart';

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    state = value;
  }
}

final searchResultsProvider = FutureProvider<List<ComicSummary>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (ref.watch(searchQueryProvider).trim() != query) return const [];
  return ref.watch(catalogRepositoryProvider).search(query);
});
