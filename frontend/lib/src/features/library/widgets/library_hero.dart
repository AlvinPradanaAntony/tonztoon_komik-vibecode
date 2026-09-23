part of '../library_screen.dart';

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({
    required this.bookmarks,
    required this.bookmarkStatusCounts,
    required this.downloadsCount,
    required this.totalBookmarks,
    required this.onFilterByStatus,
    required this.onOpenDownloads,
    this.activeStatus,
  });

  final List<LibraryComicRef> bookmarks;
  final Map<String, int> bookmarkStatusCounts;
  final int downloadsCount;
  final int totalBookmarks;
  final ValueChanged<String> onFilterByStatus;
  final VoidCallback onOpenDownloads;
  final String? activeStatus;

  int get _ongoingCount => _statusCount('ongoing');
  int get _completedCount => _statusCount('completed');
  int get _hiatusCount => _statusCount('hiatus');

  bool _isStatusActive(String targetStatus) {
    if (activeStatus == null) return false;
    final values = selectedFilterValues(activeStatus!);
    if (values.isEmpty) return false;
    final target = targetStatus.trim().toLowerCase();
    return values.any((val) {
      final v = val.trim().toLowerCase();
      if (target == 'selesai' || target == 'completed') {
        return v == 'selesai' || v == 'completed';
      }
      return v == target;
    });
  }

  int _statusCount(String status) {
    if (bookmarkStatusCounts.isNotEmpty) {
      final direct = bookmarkStatusCounts[status];
      if (direct != null) return direct;
      if (status == 'completed') {
        return bookmarkStatusCounts['selesai'] ?? 0;
      }
      return 0;
    }
    return bookmarks
        .where((item) {
          final s = item.status?.trim().toLowerCase();
          if (s == null) return false;
          if (status == 'completed') {
            return s == 'completed' || s == 'selesai';
          }
          return s == status;
        })
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryOrange = Color(0xFFFF9D00);
    const accentBlue = Color(0xFF3A86FF);
    final gradientColors = isDark
        ? const [Color(0xFF1A1F2E), Color(0xFF0F1620), Color(0xFF1A1220)]
        : const [Color(0xFFFFF8EC), Color(0xFFF0F7FF), Color(0xFFFFF0F7)];

    final isOngoingActive = _isStatusActive('Ongoing');
    final isCompletedActive = _isStatusActive('Selesai');
    final isHiatusActive = _isStatusActive('Hiatus');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: gradientColors,
        ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        TonztoonIcons.library,
                        color: primaryOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rak Bacaan Saya',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$totalBookmarks komik tersimpan',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.24),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '$totalBookmarks',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: primaryOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: primaryOrange.withValues(alpha: 0.12),
                  height: 1,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.clock,
                        value: '$_ongoingCount',
                        label: 'Ongoing',
                        color: accentBlue,
                        isDark: isDark,
                        isActive: isOngoingActive,
                        semanticLabel: 'Filter bookmark Ongoing',
                        onTap: () => onFilterByStatus('Ongoing'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.badgeCheck,
                        value: '$_completedCount',
                        label: 'Selesai',
                        color: const Color(0xFF16A34A),
                        isDark: isDark,
                        isActive: isCompletedActive,
                        semanticLabel: 'Filter bookmark Selesai',
                        onTap: () => onFilterByStatus('Selesai'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.download,
                        value: '$downloadsCount',
                        label: 'Offline',
                        color: primaryOrange,
                        isDark: isDark,
                        semanticLabel: 'Buka My Downloads',
                        onTap: onOpenDownloads,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroStatTile(
                        icon: TonztoonIcons.circleDotDashed,
                        value: '$_hiatusCount',
                        label: 'Hiatus',
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                        isActive: isHiatusActive,
                        semanticLabel: 'Filter bookmark Hiatus',
                        onTap: () => onFilterByStatus('Hiatus'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
    required this.semanticLabel,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      selected: isActive,
      label: isActive ? '$semanticLabel (aktif)' : semanticLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isActive
                ? (isDark
                    ? color.withValues(alpha: 0.22)
                    : color.withValues(alpha: 0.16))
                : (isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.white.withValues(alpha: 0.72)),
            gradient: isActive
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            color.withValues(alpha: 0.28),
                            color.withValues(alpha: 0.14),
                          ]
                        : [
                            color.withValues(alpha: 0.22),
                            color.withValues(alpha: 0.10),
                          ],
                  )
                : null,
            borderRadius: borderRadius,
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.18),
              width: isActive ? 1.6 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: isDark ? 0.35 : 0.22),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              children: [
                if (isActive)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: isActive
                                        ? color
                                        : color.withValues(alpha: 0.78),
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    height: 1,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          height: 2.5,
                          width: isActive ? 16 : 0,
                          decoration: BoxDecoration(
                            color: isActive ? color : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
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

// Shared library section header lives in widgets/library_async_pane.dart.
typedef _SectionHeader = LibrarySectionHeader;
