import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_assets.dart';
import '../../core/app_icons.dart';
import 'section/comic_section_screen.dart';
import '../../models/auth.dart';
import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../models/source_info.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import '../../widgets/guest_migration_dialog.dart';

/// [HomeScreen] adalah halaman beranda aplikasi komik.
/// Menampilkan rekomendasi dan update terbaru.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _migrationPromptShown = false;

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(homeDataProvider);
    final continueReadingAsync = ref.watch(continueReadingProvider);
    final auth = ref.watch(authControllerProvider);
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
    _maybePromptMigration(auth);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          AppAssets.logoAppLarge,
          height: 32, // Ukuran proporsional untuk AppBar
          fit: BoxFit.contain,
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: auth.isAuthenticated ? 'Notifikasi' : 'Login',
              onPressed: auth.isAuthenticated
                  ? () => _openNotifications(context)
                  : () => context.push('/auth'),
              icon: auth.isAuthenticated
                  ? _NotificationBellBadge(count: unreadNotifications)
                  : const Icon(TonztoonIcons.accountCircle),
            ),
          ),
        ],
      ),
      // Gunakan ListView dengan padding bawah besar (128) agar
      // tidak terpotong efek fade-mask dan floating navbar.
      body: RefreshIndicator(
        onRefresh: () => _retryHomeData(showErrorSnackBar: true),
        child: AppAsyncView<HomeData>(
          value: homeAsync,
          skipLoadingOnRefresh: true,
          skipError: true,
          loadingBuilder: (context) => const _HomeLoadingPlaceholder(),
          onRetry: () => unawaited(_retryHomeData()),
          builder: (home) {
            final latestComics = home.latest;
            final popularComics = home.popular;
            final recommendationComics =
                (latestComics.isNotEmpty ? latestComics : popularComics)
                    .take(4)
                    .toList();
            final continueProgress =
                continueReadingAsync.asData?.value ?? home.continueReading;
            final hasHomeContent =
                latestComics.isNotEmpty ||
                popularComics.isNotEmpty ||
                recommendationComics.isNotEmpty ||
                continueProgress.isNotEmpty;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
              children: [
                _DiscoverHeader(
                  data: home,
                  onSourceChanged: (value) {
                    ref.read(selectedSourceProvider.notifier).select(value);
                  },
                ),
                const SizedBox(height: 20),
                if (recommendationComics.isNotEmpty) ...[
                  const _SectionTitle(title: 'Rekomendasi'),
                  const SizedBox(height: 10),
                  _RecommendationCarousel(
                    comics: recommendationComics,
                    onComicTap: (comic) => _openComicDetail(context, comic),
                  ),
                  const SizedBox(height: 24),
                ],
                if (continueProgress.isNotEmpty) ...[
                  _SectionTitle(
                    title: 'Lanjutkan Membaca',
                    actionLabel: '${continueProgress.length}',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 154,
                    child: ListView.separated(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 24),
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) =>
                          _ProgressCard(progress: continueProgress[index]),
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemCount: continueProgress.length,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _ComicRail(
                  title: 'Rilis Terbaru',
                  comics: latestComics.take(6).toList(),
                  actionLabel: 'Lihat semua',
                  onAction: () => _openComicSection(
                    context,
                    title: 'Rilis Terbaru',
                    subtitle: 'Chapter baru dari berbagai sumber favorit.',
                    comics: latestComics,
                    initialSort: ComicSortOption.updateNewest,
                  ),
                ),
                if (hasHomeContent) const SizedBox(height: 24),
                _ComicRail(
                  title: 'Populer',
                  comics: popularComics.take(6).toList(),
                  actionLabel: 'Lihat semua',
                  onAction: () => _openComicSection(
                    context,
                    title: 'Populer',
                    subtitle: 'Komik yang ramai dibaca minggu ini.',
                    comics: popularComics,
                    initialSort: ComicSortOption.popular,
                  ),
                ),
                if (!hasHomeContent) const _HomeEmptyState(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _retryHomeData({bool showErrorSnackBar = false}) async {
    try {
      ref.invalidate(homeDataProvider);
      await ref.read(homeDataProvider.future);
    } catch (error) {
      if (!mounted || !showErrorSnackBar) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Refresh gagal: $error')));
    }
  }

  void _maybePromptMigration(AuthState auth) {
    if (_migrationPromptShown || !auth.isAuthenticated) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo.migrationSkipped || !repo.hasMigratableLocalData()) return;
    _migrationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMigrationDialog();
    });
  }

  Future<void> _showMigrationDialog() async {
    final repo = ref.read(libraryRepositoryProvider);
    final summary = repo.getGuestMigrationSummary();
    final action = await showGuestMigrationDialog(
      context,
      summary: summary,
      title: 'Sinkronkan data guest?',
      message:
          'Data dari mode guest berikut bisa dipindahkan ke akun cloud. File offline tetap tersimpan di perangkat ini.',
      barrierDismissible: false,
      secondaryLabel: 'Lewati',
      secondaryAction: GuestMigrationDialogAction.skip,
    );
    if (!mounted || action == null) return;

    if (action == GuestMigrationDialogAction.skip) {
      await repo.skipMigration();
      return;
    }

    var loadingShown = false;
    try {
      _showMigrationLoadingDialog();
      loadingShown = true;
      await repo.importLocalSnapshotToCloud();
      ref.invalidate(homeDataProvider);
      ref.invalidate(bookmarksProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(favoriteScenesProvider);
      ref.invalidate(downloadsProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(readingTimeProvider);
      unawaited(ref.read(readingTimeProvider.notifier).refreshFromCloud());
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingShown = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data guest berhasil disinkronkan.')),
      );
    } catch (error) {
      _migrationPromptShown = false;
      if (!mounted) return;
      if (loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Migrasi gagal: $error')));
    }
  }

  void _showMigrationLoadingDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const PopScope(canPop: false, child: GuestMigrationLoadingDialog()),
      ),
    );
  }
}

class _HomeLoadingPlaceholder extends StatelessWidget {
  const _HomeLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
      children: const [
        AppShimmer(
          child: AppShimmerBlock(
            width: double.infinity,
            height: 150,
            borderRadius: 18,
          ),
        ),
        SizedBox(height: 20),
        _HomeSkeletonSectionTitle(width: 136),
        SizedBox(height: 10),
        _HomeRecommendationShimmer(),
        SizedBox(height: 24),
        _HomeSkeletonSectionTitle(width: 164),
        SizedBox(height: 10),
        _HomeRailShimmer(),
        SizedBox(height: 24),
        _HomeSkeletonSectionTitle(width: 108),
        SizedBox(height: 10),
        _HomeRailShimmer(),
      ],
    );
  }
}

class _HomeSkeletonSectionTitle extends StatelessWidget {
  const _HomeSkeletonSectionTitle({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: [
          const AppShimmerBlock(width: 4, height: 22, borderRadius: 4),
          const SizedBox(width: 10),
          AppShimmerBlock(width: width, height: 22),
          const Spacer(),
          const AppShimmerBlock(width: 74, height: 18),
        ],
      ),
    );
  }
}

class _HomeRecommendationShimmer extends StatelessWidget {
  const _HomeRecommendationShimmer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 270,
      child: AppShimmer(
        child: AppShimmerBlock(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 18,
        ),
      ),
    );
  }
}

class _HomeRailShimmer extends StatelessWidget {
  const _HomeRailShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => const SizedBox(
          width: 138,
          child: AppShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppShimmerBlock(
                    width: double.infinity,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(height: 9),
                AppShimmerBlock(width: double.infinity, height: 14),
                SizedBox(height: 7),
                AppShimmerBlock(width: 112, height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: colorScheme.secondary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          onAction != null
              ? TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Text(
                  actionLabel!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      ],
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(
                TonztoonIcons.bookOpen,
                size: 38,
                color: colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Belum ada komik',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Coba muat ulang katalog dari sumber ini.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({required this.data, required this.onSourceChanged});

  final HomeData data;
  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Warna aksen untuk gradient banner
    const primaryOrange = Color(0xFFFF9D00);
    const accentBlue = Color(0xFF3A86FF);

    final gradientColors = isDark
        ? [
            const Color(0xFF1A1F2E),
            const Color(0xFF0F1620),
            const Color(0xFF1A1220),
          ]
        : [
            const Color(0xFFFFF8EC),
            const Color(0xFFF0F7FF),
            const Color(0xFFFFF0F7),
          ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: primaryOrange.withValues(alpha: isDark ? 0.18 : 0.12),
                blurRadius: 24,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // --- Dekorasi lingkaran latar belakang ---
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primaryOrange.withValues(alpha: isDark ? 0.18 : 0.10),
                        primaryOrange.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentBlue.withValues(alpha: isDark ? 0.14 : 0.08),
                        accentBlue.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // --- Konten utama banner ---
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [primaryOrange, accentBlue],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Jelajahi',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          fontSize: 26,
                                          letterSpacing: -0.5,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _SourceSelector(
                          selectedId: data.selectedSource.id,
                          selectedLabel: data.selectedSource.label,
                          sources: data.sources,
                          onChanged: onSourceChanged,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({
    required this.selectedId,
    required this.selectedLabel,
    required this.sources,
    required this.onChanged,
  });

  final String selectedId;
  final String selectedLabel;
  final List<SourceInfo> sources;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      initialValue: selectedId,
      tooltip: 'Pilih Sumber',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (BuildContext context) => sources.map((source) {
        return PopupMenuItem<String>(
          value: source.id,
          child: Row(
            children: [
              Icon(
                selectedId == source.id ? TonztoonIcons.check : null,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                source.label,
                style: TextStyle(
                  fontWeight: selectedId == source.id
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.82),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(
                alpha: isDark ? 0.12 : 0.08,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TonztoonIcons.travelExplore,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  selectedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                TonztoonIcons.keyboardArrowDown,
                size: 15,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComicRail extends StatelessWidget {
  const _ComicRail({
    required this.title,
    required this.comics,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final List<ComicSummary> comics;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (comics.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: title,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 284,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final comic = comics[index];
              return ComicCard(
                comic: comic,
                onTap: () => _openComicDetail(context, comic),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemCount: comics.length,
          ),
        ),
      ],
    );
  }
}

class _RecommendationCarousel extends StatefulWidget {
  const _RecommendationCarousel({
    required this.comics,
    required this.onComicTap,
  });

  final List<ComicSummary> comics;
  final ValueChanged<ComicSummary> onComicTap;

  @override
  State<_RecommendationCarousel> createState() =>
      _RecommendationCarouselState();
}

class _RecommendationCarouselState extends State<_RecommendationCarousel> {
  static const _autoSlideDuration = Duration(seconds: 4);
  static const _slideAnimationDuration = Duration(milliseconds: 520);

  late PageController _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 0;
  int _virtualPage = 0;

  @override
  void initState() {
    super.initState();
    _resetController();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant _RecommendationCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comics.length == widget.comics.length) return;
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    _resetController();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comics.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 214,
          child: PageView.builder(
            controller: _pageController,
            clipBehavior: Clip.none,
            onPageChanged: _handlePageChanged,
            itemCount: widget.comics.length > 1 ? null : widget.comics.length,
            itemBuilder: (context, index) {
              final comicIndex = index % widget.comics.length;
              final comic = widget.comics[comicIndex];
              return Padding(
                padding: EdgeInsets.only(
                  right: widget.comics.length == 1 ? 0 : 10,
                ),
                child: _RecommendationBanner(
                  comic: comic,
                  index: comicIndex,
                  onTap: () => widget.onComicTap(comic),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.comics.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _currentPage == i ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _resetController() {
    final hasMultipleItems = widget.comics.length > 1;
    _virtualPage = hasMultipleItems ? widget.comics.length * 1000 : 0;
    _currentPage = 0;
    _pageController = PageController(
      viewportFraction: 0.94,
      initialPage: _virtualPage,
    );
  }

  void _handlePageChanged(int index) {
    if (widget.comics.isEmpty) return;
    setState(() {
      _virtualPage = index;
      _currentPage = index % widget.comics.length;
    });
  }

  void _startAutoSlide() {
    if (widget.comics.length < 2) return;
    _autoSlideTimer = Timer.periodic(_autoSlideDuration, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = _virtualPage + 1;
      _pageController.animateToPage(
        nextPage,
        duration: _slideAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _RecommendationBanner extends StatelessWidget {
  const _RecommendationBanner({
    required this.comic,
    required this.index,
    required this.onTap,
  });

  final ComicSummary comic;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final source = comicSourceLabel(comic);
    final accentColors = const [
      Color(0xFFFF9D00),
      Color(0xFF3A86FF),
      Color(0xFFFF5A5A),
      Color(0xFF20B486),
    ];
    final accent = accentColors[index % accentColors.length];
    final chapter = comic.latestChapterNumber;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.13),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ComicCover(imageUrl: comic.coverImageUrl, borderRadius: 18),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: const SizedBox.shrink(),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: List.generate(9, (index) {
                        final p = index / 8;
                        return Colors.black.withValues(alpha: 0.84 * (1 - p * p));
                      }),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ComicSourceBadge(label: source),
                                if (comic.type != null)
                                  ComicTypeFlagBadge(type: comic.type!),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              comic.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (chapter != null)
                                  _BannerPill(
                                    label: 'Ch ${formatChapterNumber(chapter)}',
                                    color: accent,
                                  ),
                                _BannerPill(
                                  label: 'Rekomendasi',
                                  color: Colors.white,
                                  foregroundColor: Colors.white,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: onTap,
                              icon: const Icon(TonztoonIcons.play, size: 17),
                              label: const Text('Baca sekarang'),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 42),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 86,
                        height: 132,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.34),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ComicCover(
                            imageUrl: comic.coverImageUrl,
                            borderRadius: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({
    required this.label,
    required this.color,
    this.foregroundColor,
  });

  final String label;
  final Color color;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foregroundColor ?? color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReadingProgress progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chapterText =
        'Chapter ${formatChapterNumber(progress.chapterNumber)}';
    final pageText =
        progress.lastReadPageItemIndex == null ||
            progress.totalPageItems == null
        ? null
        : 'Halaman ${progress.lastReadPageItemIndex! + 1}/${progress.totalPageItems}';
    final progressValue =
        progress.lastReadPageItemIndex == null ||
            progress.totalPageItems == null ||
            progress.totalPageItems == 0
        ? null
        : (progress.lastReadPageItemIndex! + 1) / progress.totalPageItems!;

    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.3
                    : 0.08,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openReaderProgress(context, progress),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ComicCover(
                    imageUrl: progress.coverImageUrl,
                    width: 76,
                    height: 108,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          progress.comicTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          chapterText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (pageText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            pageText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          borderRadius: BorderRadius.circular(99),
                          value: progressValue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openComicDetail(BuildContext context, ComicSummary comic) {
  context.push(
    '/comic/${Uri.encodeComponent(comicRouteSource(comic))}/${Uri.encodeComponent(comicRouteSlug(comic))}',
    extra: comic,
  );
}

void _openReaderProgress(BuildContext context, ReadingProgress progress) {
  final comic = ComicSummary(
    title: progress.comicTitle,
    slug: progress.comicSlug,
    sourceName: progress.sourceName,
    coverImageUrl: progress.coverImageUrl,
    latestChapterNumber: progress.chapterNumber,
  );
  context.push(
    '/reader/${Uri.encodeComponent(progress.sourceName)}/${Uri.encodeComponent(progress.comicSlug)}/${formatChapterNumber(progress.chapterNumber)}',
    extra: comic,
  );
}

void _openNotifications(BuildContext context) {
  context.push('/notifications');
}

void _openComicSection(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<ComicSummary> comics,
  required String initialSort,
}) {
  final section =
      ComicSortOption.normalize(initialSort) == ComicSortOption.popular
      ? 'popular'
      : 'latest';
  context.push(
    '/comic/home/$section/section/$section',
    extra: ComicSectionPayload(
      title: title,
      subtitle: subtitle,
      comics: comics,
      initialSort: initialSort,
    ),
  );
}

class _NotificationBellBadge extends StatelessWidget {
  const _NotificationBellBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 9 ? '9+' : '$count'),
      alignment: Alignment.topRight,
      offset: const Offset(4, -4),
      child: const Icon(TonztoonIcons.bell),
    );
  }
}
