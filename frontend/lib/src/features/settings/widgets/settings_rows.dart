part of '../settings_screen.dart';

class _FavoriteScenesSettingsRow extends ConsumerWidget {
  const _FavoriteScenesSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.favoriteScenes;

    return _SettingsRow(
      icon: TonztoonIcons.heart,
      title: 'My Favorites',
      subtitle: count == null
          ? 'Favorite comic scenes only'
          : '$count scene komik favorit',
      onTap: () => _openAccountFlow(context, const _MyFavoritesScreen()),
    );
  }
}

class _SavedCollectionsSettingsRow extends ConsumerWidget {
  const _SavedCollectionsSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.collections;

    return _SettingsRow(
      icon: TonztoonIcons.bookmark,
      title: 'Saved Collections',
      subtitle: count == null
          ? 'Synced reading shelves'
          : '$count koleksi tersinkron',
      onTap: () => context.go(libraryCollectionsLocation),
    );
  }
}

class _MyDownloadsSettingsRow extends ConsumerWidget {
  const _MyDownloadsSettingsRow({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = summary.asData?.value.counts.downloads;

    return _SettingsRow(
      icon: TonztoonIcons.download,
      title: 'My Downloads',
      subtitle: count == null
          ? 'Synced download wishlist'
          : '$count chapter tersimpan di wishlist download',
      onTap: () => _openAccountFlow(context, const _MyDownloadsScreen()),
    );
  }
}

class _PushNotificationsSettingsRow extends ConsumerStatefulWidget {
  const _PushNotificationsSettingsRow();

  @override
  ConsumerState<_PushNotificationsSettingsRow> createState() =>
      _PushNotificationsSettingsRowState();
}

class _PushNotificationsSettingsRowState
    extends ConsumerState<_PushNotificationsSettingsRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(pushNotificationPreferencesProvider);

    return _SettingsRow(
      icon: TonztoonIcons.bell,
      title: 'Push Notifications',
      subtitle: preferences.enabled
          ? 'Update chapter dan status download aktif'
          : 'Aktifkan alert untuk perangkat ini',
      onTap: _saving ? null : () => _setEnabled(!preferences.enabled),
      trailing: Switch.adaptive(
        value: preferences.enabled,
        onChanged: _saving ? null : _setEnabled,
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      if (value) {
        final localGranted = await ref
            .read(pushNotificationServiceProvider)
            .requestPermissions();
        final remoteGranted = await ref
            .read(pushRegistrationServiceProvider)
            .requestPermissions();
        if (!localGranted || !remoteGranted) {
          if (!mounted) return;
          showAppSnackBar(
            context,
            message:
                'Izin notifikasi belum diberikan. Aktifkan izin TonzToon dari pengaturan perangkat.',
            type: AppSnackBarType.warning,
          );
          return;
        }
      }

      await ref
          .read(pushNotificationPreferencesProvider.notifier)
          .setEnabled(value);
      if (!value) {
        await ref.read(pushNotificationServiceProvider).dismissAll();
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Update push notification preference failed',
        fallbackMessage: 'Pengaturan notifikasi belum dapat disimpan.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.active,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: active ? const _StatusBadge(label: 'Now') : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({this.child, this.children});

  final Widget? child;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.24
                  : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child ?? Column(children: children ?? const []),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: colorScheme.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          child: Row(
            children: [
              _IconBubble(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    TonztoonIcons.chevronRight,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 50,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
