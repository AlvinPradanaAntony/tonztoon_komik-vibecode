part of '../providers.dart';

final selectedSourceProvider =
    NotifierProvider<SelectedSourceController, String?>(
      SelectedSourceController.new,
    );

class SelectedSourceController extends Notifier<String?> {
  @override
  String? build() {
    return ref.watch(localStoreProvider).settings.get('selected_source')
        as String?;
  }

  void select(String sourceName) {
    ref.read(localStoreProvider).settings.put('selected_source', sourceName);
    state = sourceName;
  }
}

final sourcesProvider = FutureProvider<List<SourceInfo>>((ref) {
  return ref.watch(catalogRepositoryProvider).getSources();
});

final genresProvider = FutureProvider<List<Genre>>((ref) {
  return ref.watch(catalogRepositoryProvider).getGenres();
});

class HomeData {
  const HomeData({
    required this.sources,
    required this.selectedSource,
    required this.latest,
    required this.popular,
    required this.recommendations,
    required this.topRanking,
    required this.continueReading,
  });

  final List<SourceInfo> sources;
  final SourceInfo selectedSource;
  final List<ComicSummary> latest;
  final List<ComicSummary> popular;
  final List<ComicSummary> recommendations;
  final List<ComicSummary> topRanking;
  final List<ReadingProgress> continueReading;
}

const _homePreviewPageSize = 6;

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(authControllerProvider);
  final repository = ref.watch(catalogRepositoryProvider);
  final progressRepository = ref.watch(progressRepositoryProvider);
  final sources = await repository.getSources();
  if (sources.isEmpty) {
    throw ApiException('No sources available.');
  }
  final selectedId = ref.watch(selectedSourceProvider);
  final selected = sources.firstWhere(
    (source) => source.id == selectedId,
    orElse: () => sources.first,
  );
  final results = await Future.wait([
    repository.getLatest(selected.id, pageSize: _homePreviewPageSize),
    repository.getPopular(selected.id, pageSize: _homePreviewPageSize),
    repository.getRecommendations(selected.id),
    repository.getTopRanking(selected.id),
    progressRepository.getContinueReading(pageSize: _homePreviewPageSize),
  ]);
  final latest = results[0] as List<ComicSummary>;
  unawaited(
    ref.read(notificationsProvider.notifier).recordLatestChapterUpdates(latest),
  );
  return HomeData(
    sources: sources,
    selectedSource: selected,
    latest: latest,
    popular: results[1] as List<ComicSummary>,
    recommendations: results[2] as List<ComicSummary>,
    topRanking: results[3] as List<ComicSummary>,
    continueReading: results[4] as List<ReadingProgress>,
  );
});

class TopRankingRequest {
  const TopRankingRequest({required this.sourceName, this.type});

  final String sourceName;
  final String? type;

  @override
  bool operator ==(Object other) {
    return other is TopRankingRequest &&
        other.sourceName == sourceName &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(sourceName, type);
}

final topRankingProvider =
    FutureProvider.family<List<ComicSummary>, TopRankingRequest>((
      ref,
      request,
    ) {
      return ref
          .watch(catalogRepositoryProvider)
          .getTopRanking(request.sourceName, type: request.type);
    });

class ComicRequest {
  const ComicRequest(this.sourceName, this.slug);

  final String sourceName;
  final String slug;

  @override
  bool operator ==(Object other) {
    return other is ComicRequest &&
        other.sourceName == sourceName &&
        other.slug == slug;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug);
}

final comicDetailProvider = FutureProvider.family<ComicDetail, ComicRequest>((
  ref,
  request,
) {
  return ref
      .watch(catalogRepositoryProvider)
      .getComicDetail(request.sourceName, request.slug);
});

final chaptersProvider =
    FutureProvider.family<List<ChapterListItem>, ComicRequest>((ref, request) {
      return ref
          .watch(catalogRepositoryProvider)
          .getChapters(request.sourceName, request.slug);
    });

final progressProvider = FutureProvider.family<ReadingProgress?, ComicRequest>((
  ref,
  request,
) {
  ref.watch(authControllerProvider);
  return ref
      .watch(progressRepositoryProvider)
      .getProgress(request.sourceName, request.slug);
});

final continueReadingProvider = FutureProvider<List<ReadingProgress>>((ref) {
  ref.watch(authControllerProvider);
  ref.watch(continueReadingRefreshSignalProvider);
  return ref
      .watch(progressRepositoryProvider)
      .getContinueReading(pageSize: _homePreviewPageSize);
});

final continueReadingRefreshSignalProvider =
    NotifierProvider<ContinueReadingRefreshSignalController, int>(
      ContinueReadingRefreshSignalController.new,
    );

class ContinueReadingRefreshSignalController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

class ChapterRequest extends ComicRequest {
  const ChapterRequest(super.sourceName, super.slug, this.chapterNumber);

  final double chapterNumber;

  @override
  bool operator ==(Object other) {
    return other is ChapterRequest &&
        other.sourceName == sourceName &&
        other.slug == slug &&
        other.chapterNumber == chapterNumber;
  }

  @override
  int get hashCode => Object.hash(sourceName, slug, chapterNumber);
}

final chapterProvider = FutureProvider.family<ChapterPayload, ChapterRequest>((
  ref,
  request,
) async {
  final offline = await ref
      .watch(offlineRepositoryProvider)
      .getOfflinePayload(
        request.sourceName,
        request.slug,
        request.chapterNumber,
      );
  if (offline != null) return offline;

  try {
    return await ref
        .watch(catalogRepositoryProvider)
        .getChapter(request.sourceName, request.slug, request.chapterNumber);
  } catch (_) {
    final fallback = await ref
        .watch(offlineRepositoryProvider)
        .getOfflinePayload(
          request.sourceName,
          request.slug,
          request.chapterNumber,
        );
    if (fallback != null) return fallback;
    rethrow;
  }
});
