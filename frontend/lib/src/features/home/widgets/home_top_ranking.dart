part of '../home_screen.dart';

class _TopRankingRail extends ConsumerStatefulWidget {
  const _TopRankingRail({
    required this.comics,
    required this.sourceName,
    required this.onComicTap,
  });

  final List<ComicSummary> comics;
  final String sourceName;
  final ValueChanged<ComicSummary> onComicTap;

  @override
  ConsumerState<_TopRankingRail> createState() => _TopRankingRailState();
}

class _TopRankingRailState extends ConsumerState<_TopRankingRail> {
  String? _selectedType;
  static const double _cardWidth = 138;
  static const double _railHeight = 224;

  @override
  Widget build(BuildContext context) {
    if (widget.comics.isEmpty) return const SizedBox.shrink();

    final rankingAsync = _selectedType == null
        ? null
        : ref.watch(
            topRankingProvider(
              TopRankingRequest(
                sourceName: widget.sourceName,
                type: _selectedType,
              ),
            ),
          );
    final visibleComics = _selectedType == null
        ? widget.comics
        : rankingAsync?.asData?.value;
    final displayComics = visibleComics ?? const <ComicSummary>[];
    final isLoading = _selectedType != null && rankingAsync is! AsyncData;
    final error = rankingAsync?.hasError == true ? rankingAsync!.error : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Top Ranking',
          trailing: _TypeFilterToggle(
            selectedType: _selectedType,
            onTypeChanged: (type) {
              setState(() {
                _selectedType = type;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _railHeight,
          child: isLoading
              ? const _HomeTopRankingRailShimmer()
              : error != null
              ? Center(
                  child: Text(
                    'Top ranking belum dapat dimuat.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                )
              : displayComics.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada komik untuk tipe ini.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  clipBehavior: Clip.none,
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final comic = displayComics[index];
                    return _TopRankingCard(
                      comic: comic,
                      rank: index + 1,
                      width: _cardWidth,
                      onTap: () => widget.onComicTap(comic),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemCount: displayComics.length,
                ),
        ),
      ],
    );
  }
}

class _TypeFilterToggle extends StatelessWidget {
  const _TypeFilterToggle({
    required this.selectedType,
    required this.onTypeChanged,
  });

  final String? selectedType;
  final ValueChanged<String?> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final types = [
      (label: 'Semua', value: null),
      (label: 'Manhwa', value: 'manhwa'),
      (label: 'Manga', value: 'manga'),
      (label: 'Manhua', value: 'manhua'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: types.map((type) {
          final isSelected = selectedType == type.value;
          return GestureDetector(
            onTap: () => onTypeChanged(type.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                          ? colorScheme.secondary
                          : colorScheme.primary)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: (isDark ? colorScheme.secondary : colorScheme.primary)
                              .withValues(alpha: isDark ? 0.24 : 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4.5,
              ),
              child: Text(
                type.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 11,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.white)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.black54),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TopRankingCard extends StatefulWidget {
  const _TopRankingCard({
    required this.comic,
    required this.rank,
    required this.width,
    required this.onTap,
  });

  final ComicSummary comic;
  final int rank;
  final double width;
  final VoidCallback onTap;

  @override
  State<_TopRankingCard> createState() => _TopRankingCardState();
}

class _TopRankingCardState extends State<_TopRankingCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewLabel = widget.comic.totalView == null
        ? null
        : '${formatCompactCount(widget.comic.totalView!)} views';
    final ratingLabel = _formatTopRankingRating(widget.comic.rating);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.025 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: widget.width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hovered ? 0.35 : 0.28,
                        ),
                        blurRadius: _hovered ? 25 : 15,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ComicCover(
                            imageUrl: widget.comic.coverImageUrl,
                            borderRadius: 12,
                          ),
                          Positioned.fill(
                            child: ShaderMask(
                              shaderCallback: (rect) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.white],
                                  stops: [0.35, 0.92],
                                ).createShader(rect);
                              },
                              blendMode: BlendMode.dstIn,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 5,
                                  sigmaY: 5,
                                ),
                                child: ComicCover(
                                  imageUrl: widget.comic.coverImageUrl,
                                  borderRadius: 12,
                                ),
                              ),
                            ),
                          ),
                          const Positioned.fill(child: _TopRankingEdgeShade()),
                          Positioned(
                            left: 0,
                            top: 0,
                            child: _TopRankingBadge(rank: widget.rank),
                          ),
                          Positioned(
                            top: 9,
                            right: 9,
                            child: ComicTypeFlagBadge(
                              type: widget.comic.type ?? '',
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _TopRankingBottomOverlay(
                              title: widget.comic.title,
                              viewLabel: viewLabel,
                              ratingLabel: ratingLabel,
                              textStyle: theme.textTheme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRankingEdgeShade extends StatelessWidget {
  const _TopRankingEdgeShade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.08),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.42),
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
    );
  }
}

class _TopRankingBottomOverlay extends StatelessWidget {
  const _TopRankingBottomOverlay({
    required this.title,
    required this.viewLabel,
    required this.ratingLabel,
    required this.textStyle,
  });

  final String title;
  final String? viewLabel;
  final String? ratingLabel;
  final TextTheme textStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: List.generate(9, (index) {
            final p = index / 8;
            return Colors.black.withValues(alpha: 0.94 * p * p);
          }),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 34, 12, 12),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.08,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyle.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (viewLabel != null) ...[
                    Flexible(
                      child: Text(
                        viewLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (viewLabel != null && ratingLabel != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '•',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.46),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (ratingLabel != null) ...[
                    Icon(
                      TonztoonIcons.starFilled,
                      size: 13,
                      color: Colors.amber.shade300,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      ratingLabel!,
                      style: textStyle.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopRankingBadge extends StatelessWidget {
  const _TopRankingBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = _topRankingBadgeColors(rank);
    final isPodium = rank <= 3;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomRight: Radius.circular(13),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: isPodium ? 40 : 36,
        height: isPodium ? 36 : 32,
        child: Center(
          child: Text(
            '#$rank',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w900,
              fontSize: isPodium ? 18 : 15,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

({Color background, Color foreground}) _topRankingBadgeColors(int rank) {
  return switch (rank) {
    1 => (background: const Color(0xFFFFC400), foreground: Colors.black),
    2 => (background: const Color(0xFFE5EDF7), foreground: Colors.black),
    3 => (background: const Color(0xFFD96A00), foreground: Colors.white),
    _ => (background: const Color(0xFF101827), foreground: Colors.white),
  };
}
