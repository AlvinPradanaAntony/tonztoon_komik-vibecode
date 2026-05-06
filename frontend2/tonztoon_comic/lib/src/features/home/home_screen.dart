import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/app_assets.dart';
import '../../core/app_icons.dart';
import '../comic/comic_detail_screen.dart';
import 'section/comic_section_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../models/comic.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';

/// [HomeScreen] adalah halaman beranda aplikasi komik.
/// Menampilkan rekomendasi dan update terbaru.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              tooltip: 'Notifikasi',
              onPressed: () => _openNotifications(context),
              icon: const _NotificationBellBadge(count: 3),
            ),
          ),
        ],
      ),
      // Gunakan ListView dengan padding bawah besar (128) agar
      // tidak terpotong efek fade-mask dan floating navbar.
      body: RefreshIndicator(
        onRefresh: () async {
          // Simulasi proses pembaruan data
          await Future.delayed(const Duration(seconds: 1));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 128),
          children: [
            const _DiscoverHeader(),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Rekomendasi'),
            const SizedBox(height: 10),
            _RecommendationCarousel(
              comics: _recommendedComics,
              onComicTap: (comic) => _openComicDetail(context, comic),
            ),
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Lanjutkan Membaca',
              actionLabel: '4', // Label dummy
            ),
            const SizedBox(height: 10),
            SizedBox(
              height:
                  154, // Diperbesar dari 130 untuk memberi ruang pada shadow
              child: ListView.separated(
                clipBehavior: Clip.none, // Mencegah shadow terpotong
                padding: const EdgeInsets.only(
                  bottom: 24,
                ), // Memberi jeda bayangan ke bawah
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) => _ProgressCard(
                  comic: dummyComics[index],
                  onTap: () => _openComicDetail(context, dummyComics[index]),
                ),
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemCount: dummyComics.length,
              ),
            ),
            const SizedBox(
              height: 12,
            ), // Dikurangi dari 24 untuk mengompensasi padding bawah
            _ComicRail(
              title: 'Rilis Terbaru',
              comics: dummyComics,
              actionLabel: 'Lihat semua',
              onAction: () => _openComicSection(
                context,
                title: 'Rilis Terbaru',
                subtitle: 'Chapter baru dari berbagai sumber favorit.',
                comics: _latestComics,
                initialSort: 'Update terbaru',
              ),
            ),
            const SizedBox(height: 24),
            _ComicRail(
              title: 'Populer',
              comics: dummyComics,
              actionLabel: 'Lihat semua',
              onAction: () => _openComicSection(
                context,
                title: 'Populer',
                subtitle: 'Komik yang ramai dibaca minggu ini.',
                comics: _popularComics,
                initialSort: 'Paling populer',
              ),
            ),
          ],
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

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Baris 1: Judul + Source Selector ---
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
                              const SizedBox(height: 3),
                              Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Text(
                                  'Temukan komik favoritmu',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.55,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _SourceSelector(),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // --- Baris 2: Stat grid (3 kolom) ---
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: TonztoonIcons.autoAwesome,
                            value: '24',
                            label: 'Terbaru',
                            accentColor: primaryOrange,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: TonztoonIcons.localFireDepartment,
                            value: '12',
                            label: 'Populer',
                            accentColor: const Color(0xFFFF5A5A),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            icon: TonztoonIcons.bookmarkAdded,
                            value: '3',
                            label: 'Aktif',
                            accentColor: accentBlue,
                            isDark: isDark,
                          ),
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

/// Kartu statistik dalam banner Jelajahi.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accentColor,
    required this.isDark,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: accentColor),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                color: accentColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSelector extends StatefulWidget {
  const _SourceSelector();

  @override
  State<_SourceSelector> createState() => _SourceSelectorState();
}

class _SourceSelectorState extends State<_SourceSelector> {
  static const _sources = [
    'Semua Sumber',
    'Komiku',
    'Komiku Asia',
    'Komikcast',
    'Shinigami',
  ];

  String _selectedSource = 'Semua Sumber';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      initialValue: _selectedSource,
      tooltip: 'Pilih Sumber',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.under,
      onSelected: (String result) {
        setState(() {
          _selectedSource = result;
        });
      },
      itemBuilder: (BuildContext context) => _sources.map((String source) {
        return PopupMenuItem<String>(
          value: source,
          child: Row(
            children: [
              Icon(
                _selectedSource == source ? TonztoonIcons.check : null,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                source,
                style: TextStyle(
                  fontWeight: _selectedSource == source
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
                  _selectedSource,
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.black.withValues(alpha: 0.58),
                        Colors.black.withValues(alpha: 0.22),
                      ],
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
  const _ProgressCard({required this.comic, required this.onTap});

  final ComicSummary comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Karena kita pakai ComicSummary (dummy data), kita buat hardcoded nilai progress untuk UI.
    final chapterText = 'Chapter ${comic.latestChapterNumber ?? 1}';
    const pageText = 'Halaman 12/24';
    const double progressValue = 0.5;

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
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ComicCover(
                    imageUrl: comic.coverImageUrl,
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
                          comic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          chapterText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pageText,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ComicDetailScreen(comic: comic),
    ),
  );
}

void _openNotifications(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const NotificationsScreen()),
  );
}

void _openComicSection(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<ComicSummary> comics,
  required String initialSort,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ComicSectionScreen(
        title: title,
        subtitle: subtitle,
        comics: comics,
        initialSort: initialSort,
      ),
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

final List<ComicSummary> _latestComics = [
  ...dummyComics,
  const ComicSummary(
    title: 'Tower of God',
    type: 'Manhwa',
    latestChapterNumber: 621,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/2/170796l.jpg',
  ),
  const ComicSummary(
    title: 'Blue Lock',
    type: 'Manga',
    latestChapterNumber: 272,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/5/213341l.jpg',
  ),
  const ComicSummary(
    title: 'Chainsaw Man',
    type: 'Manga',
    latestChapterNumber: 173,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/216464l.jpg',
  ),
  const ComicSummary(
    title: 'The Beginning After the End',
    type: 'Manhwa',
    latestChapterNumber: 187,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/222681l.jpg',
  ),
];

final List<ComicSummary> _recommendedComics = [
  dummyComics[2],
  const ComicSummary(
    title: 'Jujutsu Kaisen',
    type: 'Manga',
    latestChapterNumber: 271,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/210341l.jpg',
  ),
  const ComicSummary(
    title: 'The Beginning After the End',
    type: 'Manhwa',
    latestChapterNumber: 187,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/222681l.jpg',
  ),
  dummyComics[0],
];

final List<ComicSummary> _popularComics = [
  dummyComics[1],
  dummyComics[0],
  dummyComics[2],
  const ComicSummary(
    title: 'Jujutsu Kaisen',
    type: 'Manga',
    latestChapterNumber: 271,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/3/210341l.jpg',
  ),
  const ComicSummary(
    title: 'Dandadan',
    type: 'Manga',
    latestChapterNumber: 163,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/2/248746l.jpg',
  ),
  const ComicSummary(
    title: 'Eleceed',
    type: 'Manhwa',
    latestChapterNumber: 310,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/2/242512l.jpg',
  ),
  dummyComics[3],
  const ComicSummary(
    title: 'Wind Breaker',
    type: 'Manga',
    latestChapterNumber: 154,
    coverImageUrl: 'https://cdn.myanimelist.net/images/manga/5/253176l.jpg',
  ),
];
