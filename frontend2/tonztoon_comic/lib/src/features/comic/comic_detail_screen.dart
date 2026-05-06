import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../reader/reader_screen.dart';

class ComicDetailScreen extends StatefulWidget {
  const ComicDetailScreen({super.key, required this.comic});

  final ComicSummary comic;

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  static const double _expandedHeaderHeight = 380;
  static const double _titleFadeStart = 150;
  static const double _titleFadeDistance = 90;

  late final ScrollController _scrollController;
  double _collapseProgress = 0;
  ValueNotifier<double>? _collapseProgressNotifier;

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
    final detail = _ComicDetailUi.fromSummary(widget.comic);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final navigationOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: colorScheme.surface,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: colorScheme.outlineVariant,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: navigationOverlayStyle,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            // Simulasi proses pembaruan data
            await Future.delayed(const Duration(seconds: 1));
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                automaticallyImplyLeading: false,
                expandedHeight: _expandedHeaderHeight,
                pinned: true,
                stretch: true,
                elevation: 0,
                centerTitle: true,
                titleSpacing: 0,
                surfaceTintColor: Colors.transparent,
                foregroundColor: Colors.white,
                backgroundColor: Colors.transparent,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: _GlassIconButton(
                      tooltip: 'Kembali',
                      icon: TonztoonIcons.arrowBack,
                      onPressed: () => Navigator.of(context).pop(),
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
                      tooltip: 'Simpan',
                      icon: TonztoonIcons.bookmark,
                      onPressed: () {},
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
                      collapsedStatusBarStyle: navigationOverlayStyle.copyWith(
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
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TitleBlock(detail: detail),
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
                              .map((genre) => ComicGenreBadge(genre: genre))
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                        _ChapterPanel(
                          chapters: detail.chapters,
                          detail: detail,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomReadBar(detail: detail),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ComicCover(
              imageUrl: detail.coverImageUrl,
              borderRadius: 0,
              fit: BoxFit.cover,
              fallbackIconSize: 36,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.scrim.withValues(alpha: 0.18),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0.54),
                colorScheme.surfaceContainerLowest,
              ],
              stops: const [0, 0.56, 1],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 46),
              child: Hero(
                tag: 'detail-cover-${detail.title}',
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.38),
                          blurRadius: 28,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ComicCover(
                      imageUrl: detail.coverImageUrl,
                      width: 182,
                      height: 268,
                      borderRadius: 12,
                      fallbackIconSize: 36,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollapsingToolbarTint extends StatelessWidget {
  const _CollapsingToolbarTint({
    required this.progress,
    required this.color,
    required this.collapsedStatusBarStyle,
  });

  final ValueListenable<double> progress;
  final Color color;
  final SystemUiOverlayStyle collapsedStatusBarStyle;

  @override
  Widget build(BuildContext context) {
    final toolbarHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: toolbarHeight,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, child) {
            final statusBarStyle = value > 0.56
                ? collapsedStatusBarStyle
                : collapsedStatusBarStyle.copyWith(
                    statusBarIconBrightness: Brightness.light,
                    statusBarBrightness: Brightness.dark,
                  );

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: statusBarStyle,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.86 * value),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08 * value),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              detail.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(height: 1.08),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TypeInfoPill(type: detail.type),
              _InfoPill(icon: TonztoonIcons.clock, label: detail.status),
              _InfoPill(
                icon: TonztoonIcons.starFilled,
                label: detail.rating,
                accent: Colors.amber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _CreatorTile(
                icon: TonztoonIcons.user,
                label: 'Author',
                value: detail.author,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CreatorTile(
                icon: TonztoonIcons.paintbrush,
                label: 'Artist',
                value: detail.artist,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CreatorTile(
          icon: TonztoonIcons.tags,
          label: 'Alternative Title',
          value: detail.alternativeTitle,
        ),
      ],
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.list,
            value: detail.totalChapters,
            label: 'Chapter',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.eye,
            value: detail.totalViews,
            label: 'Views',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.calendar,
            value: detail.updatedAt,
            label: 'Update',
          ),
        ),
      ],
    );
  }
}

class _ChapterPanel extends StatelessWidget {
  const _ChapterPanel({required this.chapters, required this.detail});

  final List<_ChapterUi> chapters;
  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          children: [
            Row(
              children: [
                const _SectionHeader(
                  icon: TonztoonIcons.list,
                  title: 'Daftar Chapter',
                ),
                const Spacer(),
                Text(
                  '${chapters.length} terbaru',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 430,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Scrollbar(
                  child: ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.only(bottom: 4),
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      return _ChapterRow(
                        chapter: chapters[index],
                        onTap: () {
                          _openReader(context, detail, chapters[index]);
                        },
                      );
                    },
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 58,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                    itemCount: chapters.length,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.onTap});

  final _ChapterUi chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  TonztoonIcons.bookOpen,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chapter.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(chapter.subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(TonztoonIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomReadBar extends StatelessWidget {
  const _BottomReadBar({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Unduh',
              onPressed: () {},
              icon: const Icon(TonztoonIcons.download),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  _openReader(context, detail, detail.chapters.first);
                },
                icon: const Icon(TonztoonIcons.play),
                label: Text('Baca ${detail.firstChapterLabel}'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Bagikan',
              onPressed: () {},
              icon: const Icon(TonztoonIcons.share),
            ),
          ],
        ),
      ),
    );
  }
}

void _openReader(
  BuildContext context,
  _ComicDetailUi detail,
  _ChapterUi chapter,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ReaderScreen(
        comicTitle: detail.title,
        chapterTitle: chapter.title,
        comic: ComicSummary(
          title: detail.title,
          coverImageUrl: detail.coverImageUrl,
          type: detail.type,
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _CreatorTile extends StatelessWidget {
  const _CreatorTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.secondary, size: 19),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, this.accent});

  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accent ?? colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeInfoPill extends StatelessWidget {
  const _TypeInfoPill({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              comicTypeFlag(type),
              style: const TextStyle(fontSize: 15, height: 1),
            ),
            const SizedBox(width: 6),
            Text(
              type,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _ComicDetailUi {
  const _ComicDetailUi({
    required this.title,
    required this.alternativeTitle,
    required this.coverImageUrl,
    required this.type,
    required this.status,
    required this.rating,
    required this.author,
    required this.artist,
    required this.totalChapters,
    required this.totalViews,
    required this.updatedAt,
    required this.synopsis,
    required this.genres,
    required this.chapters,
  });

  factory _ComicDetailUi.fromSummary(ComicSummary comic) {
    return _samples[comic.title] ??
        _ComicDetailUi(
          title: comic.title,
          alternativeTitle: comic.title,
          coverImageUrl: comic.coverImageUrl,
          type: comic.type ?? 'Komik',
          status: 'Ongoing',
          rating: '4.7',
          author: 'Studio Tonz',
          artist: 'Tonz Team',
          totalChapters: comic.latestChapterNumber == null
              ? '24'
              : formatChapterNumber(comic.latestChapterNumber!),
          totalViews: '128K',
          updatedAt: 'Hari ini',
          synopsis:
              'Petualangan penuh aksi dengan pacing cepat, karakter kuat, dan konflik yang terus berkembang dari chapter ke chapter.',
          genres: const ['Action', 'Adventure', 'Fantasy', 'Drama'],
          chapters: _defaultChapters,
        );
  }

  final String title;
  final String alternativeTitle;
  final String? coverImageUrl;
  final String type;
  final String status;
  final String rating;
  final String author;
  final String artist;
  final String totalChapters;
  final String totalViews;
  final String updatedAt;
  final String synopsis;
  final List<String> genres;
  final List<_ChapterUi> chapters;

  String get firstChapterLabel => chapters.first.title;
}

class _ChapterUi {
  const _ChapterUi({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

List<_ChapterUi> _buildDummyChapters({
  required int latest,
  required String firstSubtitle,
}) {
  const archiveSubtitles = [
    '22 halaman - 2 hari lalu',
    '25 halaman - Minggu lalu',
    '21 halaman - 2 minggu lalu',
    '24 halaman - 3 minggu lalu',
    '20 halaman - Bulan lalu',
    '23 halaman - Arsip',
    '19 halaman - Arsip',
    '26 halaman - Arsip',
    '18 halaman - Arsip',
  ];

  return List<_ChapterUi>.generate(10, (index) {
    final chapterNumber = latest - index;
    return _ChapterUi(
      title: 'Chapter $chapterNumber',
      subtitle: index == 0 ? firstSubtitle : archiveSubtitles[index - 1],
    );
  });
}

final _defaultChapters = _buildDummyChapters(
  latest: 24,
  firstSubtitle: '24 halaman - Hari ini',
);

final Map<String, _ComicDetailUi> _samples = {
  'Solo Leveling': _ComicDetailUi(
    title: 'Solo Leveling',
    alternativeTitle: 'Na Honjaman Level Up',
    coverImageUrl: dummyComics[0].coverImageUrl,
    type: 'Manhwa',
    status: 'Completed',
    rating: '4.9',
    author: 'Chugong',
    artist: 'DUBU',
    totalChapters: '179',
    totalViews: '2.4M',
    updatedAt: 'Selesai',
    synopsis:
        'Sung Jin-Woo, hunter rank E yang dikenal paling lemah, mendapat kesempatan kedua setelah melewati dungeon misterius. Dari sana ia tumbuh menjadi kekuatan yang mengubah aturan dunia hunter.',
    genres: const ['Action', 'Fantasy', 'Adventure', 'System', 'Drama'],
    chapters: _buildDummyChapters(
      latest: 179,
      firstSubtitle: '38 halaman - Tamat',
    ),
  ),
  'One Piece': _ComicDetailUi(
    title: 'One Piece',
    alternativeTitle: 'Wan Pisu',
    coverImageUrl: dummyComics[1].coverImageUrl,
    type: 'Manga',
    status: 'Ongoing',
    rating: '4.8',
    author: 'Eiichiro Oda',
    artist: 'Eiichiro Oda',
    totalChapters: '1111',
    totalViews: '9.8M',
    updatedAt: 'Minggu ini',
    synopsis:
        'Monkey D. Luffy dan kru Topi Jerami berlayar mencari harta legendaris One Piece. Setiap pulau membawa konflik, teman baru, dan potongan rahasia dunia yang makin besar.',
    genres: const ['Adventure', 'Action', 'Comedy', 'Fantasy', 'Shounen'],
    chapters: _buildDummyChapters(
      latest: 1111,
      firstSubtitle: '17 halaman - Minggu ini',
    ),
  ),
  'Omniscient Reader\'s Viewpoint': _ComicDetailUi(
    title: 'Omniscient Reader\'s Viewpoint',
    alternativeTitle: 'Jeonjijeok Dokja Sijeom',
    coverImageUrl: dummyComics[2].coverImageUrl,
    type: 'Manhwa',
    status: 'Ongoing',
    rating: '4.8',
    author: 'Sing Shong',
    artist: 'Sleepy-C',
    totalChapters: '200',
    totalViews: '1.7M',
    updatedAt: 'Kemarin',
    synopsis:
        'Kim Dokja adalah satu-satunya pembaca novel web yang tiba-tiba menjadi kenyataan. Pengetahuannya tentang cerita menjadi senjata utama untuk bertahan hidup.',
    genres: const ['Action', 'Apocalypse', 'Fantasy', 'Psychological'],
    chapters: _buildDummyChapters(
      latest: 200,
      firstSubtitle: '26 halaman - Kemarin',
    ),
  ),
  'Kagurabachi': _ComicDetailUi(
    title: 'Kagurabachi',
    alternativeTitle: 'Kagurabachi',
    coverImageUrl: dummyComics[3].coverImageUrl,
    type: 'Manga',
    status: 'Ongoing',
    rating: '4.6',
    author: 'Takeru Hokazono',
    artist: 'Takeru Hokazono',
    totalChapters: '24',
    totalViews: '642K',
    updatedAt: '3 hari lalu',
    synopsis:
        'Chihiro Rokuhira mengejar kelompok kriminal yang mencuri pedang sihir warisan ayahnya. Balas dendam, teknik pedang, dan dunia bawah menjadi panggung utamanya.',
    genres: const ['Action', 'Supernatural', 'Swordplay', 'Shounen'],
    chapters: _buildDummyChapters(
      latest: 24,
      firstSubtitle: '19 halaman - 3 hari lalu',
    ),
  ),
};
