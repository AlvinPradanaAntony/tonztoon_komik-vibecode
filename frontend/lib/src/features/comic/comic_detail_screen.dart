import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/app_icons.dart';
import '../../helpers/app_responsive.dart';
import '../../helpers/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../models/auth.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../helpers/navigation_helpers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/bookmark_status_picker.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/source_tag.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import '../library/library_screen.dart';

part 'models/comic_detail_view_models.dart';
part 'helpers/comic_detail_formatters.dart';
part 'dialogs/collection_picker_dialog.dart';
part 'dialogs/download_picker_dialog.dart';
part 'widgets/detail_hero.dart';
part 'widgets/detail_title_section.dart';
part 'widgets/linked_sources_card.dart';
part 'widgets/chapter_panel.dart';
part 'widgets/bottom_read_bar.dart';
part 'widgets/detail_info_tiles.dart';
part 'widgets/detail_shimmers.dart';

class ComicDetailScreen extends ConsumerStatefulWidget {
  ComicDetailScreen({
    super.key,
    ComicSummary? comic,
    String? sourceName,
    String? slug,
    ComicSummary? initialComic,
  }) : initialComic = initialComic ?? comic,
       sourceName = sourceName ?? comic?.sourceName ?? 'komiku',
       slug = slug ?? comic?.slug ?? '';

  final ComicSummary? initialComic;
  final String sourceName;
  final String slug;

  @override
  ConsumerState<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends ConsumerState<ComicDetailScreen> {
  static const double _titleFadeStart = 150;
  static const Duration _minimumBookmarkLoadingDuration = Duration(
    milliseconds: 250,
  );
  static const double _titleFadeDistance = 90;

  late final ScrollController _scrollController;
  double _collapseProgress = 0;
  ValueNotifier<double>? _collapseProgressNotifier;
  bool _bookmarkBusy = false;
  bool _bookmarkStatusBusy = false;
  bool? _bookmarkOverride;
  bool _collectionBusy = false;
  bool _downloadBusy = false;
  bool _readSyncBusy = false;
  bool _bookmarkLinkBusy = false;

  ValueNotifier<double> get _toolbarProgress =>
      _collapseProgressNotifier ??= ValueNotifier<double>(_collapseProgress);

  @override
  void initState() {
    super.initState();
    _collapseProgressNotifier = ValueNotifier<double>(_collapseProgress);
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _collapseProgressNotifier?.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final nextProgress =
        ((_scrollController.offset - _titleFadeStart) / _titleFadeDistance)
            .clamp(0.0, 1.0);

    if ((nextProgress - _collapseProgress).abs() < 0.02) return;

    _collapseProgress = nextProgress;
    _toolbarProgress.value = nextProgress;
  }

  @override
  Widget build(BuildContext context) {
    final request = ComicRequest(widget.sourceName, widget.slug);
    final detailAsync = ref.watch(comicDetailProvider(request));
    final chaptersAsync = ref.watch(chaptersProvider(request));
    final progressAsync = ref.watch(progressProvider(request));
    final detailPayload = detailAsync.asData?.value;
    if (detailPayload == null) {
      return Scaffold(
        body: AppAsyncView<ComicDetail>(
          value: detailAsync,
          loadingBuilder: (context) => const _ComicDetailLoadingPlaceholder(),
          onRetry: () {
            ref.invalidate(comicDetailProvider(request));
            ref.invalidate(chaptersProvider(request));
          },
          builder: (_) => const SizedBox.shrink(),
        ),
      );
    }
    final chapterItems = chaptersAsync.asData?.value;
    final chaptersLoading = chaptersAsync.isLoading && chapterItems == null;
    final chaptersError = chaptersAsync.whenOrNull(
      error: (error, stackTrace) => error,
    );
    final detail = _ComicDetailUi.fromDetail(detailPayload).copyWith(
      chapters: chapterItems?.map(_ChapterUi.fromChapterItem).toList(),
    );
    final comic = detailPayload.toSummary();
    final libraryStateAsync = ref.watch(libraryComicStateProvider(comic));
    if (!libraryStateAsync.hasValue) {
      return Scaffold(
        body: AppAsyncView<LibraryComicState>(
          value: libraryStateAsync,
          loadingBuilder: (context) => const _ComicDetailLoadingPlaceholder(),
          onRetry: () => ref.invalidate(libraryComicStateProvider(comic)),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
    }
    final libraryState = libraryStateAsync.asData?.value;
    final isGuest =
        ref.watch(authControllerProvider).status == AuthStatus.guest;
    final effectiveBookmarked =
        _bookmarkOverride ?? (libraryState?.bookmarked == true);
    final bookmarkStatus = libraryState?.bookmarkOrigin?.status?.trim();
    final displayedStatus = bookmarkStatus?.isNotEmpty == true
        ? bookmarkStatus!
        : detail.status;
    final statusComic = libraryState?.bookmarkOrigin?.toSummary();
    if (_bookmarkOverride != null &&
        libraryState?.bookmarked == _bookmarkOverride) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bookmarkOverride == libraryState?.bookmarked) {
          setState(() => _bookmarkOverride = null);
        }
      });
    }
    final progress = progressAsync.asData?.value ?? libraryState?.progress;
    final completedChapterNumbers =
        libraryState?.completedChapterNumbers.toSet() ?? const <double>{};
    final downloadState = _ComicDownloadState.from(
      comic: comic,
      libraryState: libraryState,
      offlineChapters: ref.watch(offlineChaptersProvider).asData?.value,
      queue: ref.watch(offlineQueueProvider).asData?.value,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final expandedHeaderHeight = AppResponsive.heroHeaderHeight(context);
    final navigationOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('comic-detail-system-ui-overlay'),
      value: navigationOverlayStyle,
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: () async {
                  try {
                    ref.invalidate(comicDetailProvider(request));
                    ref.invalidate(chaptersProvider(request));
                    ref.invalidate(progressProvider(request));
                    ref.invalidate(libraryComicStateProvider(comic));
                    await Future.wait([
                      ref.read(comicDetailProvider(request).future),
                      ref.read(chaptersProvider(request).future),
                      ref.read(progressProvider(request).future),
                      ref.read(libraryComicStateProvider(comic).future),
                    ]);
                  } catch (error, stackTrace) {
                    if (!context.mounted) return;
                    showAppErrorSnackBar(
                      context,
                      error: error,
                      stackTrace: stackTrace,
                      logContext: 'Refresh comic detail failed',
                      fallbackMessage:
                          'Detail komik belum dapat dimuat ulang. Silakan coba lagi.',
                    );
                  }
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverAppBar(
                      automaticallyImplyLeading: false,
                      expandedHeight: expandedHeaderHeight,
                      pinned: true,
                      stretch: true,
                      elevation: 0,
                      centerTitle: true,
                      titleSpacing: 16,
                      surfaceTintColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.transparent,
                      leading: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Center(
                          child: _GlassIconButton(
                            tooltip: 'Kembali',
                            icon: TonztoonIcons.arrowBack,
                            progress: _toolbarProgress,
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go('/'),
                          ),
                        ),
                      ),
                      title: ValueListenableBuilder<double>(
                        valueListenable: _toolbarProgress,
                        builder: (context, progress, child) {
                          return IgnorePointer(
                            ignoring: progress == 0,
                            child: Opacity(
                              opacity: progress,
                              child: Text(
                                detail.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Color.lerp(
                                    Colors.white,
                                    colorScheme.onSurface,
                                    progress,
                                  ),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _GlassIconButton(
                            tooltip: _bookmarkBusy
                                ? 'Menyimpan bookmark'
                                : libraryState?.bookmarkRelation ==
                                      BookmarkRelation.linked
                                ? 'Bookmark terhubung dari source lain'
                                : effectiveBookmarked
                                ? 'Hapus bookmark'
                                : 'Simpan bookmark',
                            icon: effectiveBookmarked
                                ? TonztoonIcons.bookmarkFilled
                                : TonztoonIcons.bookmark,
                            isLoading: isGuest ? false : _bookmarkBusy,
                            progress: _toolbarProgress,
                            onPressed: () =>
                                _toggleBookmark(comic, libraryState),
                          ),
                        ),
                      ],
                      flexibleSpace: Stack(
                        fit: StackFit.expand,
                        children: [
                          FlexibleSpaceBar(
                            stretchModes: const [StretchMode.zoomBackground],
                            background: RepaintBoundary(
                              child: _DetailHero(detail: detail),
                            ),
                          ),
                          _CollapsingToolbarTint(
                            progress: _toolbarProgress,
                            color: colorScheme.surfaceContainerLowest,
                            collapsedStatusBarStyle: navigationOverlayStyle
                                .copyWith(
                                  statusBarIconBrightness: isDark
                                      ? Brightness.light
                                      : Brightness.dark,
                                  statusBarBrightness: isDark
                                      ? Brightness.dark
                                      : Brightness.light,
                                ),
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 22, 16, 136),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TitleBlock(
                                detail: detail,
                                status: displayedStatus,
                                onStatusTap: statusComic == null
                                    ? null
                                    : () => _showBookmarkStatusPicker(
                                        statusComic,
                                      ),
                                isStatusLoading: _bookmarkStatusBusy,
                              ),
                              if (libraryState != null &&
                                  (effectiveBookmarked ||
                                      libraryState.bookmarkRelation ==
                                          BookmarkRelation.linked ||
                                      libraryState
                                          .linkedComics
                                          .isNotEmpty)) ...[
                                const SizedBox(height: 12),
                                _LinkedSourcesCard(
                                  state: libraryState,
                                  currentComic: comic,
                                  isFindingSources: _bookmarkLinkBusy,
                                  onFindSources:
                                      effectiveBookmarked && !_bookmarkLinkBusy
                                      ? () => _findAndLinkBookmarkSources(comic)
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 18),
                              _QuickStats(detail: detail),
                              const SizedBox(height: 20),
                              _SectionHeader(
                                icon: TonztoonIcons.bookOpen,
                                title: 'Sinopsis',
                              ),
                              const SizedBox(height: 10),
                              Text(
                                detail.synopsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.55,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.82,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              _SectionHeader(
                                icon: TonztoonIcons.tags,
                                title: 'Genre',
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: detail.genres
                                    .map(
                                      (genre) => ComicGenreBadge(genre: genre),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 24),
                              _ChapterPanel(
                                chapters: detail.chapters,
                                downloadState: downloadState,
                                progress: progress,
                                completedChapterNumbers:
                                    completedChapterNumbers,
                                showReadSync:
                                    libraryState != null &&
                                    (libraryState.bookmarkRelation ==
                                            BookmarkRelation.linked ||
                                        libraryState.linkedComics.isNotEmpty),
                                readSyncBusy: _readSyncBusy,
                                loading: chaptersAsync.isLoading,
                                error: chaptersError,
                                onRetry: () =>
                                    ref.invalidate(chaptersProvider(request)),
                                onOpenChapter: (chapter) =>
                                    _openReaderAndRefresh(
                                      comic,
                                      request,
                                      detail,
                                      chapter,
                                    ),
                                onSyncReadStatus: () => _syncReadStatus(
                                  comic,
                                  libraryState,
                                  chapterItems ?? const [],
                                  progress,
                                  request,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AppEdgeFade(
              background: colorScheme.surfaceContainerLowest,
              height: 120,
              midStop: 0.62,
            ),
          ],
        ),
        bottomNavigationBar: _BottomReadBar(
          detail: detail,
          chaptersLoading: chaptersLoading,
          progress: progress,
          completedChapterNumbers: completedChapterNumbers,
          downloadState: downloadState,
          hasCollections: libraryState?.collections.isNotEmpty == true,
          downloadBusy: _downloadBusy,
          collectionBusy: _collectionBusy,
          onDownload: chapterItems == null || chapterItems.isEmpty
              ? null
              : () => _showDownloadSheet(comic, chapterItems, downloadState),
          onManageCollections: () => _showCollectionSheet(comic, libraryState),
          onContinueReading: () => _continueReading(
            comic,
            request,
            detail,
            progress,
            completedChapterNumbers,
          ),
        ),
      ),
    );
  }

  void _continueReading(
    ComicSummary comic,
    ComicRequest request,
    _ComicDetailUi detail,
    ReadingProgress? progress,
    Set<double> completedChapterNumbers,
  ) {
    final chapter = _continueChapter(detail, progress, completedChapterNumbers);
    if (chapter == null) {
      _showSnack('Chapter belum tersedia.');
      return;
    }
    _openReaderAndRefresh(comic, request, detail, chapter);
  }

  Future<void> _openReaderAndRefresh(
    ComicSummary comic,
    ComicRequest request,
    _ComicDetailUi detail,
    _ChapterUi chapter,
  ) async {
    await _openReader(context, detail, chapter);
    if (!mounted) return;
    ref.invalidate(progressProvider(request));
    ref.invalidate(libraryComicStateProvider(comic));
    ref.invalidate(continueReadingProvider);
  }

  Future<void> _syncReadStatus(
    ComicSummary comic,
    LibraryComicState? currentState,
    List<ChapterListItem> chapters,
    ReadingProgress? progress,
    ComicRequest request,
  ) async {
    if (_readSyncBusy) return;
    setState(() => _readSyncBusy = true);
    try {
      final state =
          currentState ??
          await ref.read(libraryComicStateProvider(comic).future);
      final result = await ref
          .read(libraryRepositoryProvider)
          .synchronizeReadStatusForComic(
            comic: comic,
            chapters: chapters,
            state: state,
            progress: progress,
          );
      if (!mounted) return;

      ref.invalidate(progressProvider(request));
      ref.invalidate(libraryComicStateProvider(comic));
      final origin = state?.bookmarkOrigin;
      if (origin != null) {
        ref.invalidate(libraryComicStateProvider(origin.toSummary()));
      }
      for (final linked in state?.linkedComics ?? const <LibraryComicRef>[]) {
        ref.invalidate(libraryComicStateProvider(linked.toSummary()));
      }
      ref.invalidate(continueReadingProvider);

      final synced = result.completedSynced;
      final propagated = result.completedPropagated;
      final message = synced == 0 && propagated == 0
          ? 'Belum ada status read lokal yang perlu disinkronkan.'
          : 'Status read disinkronkan: $synced chapter dikirim, $propagated chapter lokal ikut ditandai.';
      _showSnack(
        message,
        type: synced == 0 && propagated == 0
            ? AppSnackBarType.help
            : AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      _showErrorSnack(error, stackTrace, 'Manual read status sync failed');
    } finally {
      if (mounted) setState(() => _readSyncBusy = false);
    }
  }

  Future<void> _toggleBookmark(
    ComicSummary comic,
    LibraryComicState? currentState,
  ) async {
    if (_bookmarkBusy) return;
    if (currentState?.bookmarkRelation == BookmarkRelation.linked) {
      await _manageLinkedBookmark(comic, currentState!);
      return;
    }

    final isGuest = ref.read(authControllerProvider).status == AuthStatus.guest;
    final loadingStopwatch = isGuest ? null : (Stopwatch()..start());
    setState(() => _bookmarkBusy = true);

    bool? originalBookmarked;
    try {
      final currentBookmarked =
          _bookmarkOverride ??
          currentState?.bookmarked ??
          (await ref.read(libraryComicStateProvider(comic).future)).bookmarked;
      originalBookmarked = currentBookmarked;

      if (isGuest) {
        setState(() => _bookmarkOverride = !currentBookmarked);
      }

      final bookmarked = await ref
          .read(libraryRepositoryProvider)
          .toggleBookmark(comic, currentBookmarked);
      if (!mounted) return;
      setState(() => _bookmarkOverride = bookmarked);
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(bookmarksProvider);
      ref.invalidate(paginatedBookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      _showSnack(
        bookmarked ? 'Bookmark disimpan.' : 'Bookmark dihapus.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (mounted && isGuest && originalBookmarked != null) {
        setState(() => _bookmarkOverride = originalBookmarked);
      }
      _showErrorSnack(error, stackTrace, 'Toggle bookmark failed');
    } finally {
      if (loadingStopwatch != null) {
        await _waitForMinimumBookmarkLoading(loadingStopwatch);
      }
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  Future<void> _showBookmarkStatusPicker(ComicSummary comic) async {
    if (_bookmarkStatusBusy || _bookmarkBusy) return;

    final selectedStatus = await showBookmarkStatusPicker(context, comic);
    if (!mounted ||
        selectedStatus == null ||
        comic.status?.trim().toLowerCase() == selectedStatus) {
      return;
    }

    setState(() => _bookmarkStatusBusy = true);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .updateBookmarkStatus(comic, selectedStatus);
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(bookmarksProvider);
      ref.invalidate(paginatedBookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      if (mounted) {
        _showSnack(
          'Status ${comic.title} diubah menjadi ${bookmarkStatusLabel(selectedStatus)}.',
          type: AppSnackBarType.success,
        );
      }
    } catch (error, stackTrace) {
      _showErrorSnack(error, stackTrace, 'Update bookmark status failed');
    } finally {
      if (mounted) setState(() => _bookmarkStatusBusy = false);
    }
  }

  Future<void> _manageLinkedBookmark(
    ComicSummary comic,
    LibraryComicState state,
  ) async {
    final origin = state.bookmarkOrigin;
    if (origin == null) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bookmark terhubung'),
        content: Text(
          '${comic.title} dikenali sebagai komik yang sama dengan bookmark '
          '${origin.title} dari ${comicSourceNameLabel(origin.sourceName)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('unlink'),
            child: const Text('Putuskan source ini'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('Hapus bookmark utama'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;

    final loadingStopwatch = Stopwatch()..start();
    setState(() => _bookmarkBusy = true);
    try {
      final repository = ref.read(libraryRepositoryProvider);
      if (action == 'unlink') {
        await repository.unlinkComicSource(comic);
        _showSnack(
          'Source diputuskan dari bookmark.',
          type: AppSnackBarType.success,
        );
      } else {
        await repository.toggleBookmark(origin.toSummary(), true);
        _showSnack('Bookmark utama dihapus.', type: AppSnackBarType.success);
      }
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(libraryComicStateProvider(origin.toSummary()));
      ref.invalidate(bookmarksProvider);
      ref.invalidate(paginatedBookmarksProvider);
      ref.invalidate(librarySummaryProvider);
    } catch (error, stackTrace) {
      _showErrorSnack(error, stackTrace, 'Manage linked bookmark failed');
    } finally {
      await _waitForMinimumBookmarkLoading(loadingStopwatch);
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  Future<void> _waitForMinimumBookmarkLoading(Stopwatch stopwatch) async {
    final remaining = _minimumBookmarkLoadingDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _findAndLinkBookmarkSources(ComicSummary comic) async {
    if (_bookmarkLinkBusy) return;
    setState(() => _bookmarkLinkBusy = true);
    try {
      final candidates = await _scanBookmarkLinkCandidatesForComic(comic);
      if (!mounted) return;
      if (candidates.isEmpty) {
        _showSnack(
          'Belum ditemukan komik yang cukup mirip di source lain.',
          type: AppSnackBarType.help,
        );
        return;
      }

      final selected = await showBookmarkLinkCandidatesDialog(
        context,
        candidates,
      );
      if (!mounted || selected == null || selected.isEmpty) return;

      final result = await _saveBookmarkLinksWithProgress(selected);
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(bookmarksProvider);
      ref.invalidate(paginatedBookmarksProvider);
      ref.invalidate(librarySummaryProvider);
      for (final candidate in selected) {
        ref.invalidate(libraryComicStateProvider(candidate.comic.toSummary()));
        ref.invalidate(
          libraryComicStateProvider(candidate.bookmark.toSummary()),
        );
      }
      if (mounted) {
        _showSnack(
          '${result.linkedTotal} source dihubungkan dan '
          '${result.completedPropagated} status selesai disinkronkan.',
          type: AppSnackBarType.success,
        );
      }
    } catch (error, stackTrace) {
      _showErrorSnack(
        error,
        stackTrace,
        'Link bookmark sources from comic detail failed',
      );
    } finally {
      if (mounted) setState(() => _bookmarkLinkBusy = false);
    }
  }

  Future<List<BookmarkLinkCandidate>> _scanBookmarkLinkCandidatesForComic(
    ComicSummary comic,
  ) async {
    final dialogReady = Completer<BuildContext>();
    final dialogFuture = showTonztoonModal<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!dialogReady.isCompleted) dialogReady.complete(dialogContext);
        return const PopScope(
          canPop: false,
          child: TonztoonModalDialog(
            title: 'Mencari source lain',
            message: 'Mencocokkan komik ini dengan versi dari source berbeda.',
            eyebrow: 'Bookmark multi-source',
            helperText: 'Pencarian hanya dilakukan untuk bookmark ini.',
            helperIcon: TonztoonIcons.search,
            art: TonztoonModalArt.cloudSync,
            showActions: false,
            showCloseButton: false,
            content: LinearProgressIndicator(
              minHeight: 8,
              borderRadius: BorderRadius.all(Radius.circular(99)),
            ),
          ),
        );
      },
    );
    final dialogContext = await dialogReady.future;

    try {
      return await ref
          .read(libraryRepositoryProvider)
          .scanBookmarkLinkCandidatesForComic(comic);
    } finally {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await dialogFuture;
    }
  }

  Future<BookmarkLinkSaveResult> _saveBookmarkLinksWithProgress(
    List<BookmarkLinkCandidate> candidates,
  ) async {
    final progress = ValueNotifier<BookmarkLinkSaveProgress>(
      BookmarkLinkSaveProgress(
        stage: BookmarkLinkSaveStage.linking,
        completed: 0,
        total: candidates.length,
      ),
    );
    final dialogReady = Completer<BuildContext>();
    final dialogFuture = showTonztoonModal<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!dialogReady.isCompleted) dialogReady.complete(dialogContext);
        return PopScope(
          canPop: false,
          child: BookmarkLinkProgressDialog(progress: progress),
        );
      },
    );
    final dialogContext = await dialogReady.future;

    try {
      return await ref
          .read(libraryRepositoryProvider)
          .saveBookmarkLinks(
            candidates,
            onProgress: (value) => progress.value = value,
          );
    } finally {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await dialogFuture;
      progress.dispose();
    }
  }

  Future<void> _showCollectionSheet(
    ComicSummary comic,
    LibraryComicState? currentState,
  ) async {
    if (_collectionBusy) return;
    setState(() => _collectionBusy = true);
    try {
      final LibraryComicState state =
          currentState ??
          await ref.read(libraryComicStateProvider(comic).future);
      final collections = await ref.read(collectionsProvider.future);
      final selectedIds = state.collections.map((item) => item.id).toSet();
      if (!mounted) return;
      final result = await _showCollectionPicker(
        context,
        collections: collections,
        selectedIds: selectedIds,
        onCreate: () async {
          final name = await _showCollectionNameDialog(context);
          if (name == null || name.trim().isEmpty) return null;
          final created = await ref
              .read(libraryRepositoryProvider)
              .createCollection(name);
          ref.invalidate(collectionsProvider);
          return created;
        },
      );
      if (!mounted || result == null) return;

      await ref
          .read(libraryRepositoryProvider)
          .setComicCollections(comic, result);
      ref.invalidate(libraryComicStateProvider(comic));
      ref.invalidate(collectionsProvider);
      _showSnack('Koleksi diperbarui.', type: AppSnackBarType.success);
      try {
        await Future.wait([
          ref.read(libraryComicStateProvider(comic).future),
          ref.read(collectionsProvider.future),
        ]);
      } catch (_) {
        // Mutasi sudah tersimpan. Biarkan refresh berikutnya mencoba lagi
        // tanpa mengganti snackbar sukses dengan error yang menyesatkan.
      }
    } catch (error, stackTrace) {
      if (mounted) {
        _showErrorSnack(error, stackTrace, 'Update comic collections failed');
      }
    } finally {
      if (mounted) setState(() => _collectionBusy = false);
    }
  }

  Future<void> _showDownloadSheet(
    ComicSummary comic,
    List<ChapterListItem> chapters,
    _ComicDownloadState downloadState,
  ) async {
    if (_downloadBusy) return;
    final available = chapters
        .where(
          (chapter) => !downloadState.knownChapterNumbers.contains(
            chapter.chapterNumber,
          ),
        )
        .toList();
    if (available.isEmpty) {
      _showSnack(
        'Semua chapter yang tersedia sudah masuk offline/antrean.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final selected = await _showDownloadPicker(
      context,
      chapters: available,
      skippedCount: chapters.length - available.length,
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    setState(() => _downloadBusy = true);
    try {
      await ref
          .read(offlineQueueProvider.notifier)
          .startBatch(comic: comic, chapters: selected);
      ref.invalidate(downloadsProvider);
      ref.invalidate(offlineQueueProvider);
      ref.invalidate(libraryComicStateProvider(comic));
      _showSnack(
        '${selected.length} chapter masuk antrean offline.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      _showErrorSnack(error, stackTrace, 'Queue comic download failed');
    } finally {
      if (mounted) setState(() => _downloadBusy = false);
    }
  }

  void _showSnack(
    String message, {
    AppSnackBarType type = AppSnackBarType.help,
  }) {
    if (!mounted) return;
    showAppSnackBar(context, message: message, type: type);
  }

  void _showErrorSnack(Object error, StackTrace stackTrace, String logContext) {
    if (!mounted) return;
    showAppErrorSnackBar(
      context,
      error: error,
      stackTrace: stackTrace,
      logContext: logContext,
      fallbackMessage: 'Aksi komik belum berhasil. Silakan coba lagi.',
    );
  }
}
