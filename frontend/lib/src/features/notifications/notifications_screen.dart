import 'package:flutter/material.dart';

import '../../core/app_icons.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedFilter = 'Semua';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifikasi', style: theme.textTheme.titleLarge),
        centerTitle: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(TonztoonIcons.arrowBack),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton(
              onPressed: () {},
              child: const Text('Tandai dibaca'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _NotificationSummary(),
          const SizedBox(height: 18),
          _FilterStrip(
            selectedFilter: _selectedFilter,
            onChanged: (value) => setState(() => _selectedFilter = value),
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: _selectedFilter == 'Semua'
                ? 'Terbaru'
                : 'Kategori $_selectedFilter',
            count: _visibleNotifications(_selectedFilter).length,
          ),
          const SizedBox(height: 10),
          for (final item in _visibleNotifications(_selectedFilter)) ...[
            _NotificationTile(item: item),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF17232E), Color(0xFF261A16)]
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
                  Text('3 notifikasi baru', style: theme.textTheme.titleLarge),
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
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in const [
            'Semua',
            'Update',
            'Pustaka',
            'Rekomendasi',
          ]) ...[
            ChoiceChip(
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onChanged(filter),
              selectedColor: colorScheme.primary.withValues(alpha: 0.18),
              labelStyle: TextStyle(
                color: selectedFilter == filter
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: colorScheme.outlineVariant),
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
  const _NotificationTile({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: item.unread
                  ? colorScheme.primary.withValues(alpha: 0.38)
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NotificationIcon(item: item),
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
                              style: theme.textTheme.titleMedium,
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
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Text(
                            item.time,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryPill(label: item.category),
                        ],
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

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.item});

  final _NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: item.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(item.icon, size: 20, color: item.accent),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

List<_NotificationItem> _visibleNotifications(String filter) {
  if (filter == 'Semua') return _notifications;
  return _notifications
      .where((item) => item.category == filter)
      .toList(growable: false);
}

class _NotificationItem {
  const _NotificationItem({
    required this.title,
    required this.message,
    required this.time,
    required this.category,
    required this.icon,
    required this.accent,
    required this.unread,
  });

  final String title;
  final String message;
  final String time;
  final String category;
  final IconData icon;
  final Color accent;
  final bool unread;
}

const _notifications = [
  _NotificationItem(
    title: 'Solo Leveling selesai diunduh',
    message: 'Chapter 179 sudah siap dibaca offline dari pustaka kamu.',
    time: '2 menit lalu',
    category: 'Pustaka',
    icon: TonztoonIcons.download,
    accent: Color(0xFF3A86FF),
    unread: true,
  ),
  _NotificationItem(
    title: 'Chapter baru tersedia',
    message: 'Omniscient Reader\'s Viewpoint Chapter 200 baru saja rilis.',
    time: '18 menit lalu',
    category: 'Update',
    icon: TonztoonIcons.bookOpen,
    accent: Color(0xFFFF9D00),
    unread: true,
  ),
  _NotificationItem(
    title: 'Rekomendasi untuk kamu',
    message: 'Coba manga aksi supernatural dengan pacing cepat minggu ini.',
    time: '1 jam lalu',
    category: 'Rekomendasi',
    icon: TonztoonIcons.autoAwesome,
    accent: Color(0xFFFFD60A),
    unread: true,
  ),
  _NotificationItem(
    title: 'Bookmark tersinkron',
    message: 'Koleksi Favorit Utama sudah diperbarui di perangkat ini.',
    time: 'Kemarin',
    category: 'Pustaka',
    icon: TonztoonIcons.bookmarkAdded,
    accent: Color(0xFF22C55E),
    unread: false,
  ),
];
