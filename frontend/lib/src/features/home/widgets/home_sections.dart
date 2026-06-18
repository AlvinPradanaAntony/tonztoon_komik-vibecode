part of '../home_screen.dart';

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

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
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: AppEmptyState(
        icon: TonztoonIcons.bookOpen,
        title: 'Belum ada komik',
        message: 'Coba muat ulang katalog dari sumber ini.',
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
    this.showNewBadges = false,
  });

  final String title;
  final List<ComicSummary> comics;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showNewBadges;

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
          height: 288,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final comic = comics[index];
              return ComicCard(
                comic: comic,
                showNewBadge: showNewBadges,
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

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReadingProgress progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chapterText =
        'Chapter ${formatChapterNumber(progress.chapterNumber)}';
    final pageText = _progressPageText(progress);
    final progressValue = _progressValue(progress);
    final cardWidth = _progressCardWidth(context, chapterText, progress);

    return SizedBox(
      width: cardWidth,
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
                        Row(
                          children: [
                            Text(
                              chapterText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 6),
                            MetadataSeparator(
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(width: 6),
                            SourceTag(sourceName: progress.sourceName),
                          ],
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

  double _progressCardWidth(
    BuildContext context,
    String chapterText,
    ReadingProgress progress,
  ) {
    final theme = Theme.of(context);
    final chapterWidth = _textWidth(chapterText, theme.textTheme.bodyMedium);
    final sourceWidth =
        _textWidth(
          comicSourceNameLabel(progress.sourceName),
          theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ) +
        31;
    final metadataWidth = chapterWidth + 18 + sourceWidth;

    const coverWidth = 76.0;
    const horizontalPadding = 20.0;
    const coverGap = 12.0;
    const safety = 14.0;
    return (horizontalPadding + coverWidth + coverGap + metadataWidth + safety)
        .clamp(260.0, 360.0);
  }

  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}
