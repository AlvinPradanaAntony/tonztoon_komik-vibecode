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
    return TonztoonDropdownButton<String>(
      value: selectedId,
      items: sources
          .map((source) => TonztoonDropdownItem<String>(
                value: source.id,
                label: source.label,
              ))
          .toList(),
      onChanged: (newValue) {
        if (newValue != null) {
          onChanged(newValue);
        }
      },
      hintText: 'Pilih Sumber',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      iconSize: 16,
      maxLabelWidth: 90,
      mainAxisSize: MainAxisSize.min,
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
