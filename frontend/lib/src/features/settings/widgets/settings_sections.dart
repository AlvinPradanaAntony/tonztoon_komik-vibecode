part of '../settings_screen.dart';

class _AccountFlowScaffold extends StatelessWidget {
  const _AccountFlowScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: children,
      ),
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.prefs,
    required this.themeMode,
    required this.showHomeHelpdeskButton,
    required this.isSignedIn,
    required this.onThemeChanged,
    required this.onReaderModeChanged,
    required this.onDirectionChanged,
    required this.onBingeModeChanged,
    required this.onAutoScrollChanged,
    required this.onMarkReadChanged,
    required this.onHomeHelpdeskButtonChanged,
    required this.onClearCache,
    required this.onOpenAuth,
  });

  final ReaderPreferences prefs;
  final ThemeMode themeMode;
  final bool showHomeHelpdeskButton;
  final bool isSignedIn;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onReaderModeChanged;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<bool> onBingeModeChanged;
  final ValueChanged<bool> onAutoScrollChanged;
  final ValueChanged<bool> onMarkReadChanged;
  final ValueChanged<bool> onHomeHelpdeskButtonChanged;
  final VoidCallback onClearCache;
  final VoidCallback onOpenAuth;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      children: [
        _SegmentedSetting(
          icon: TonztoonIcons.lightMode,
          title: 'Theme',
          options: const {
            'System': Icons.brightness_auto_rounded,
            'Light': Icons.light_mode_rounded,
            'Dark': Icons.dark_mode_rounded,
          },
          selected: _themeModeLabel(themeMode),
          onChanged: onThemeChanged,
        ),
        const _SettingsDivider(),
        _SegmentedSetting(
          icon: TonztoonIcons.bookOpen,
          title: 'Reader Mode',
          options: const {
            'Vertical': Icons.view_day_rounded,
            'Paged': Icons.view_carousel_rounded,
          },
          selected: _readerModeLabel(prefs.defaultReadingMode),
          onChanged: onReaderModeChanged,
        ),
        const _SettingsDivider(),
        _SegmentedSetting(
          icon: TonztoonIcons.rows,
          title: 'Direction',
          options: const {
            'LTR': Icons.format_textdirection_l_to_r_rounded,
            'RTL': Icons.format_textdirection_r_to_l_rounded,
          },
          selected: _directionLabel(prefs.readingDirection),
          onChanged: onDirectionChanged,
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.skipForward,
          title: 'Binge Mode',
          subtitle: 'Auto-next chapter dan continuous reading',
          trailing: Switch.adaptive(
            value: prefs.defaultBingeMode,
            onChanged: onBingeModeChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.play,
          title: 'AutoScroll',
          subtitle: 'Tampilkan kontrol scroll otomatis di reader',
          trailing: Switch.adaptive(
            value: prefs.autoScrollEnabled,
            onChanged: onAutoScrollChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.check,
          title: 'Mark Read on Complete',
          subtitle: 'Save completed chapters visually',
          trailing: Switch.adaptive(
            value: prefs.markReadOnComplete,
            onChanged: onMarkReadChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.lifeBuoy,
          title: 'Home Helpdesk Button',
          subtitle: 'Tampilkan tombol helpdesk di halaman Home',
          trailing: Switch.adaptive(
            value: showHomeHelpdeskButton,
            onChanged: onHomeHelpdeskButtonChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.paintbrush,
          title: 'Clear Catalog Cache',
          subtitle: 'Refresh source, catalog, comic, and chapter data',
          onTap: onClearCache,
        ),
        if (!isSignedIn) ...[
          const _SettingsDivider(),
          _SettingsRow(
            icon: TonztoonIcons.login,
            title: 'Login / Register',
            subtitle: 'Email, Google, atau lanjut sebagai guest',
            onTap: onOpenAuth,
          ),
        ],
      ],
    );
  }
}

class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final Map<String, IconData> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeBackground = colorScheme.primary;
    final activeForeground = colorScheme.onPrimary;
    final inactiveForeground = colorScheme.onSurfaceVariant;
    final trackBackground = colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      child: Row(
        children: [
          _IconBubble(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: trackBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in options.entries)
                  GestureDetector(
                    onTap: () => onChanged(entry.key),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected == entry.key
                            ? activeBackground
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        entry.value,
                        size: 18,
                        color: selected == entry.key
                            ? activeForeground
                            : inactiveForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppVersionSection extends StatelessWidget {
  const _AppVersionSection({
    required this.packageInfoFuture,
    required this.checkingForUpdate,
    required this.onCheckForUpdate,
    required this.onShowAppInfo,
  });

  final Future<PackageInfo> packageInfoFuture;
  final bool checkingForUpdate;
  final VoidCallback onCheckForUpdate;
  final VoidCallback onShowAppInfo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: packageInfoFuture,
      builder: (context, snapshot) {
        final versionLabel = switch (snapshot) {
          AsyncSnapshot<PackageInfo>(hasData: true, data: final info?) =>
            _formatVersion(info),
          AsyncSnapshot<PackageInfo>(hasError: true) => 'Tidak tersedia',
          _ => 'Memuat...',
        };

        return _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.badge,
              title: 'App Version',
              subtitle: 'Mengikuti metadata build terbaru',
              onTap: onShowAppInfo,
              trailing: Text(
                versionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: Icons.system_update_alt_rounded,
              title: 'Check for Update',
              subtitle: 'Periksa rilis terbaru dari GitHub',
              trailing: checkingForUpdate
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: checkingForUpdate ? null : onCheckForUpdate,
            ),
          ],
        );
      },
    );
  }

  String _formatVersion(PackageInfo info) {
    final version = info.version.trim();
    final buildNumber = info.buildNumber.trim();
    if (version.isEmpty && buildNumber.isEmpty) return 'Tidak tersedia';
    if (buildNumber.isEmpty) return 'v$version';
    if (version.isEmpty) return 'Build $buildNumber';
    return 'v$version ($buildNumber)';
  }
}
