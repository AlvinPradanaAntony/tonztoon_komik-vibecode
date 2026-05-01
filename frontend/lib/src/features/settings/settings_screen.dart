import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_icons.dart';
import '../../models/auth.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushNotifications = true;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final prefs = ref.watch(readerPreferencesProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final isSignedIn = auth.isAuthenticated;

    return Scaffold(
      body: SafeArea(
        child: AppAsyncView<ReaderPreferences>(
          value: prefs,
          onRetry: () => ref.invalidate(readerPreferencesProvider),
          builder: (value) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
            children: [
              _ProfileTopBar(
                isSignedIn: isSignedIn,
                title: isSignedIn ? 'My Profile' : 'Settings',
                subtitle: isSignedIn
                    ? 'Your account and reading setup'
                    : 'Preferences stay on this device',
              ),
              const SizedBox(height: 18),
              if (isSignedIn) ...[
                _ProfileHeader(auth: auth),
                const SizedBox(height: 18),
                const _ProfileStats(),
                const SizedBox(height: 26),
                _SectionLabel(text: 'Account'),
                const SizedBox(height: 8),
                _ProfileSection(
                  children: [
                    const _ProfileRow(
                      icon: TonztoonIcons.shieldCheck,
                      title: 'Privacy & Security',
                    ),
                    const _ProfileDivider(),
                    const _ProfileRow(
                      icon: TonztoonIcons.mapPin,
                      title: 'Saved Addresses',
                    ),
                    const _ProfileDivider(),
                    const _ProfileRow(
                      icon: TonztoonIcons.heart,
                      title: 'My Favorites',
                    ),
                    const _ProfileDivider(),
                    _ProfileRow(
                      icon: TonztoonIcons.bell,
                      title: 'Push Notifications',
                      trailing: Switch.adaptive(
                        value: _pushNotifications,
                        onChanged: (enabled) =>
                            setState(() => _pushNotifications = enabled),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              const _SectionLabel(text: 'Preferences'),
              const SizedBox(height: 8),
              _PreferencesSection(
                prefs: value,
                themeMode: themeMode,
                onThemeChanged: (mode) =>
                    ref.read(appThemeModeProvider.notifier).setMode(mode),
                onPrefsChanged: _save,
                onClearCache: _clearCache,
              ),
              if (isSignedIn) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(TonztoonIcons.logout, size: 18),
                  label: const Text('Sign Out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(ReaderPreferences prefs) async {
    await ref.read(libraryRepositoryProvider).saveReaderPreferences(prefs);
    ref.invalidate(readerPreferencesProvider);
  }

  Future<void> _clearCache() async {
    await ref.read(localStoreProvider).cache.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cache cleared.')));
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    ref.invalidate(homeDataProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signed out.')));
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.isSignedIn,
    required this.title,
    required this.subtitle,
  });

  final bool isSignedIn;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              isSignedIn ? TonztoonIcons.accountCircle : TonztoonIcons.settings,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = _displayName(auth);
    final initials = _initials(name);

    return Column(
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.tertiary, width: 2),
          ),
          child: Center(
            child: Text(
              initials,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              'READER',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _displayName(AuthState auth) {
    final email = auth.user?.email;
    if (email == null || email.trim().isEmpty) return 'TonzToon Reader';
    final handle = email.split('@').first;
    final words = handle
        .split(RegExp(r'[._-]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return handle;
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String _initials(String name) {
    final words = name.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return 'TT';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats();

  @override
  Widget build(BuildContext context) {
    return _ProfileSection(
      child: const Row(
        children: [
          Expanded(
            child: _StatBlock(value: '12', label: 'Works'),
          ),
          SizedBox(height: 42, child: VerticalDivider(width: 1)),
          Expanded(
            child: _StatBlock(value: '14.2k', label: 'Followers'),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.tertiary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.prefs,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onPrefsChanged,
    required this.onClearCache,
  });

  final ReaderPreferences prefs;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<ReaderPreferences> onPrefsChanged;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    return _ProfileSection(
      children: [
        _ProfileRow(
          icon: TonztoonIcons.darkMode,
          title: 'Night Mode',
          trailing: Switch.adaptive(
            value: themeMode == ThemeMode.dark,
            onChanged: (enabled) =>
                onThemeChanged(enabled ? ThemeMode.dark : ThemeMode.light),
          ),
        ),
        const _ProfileDivider(),
        _ControlRow(
          icon: TonztoonIcons.contrast,
          title: 'Theme',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(TonztoonIcons.devices),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(TonztoonIcons.lightMode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(TonztoonIcons.darkMode),
                label: Text('Dark'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selected) => onThemeChanged(selected.first),
          ),
        ),
        const _ProfileDivider(),
        _ControlRow(
          icon: TonztoonIcons.autoStoriesRounded,
          title: 'Reader Mode',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'vertical',
                icon: Icon(TonztoonIcons.viewAgenda),
                label: Text('Vertical'),
              ),
              ButtonSegment(
                value: 'paged',
                icon: Icon(TonztoonIcons.autoStories),
                label: Text('Paged'),
              ),
            ],
            selected: {prefs.defaultReadingMode},
            onSelectionChanged: (selected) => onPrefsChanged(
              prefs.copyWith(defaultReadingMode: selected.first),
            ),
          ),
        ),
        const _ProfileDivider(),
        _ControlRow(
          icon: TonztoonIcons.slidersHorizontal,
          title: 'Direction',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ltr', label: Text('LTR')),
              ButtonSegment(value: 'rtl', label: Text('RTL')),
            ],
            selected: {prefs.readingDirection},
            onSelectionChanged: (selected) => onPrefsChanged(
              prefs.copyWith(readingDirection: selected.first),
            ),
          ),
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.skipNext,
          title: 'Auto-next Chapter',
          trailing: Switch.adaptive(
            value: prefs.autoNext,
            onChanged: (enabled) =>
                onPrefsChanged(prefs.copyWith(autoNext: enabled)),
          ),
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.bookOpenCheck,
          title: 'Mark Read on Complete',
          trailing: Switch.adaptive(
            value: prefs.markReadOnComplete,
            onChanged: (enabled) =>
                onPrefsChanged(prefs.copyWith(markReadOnComplete: enabled)),
          ),
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.localFireDepartment,
          title: 'Binge Mode Default',
          trailing: Switch.adaptive(
            value: prefs.defaultBingeMode,
            onChanged: (enabled) =>
                onPrefsChanged(prefs.copyWith(defaultBingeMode: enabled)),
          ),
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.gift,
          title: 'Donate to Creators',
          onTap: () {},
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.settings,
          title: 'App Settings',
          onTap: () {},
        ),
        const _ProfileDivider(),
        _ProfileRow(
          icon: TonztoonIcons.cleaningServices,
          title: 'Clear Catalog Cache',
          onTap: onClearCache,
        ),
      ],
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
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({this.child, this.children});

  final Widget? child;
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child ?? Column(children: children ?? const []),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
            trailing ??
                Icon(
                  TonztoonIcons.chevronRight,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: child),
        ],
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 48,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
