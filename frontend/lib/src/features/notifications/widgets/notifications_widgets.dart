part of '../notifications_screen.dart';

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      key: const ValueKey('notification-summary'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF143248), Color(0xFF402515)]
              : const [Color(0xFFFFF2DD), Color(0xFFE8F6FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.74),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(TonztoonIcons.bell, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unreadCount == 0
                        ? 'Tidak ada notifikasi baru'
                        : '$unreadCount notifikasi baru',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Update chapter, aktivitas pustaka, dan rekomendasi bacaan.',
                    style: theme.textTheme.bodySmall,
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

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selectedFilter, required this.onChanged});

  final String selectedFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in const [
            'Semua',
            'Update',
            'Pustaka',
            'Sistem',
          ]) ...[
            ChoiceChip(
              key: ValueKey('notification-filter-$filter'),
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onChanged(filter),
              showCheckmark: false,
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer
                  : colorScheme.surface,
              selectedColor: colorScheme.primary,
              disabledColor: colorScheme.surfaceContainerLow,
              surfaceTintColor: Colors.transparent,
              labelStyle: TextStyle(
                color: selectedFilter == filter
                    ? colorScheme.onPrimary
                    : isDark
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: selectedFilter == filter
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(
                          alpha: isDark ? 0.8 : 1,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(TonztoonIcons.autoAwesome, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          '$count item',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = _notificationStyle(item);

    // Background color: Blend with primary if unread for a soft modern tint
    final cardColor = item.unread
        ? Color.lerp(colorScheme.surface, colorScheme.primary, 0.07)!
        : colorScheme.surface;

    // Subtle colored shadow for unread, flat shadow for read
    final shadowColor = item.unread
        ? colorScheme.primary.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.04);

    final elevation = item.unread ? 2.5 : 0.8;

    return Material(
      color: cardColor,
      elevation: elevation,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: item.unread
            ? BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.16),
                width: 1,
              )
            : BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                width: 1,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Visual Accent Indicator on the left edge
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 4.5,
                decoration: BoxDecoration(
                  color: item.unread ? colorScheme.primary : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NotificationIcon(
                        icon: style.icon,
                        accent: style.accent,
                        isUnread: item.unread,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: item.unread
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: item.unread
                                              ? null
                                              : (theme
                                                            .textTheme
                                                            .titleMedium
                                                            ?.color ??
                                                        colorScheme.onSurface)
                                                    .withValues(alpha: 0.72),
                                        ),
                                  ),
                                ),
                                if (item.unread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 4,
                                          spreadRadius: 1.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  _relativeTime(item.createdAt),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: item.unread
                                        ? colorScheme.secondary
                                        : colorScheme.secondary.withValues(
                                            alpha: 0.6,
                                          ),
                                    fontWeight: item.unread
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                                color: item.unread
                                    ? null
                                    : (theme.textTheme.bodySmall?.color ??
                                              colorScheme.onSurfaceVariant)
                                          .withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 9),
                            _CategoryPill(
                              label: item.category,
                              isUnread: item.unread,
                            ),
                          ],
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
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({
    required this.icon,
    required this.accent,
    required this.isUnread,
  });

  final IconData icon;
  final Color accent;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isUnread
            ? accent.withValues(alpha: 0.20)
            : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isUnread
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          size: 20,
          color: isUnread ? accent : accent.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.isUnread});

  final String label;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUnread
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: isUnread
                ? null
                : (Theme.of(context).textTheme.labelSmall?.color ??
                          colorScheme.onSurface)
                      .withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
