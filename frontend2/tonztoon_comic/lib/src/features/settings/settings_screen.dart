import 'package:flutter/material.dart';

import '../../core/app_icons.dart';
import '../../models/comic.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_cover.dart';
import '../comic/comic_detail_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.isSignedIn,
    required this.onOpenAuth,
    required this.onLogout,
  });

  final bool isSignedIn;
  final VoidCallback onOpenAuth;
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _nightMode = false;
  bool _autoNext = true;
  bool _markRead = true;
  bool _bingeMode = false;
  bool _pushNotifications = true;
  String _theme = 'System';
  String _readerMode = 'Vertical';
  String _direction = 'LTR';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSignedIn ? 'My Profile' : 'Settings',
          style: theme.textTheme.titleLarge,
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
        children: [
          if (widget.isSignedIn) ...[
            const _ProfileHeader(),
            const SizedBox(height: 18),
            const _ProfileStats(),
            const SizedBox(height: 24),
            const _SectionLabel(text: 'Account'),
            const SizedBox(height: 8),
            _SettingsSection(
              children: [
                _SettingsRow(
                  icon: TonztoonIcons.settings2,
                  title: 'Privacy & Security',
                  subtitle: 'Password, devices, and account access',
                  onTap: () =>
                      _openAccountFlow(context, const _PrivacySecurityScreen()),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: TonztoonIcons.bookmark,
                  title: 'Saved Collections',
                  subtitle: 'Manage synced reading shelves',
                  onTap: () => _openAccountFlow(
                    context,
                    const _SavedCollectionsScreen(),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: TonztoonIcons.heart,
                  title: 'My Favorites',
                  subtitle: 'Comics and scenes you saved',
                  onTap: () =>
                      _openAccountFlow(context, const _MyFavoritesScreen()),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: TonztoonIcons.bell,
                  title: 'Push Notifications',
                  subtitle: 'New chapters and reading reminders',
                  onTap: () => _openAccountFlow(
                    context,
                    const _PushNotificationsScreen(),
                  ),
                  trailing: Switch.adaptive(
                    value: _pushNotifications,
                    onChanged: (value) =>
                        setState(() => _pushNotifications = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          const _SectionLabel(text: 'Preferences'),
          const SizedBox(height: 8),
          _PreferencesSection(
            nightMode: _nightMode,
            theme: _theme,
            readerMode: _readerMode,
            direction: _direction,
            autoNext: _autoNext,
            markRead: _markRead,
            bingeMode: _bingeMode,
            isSignedIn: widget.isSignedIn,
            onNightModeChanged: (value) => setState(() => _nightMode = value),
            onThemeChanged: (value) => setState(() => _theme = value),
            onReaderModeChanged: (value) => setState(() => _readerMode = value),
            onDirectionChanged: (value) => setState(() => _direction = value),
            onAutoNextChanged: (value) => setState(() => _autoNext = value),
            onMarkReadChanged: (value) => setState(() => _markRead = value),
            onBingeModeChanged: (value) => setState(() => _bingeMode = value),
            onOpenAuth: widget.onOpenAuth,
          ),
          if (widget.isSignedIn) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(TonztoonIcons.logout, size: 18),
              label: const Text('Logout'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _openAccountFlow(BuildContext context, Widget page) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => page));
}

Future<String?> _showProfileCollectionDialog(BuildContext context) {
  var value = '';

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Koleksi baru'),
      content: TextField(
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Nama koleksi',
          hintText: 'Contoh: Rekomendasi minggu ini',
        ),
        onChanged: (text) => value = text,
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(value),
          child: const Text('Buat'),
        ),
      ],
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.tertiary, width: 2),
          ),
          child: Center(
            child: Text(
              'TT',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('TonzToon Reader', style: theme.textTheme.titleLarge),
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats();

  @override
  Widget build(BuildContext context) {
    return const _SettingsSection(
      child: Row(
        children: [
          Expanded(
            child: _StatBlock(value: '12', label: 'Works'),
          ),
          SizedBox(height: 42, child: VerticalDivider(width: 1)),
          Expanded(
            child: _StatBlock(value: '14.2K', label: 'Followers'),
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
          ),
        ),
      ],
    );
  }
}

class _PrivacySecurityScreen extends StatelessWidget {
  const _PrivacySecurityScreen();

  @override
  Widget build(BuildContext context) {
    return _AccountFlowScaffold(
      title: 'Privacy & Security',
      children: const [
        _SecurityScoreCard(),
        SizedBox(height: 18),
        _SectionLabel(text: 'Account Protection'),
        SizedBox(height: 8),
        _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.mail,
              title: 'Email Verification',
              subtitle: 'reader@tonztoon.app verified',
              trailing: _StatusBadge(label: 'Verified'),
            ),
            _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.keyRound,
              title: 'Change Password',
              subtitle: 'Last changed 2 months ago',
            ),
            _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.shieldCheck,
              title: 'Two-step Verification',
              subtitle: 'Add an extra layer before signing in',
              trailing: _StatusBadge(label: 'On'),
            ),
          ],
        ),
        SizedBox(height: 20),
        _SectionLabel(text: 'Active Sessions'),
        SizedBox(height: 8),
        _SettingsSection(
          children: [
            _DeviceRow(
              title: 'Android Phone',
              subtitle: 'Current device - Jakarta',
              icon: Icons.phone_android_rounded,
              active: true,
            ),
            _SettingsDivider(),
            _DeviceRow(
              title: 'Chrome Browser',
              subtitle: 'Last active yesterday',
              icon: Icons.desktop_windows_rounded,
              active: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _SecurityScoreCard extends StatelessWidget {
  const _SecurityScoreCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                TonztoonIcons.shieldCheck,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Security looks good',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2-step verification and verified email are active.',
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

class _SavedCollectionsScreen extends StatefulWidget {
  const _SavedCollectionsScreen();

  @override
  State<_SavedCollectionsScreen> createState() =>
      _SavedCollectionsScreenState();
}

class _SavedCollectionsScreenState extends State<_SavedCollectionsScreen> {
  late final List<_ProfileCollection> _collections = List.of(
    _profileCollections,
  );

  @override
  Widget build(BuildContext context) {
    return _AccountFlowScaffold(
      title: 'Saved Collections',
      action: IconButton(
        tooltip: 'Tambah koleksi',
        onPressed: _createCollection,
        icon: const Icon(TonztoonIcons.plus),
      ),
      children: [
        const _SectionLabel(text: 'Collections'),
        const SizedBox(height: 8),
        if (_collections.isEmpty)
          const _ProfileCollectionEmptyState()
        else
          for (final collection in _collections) ...[
            _CollectionFlowTile(collection: collection),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Future<void> _createCollection() async {
    final title = await _showProfileCollectionDialog(context);
    if (!mounted || title == null || title.trim().isEmpty) return;

    setState(() {
      _collections.insert(
        0,
        _ProfileCollection(
          title: title.trim(),
          subtitle: 'Koleksi sinkron baru',
          comics: [dummyComics[0], dummyComics[2]],
        ),
      );
    });
  }
}

class _CollectionDetailScreen extends StatelessWidget {
  const _CollectionDetailScreen({required this.collection});

  final _ProfileCollection collection;

  @override
  Widget build(BuildContext context) {
    return _AccountFlowScaffold(
      title: collection.title,
      children: [
        Text(collection.subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        for (final comic in collection.comics) ...[
          _ComicMiniTile(comic: comic),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CollectionFlowTile extends StatelessWidget {
  const _CollectionFlowTile({required this.collection});

  final _ProfileCollection collection;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceInk(
      onTap: () => _openAccountFlow(
        context,
        _CollectionDetailScreen(collection: collection),
      ),
      child: Row(
        children: [
          _CoverStack(comics: collection.comics),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  collection.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(TonztoonIcons.chevronRight),
        ],
      ),
    );
  }
}

class _ProfileCollectionEmptyState extends StatelessWidget {
  const _ProfileCollectionEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Icon(TonztoonIcons.bookmark, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada koleksi tersimpan.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _MyFavoritesScreen extends StatelessWidget {
  const _MyFavoritesScreen();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Favorites'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Comics'),
              Tab(text: 'Scenes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                for (final comic in dummyComics) ...[
                  _ComicMiniTile(comic: comic),
                  const SizedBox(height: 12),
                ],
              ],
            ),
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: dummyComics.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) =>
                  _FavoriteSceneCard(comic: dummyComics[index], index: index),
            ),
          ],
        ),
      ),
    );
  }
}

class _PushNotificationsScreen extends StatefulWidget {
  const _PushNotificationsScreen();

  @override
  State<_PushNotificationsScreen> createState() =>
      _PushNotificationsScreenState();
}

class _PushNotificationsScreenState extends State<_PushNotificationsScreen> {
  bool _newChapters = true;
  bool _librarySync = true;
  bool _recommendations = false;
  bool _quietHours = true;

  @override
  Widget build(BuildContext context) {
    return _AccountFlowScaffold(
      title: 'Push Notifications',
      children: [
        const _NotificationPreviewCard(),
        const SizedBox(height: 18),
        const _SectionLabel(text: 'Categories'),
        const SizedBox(height: 8),
        _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.bookOpen,
              title: 'New Chapters',
              subtitle: 'Notify when followed comics update',
              trailing: Switch.adaptive(
                value: _newChapters,
                onChanged: (value) => setState(() => _newChapters = value),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.library,
              title: 'Library Sync',
              subtitle: 'Collections, bookmarks, and offline status',
              trailing: Switch.adaptive(
                value: _librarySync,
                onChanged: (value) => setState(() => _librarySync = value),
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              icon: TonztoonIcons.autoAwesome,
              title: 'Recommendations',
              subtitle: 'New picks based on your taste',
              trailing: Switch.adaptive(
                value: _recommendations,
                onChanged: (value) => setState(() => _recommendations = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionLabel(text: 'Delivery'),
        const SizedBox(height: 8),
        _SettingsSection(
          children: [
            _SettingsRow(
              icon: TonztoonIcons.clock,
              title: 'Quiet Hours',
              subtitle: 'Pause alerts between 22:00 - 07:00',
              trailing: Switch.adaptive(
                value: _quietHours,
                onChanged: (value) => setState(() => _quietHours = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationPreviewCard extends StatelessWidget {
  const _NotificationPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            _IconBubble(icon: TonztoonIcons.bell),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Chapter baru, sinkron pustaka, dan rekomendasi akan tampil sebagai kartu ringkas.',
              ),
            ),
          ],
        ),
      ),
    );
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

class _ComicMiniTile extends StatelessWidget {
  const _ComicMiniTile({required this.comic});

  final ComicSummary comic;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceInk(
      onTap: () => _openAccountFlow(context, ComicDetailScreen(comic: comic)),
      child: Row(
        children: [
          ComicCover(imageUrl: comic.coverImageUrl, width: 54, height: 76),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (comic.type != null) comic.type!,
                    if (comic.latestChapterNumber != null)
                      'Ch ${formatChapterNumber(comic.latestChapterNumber!)}',
                  ].join(' - '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(TonztoonIcons.chevronRight),
        ],
      ),
    );
  }
}

class _FavoriteSceneCard extends StatelessWidget {
  const _FavoriteSceneCard({required this.comic, required this.index});

  final ComicSummary comic;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceInk(
      onTap: () => _openAccountFlow(context, ComicDetailScreen(comic: comic)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ComicCover(imageUrl: comic.coverImageUrl, borderRadius: 0),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comic.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 3),
          Text(
            'Scene ${index + 1} - Page ${(index + 1) * 4}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.comics});

  final List<ComicSummary> comics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 72,
      child: Stack(
        children: [
          for (var index = 0; index < comics.take(3).length; index++)
            Positioned(
              left: index * 16,
              top: index * 5,
              child: ComicCover(
                imageUrl: comics[index].coverImageUrl,
                width: 42,
                height: 58,
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountFlowScaffold extends StatelessWidget {
  const _AccountFlowScaffold({
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (action != null)
            Padding(padding: const EdgeInsets.only(right: 10), child: action!),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: children,
      ),
    );
  }
}

class _ProfileCollection {
  const _ProfileCollection({
    required this.title,
    required this.subtitle,
    required this.comics,
  });

  final String title;
  final String subtitle;
  final List<ComicSummary> comics;
}

final _profileCollections = [
  _ProfileCollection(
    title: 'Favorit Utama',
    subtitle: 'Komik yang paling sering dibaca',
    comics: [dummyComics[0], dummyComics[2], dummyComics[3]],
  ),
  _ProfileCollection(
    title: 'Baca Saat Santai',
    subtitle: 'Pilihan ringan untuk malam hari',
    comics: [dummyComics[1], dummyComics[3]],
  ),
  _ProfileCollection(
    title: 'Tunggu Tamat',
    subtitle: 'Ongoing yang menunggu batch chapter',
    comics: [dummyComics[2], dummyComics[1], dummyComics[0]],
  ),
];

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.nightMode,
    required this.theme,
    required this.readerMode,
    required this.direction,
    required this.autoNext,
    required this.markRead,
    required this.bingeMode,
    required this.isSignedIn,
    required this.onNightModeChanged,
    required this.onThemeChanged,
    required this.onReaderModeChanged,
    required this.onDirectionChanged,
    required this.onAutoNextChanged,
    required this.onMarkReadChanged,
    required this.onBingeModeChanged,
    required this.onOpenAuth,
  });

  final bool nightMode;
  final String theme;
  final String readerMode;
  final String direction;
  final bool autoNext;
  final bool markRead;
  final bool bingeMode;
  final bool isSignedIn;
  final ValueChanged<bool> onNightModeChanged;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onReaderModeChanged;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<bool> onAutoNextChanged;
  final ValueChanged<bool> onMarkReadChanged;
  final ValueChanged<bool> onBingeModeChanged;
  final VoidCallback onOpenAuth;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      children: [
        _SettingsRow(
          icon: TonztoonIcons.darkMode,
          title: 'Night Mode',
          subtitle: 'Use a darker reading surface',
          trailing: Switch.adaptive(
            value: nightMode,
            onChanged: onNightModeChanged,
          ),
        ),
        const _SettingsDivider(),
        _SegmentedSetting(
          icon: TonztoonIcons.lightMode,
          title: 'Theme',
          options: const {
            'System': Icons.brightness_auto_rounded,
            'Light': Icons.light_mode_rounded,
            'Dark': Icons.dark_mode_rounded,
          },
          selected: theme,
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
          selected: readerMode,
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
          selected: direction,
          onChanged: onDirectionChanged,
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.skipForward,
          title: 'Auto-next Chapter',
          subtitle: 'Continue when a chapter ends',
          trailing: Switch.adaptive(
            value: autoNext,
            onChanged: onAutoNextChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.check,
          title: 'Mark Read on Complete',
          subtitle: 'Save completed chapters visually',
          trailing: Switch.adaptive(
            value: markRead,
            onChanged: onMarkReadChanged,
          ),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          icon: TonztoonIcons.localFireDepartment,
          title: 'Binge Mode Default',
          subtitle: 'Keep the reader focused for long sessions',
          trailing: Switch.adaptive(
            value: bingeMode,
            onChanged: onBingeModeChanged,
          ),
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        entry.value,
                        size: 18,
                        color: selected == entry.key
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
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
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
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
