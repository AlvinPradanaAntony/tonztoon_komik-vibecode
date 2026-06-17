part of '../settings_screen.dart';

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.auth});

  final AuthState auth;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  static const double _profileInlineEditButtonBalancedWidth = 28;

  bool _saving = false;
  final AvatarImagePicker _avatarPicker = AvatarImagePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = _displayName(widget.auth);
    final username = widget.auth.user?.username?.trim();
    final initials = _initials(name);
    final avatarUrl = widget.auth.user?.avatarUrl?.trim();

    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipOval(
                          child: ColoredBox(
                            color: colorScheme.surface,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? Center(
                                    child: Text(
                                      initials,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  )
                                : Image.network(
                                    avatarUrl,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                    errorBuilder:
                                        (context, error, stackTrace) => Center(
                                          child: Text(
                                            initials,
                                            style: theme.textTheme.headlineSmall
                                                ?.copyWith(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ),
                                  ),
                          ),
                        ),
                      ),
                      if (avatarUrl == null || avatarUrl.isEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.tertiary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _ProfileEditButton(
                  tooltip: 'Ubah foto profil',
                  busy: _saving,
                  onPressed: _editAvatar,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: _profileInlineEditButtonBalancedWidth),
            Flexible(
              child: Text(
                name,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _ProfileEditButton(
              tooltip: 'Ubah display name',
              variant: _ProfileEditButtonVariant.inline,
              busy: _saving,
              onPressed: _editDisplayName,
            ),
          ],
        ),
        if (username != null && username.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '@$username',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
        ] else
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

  Future<void> _editDisplayName() async {
    final current = widget.auth.user?.displayName?.trim();
    final name = await _showProfileTextDialog(
      context,
      title: 'Edit display name',
      label: 'Display name',
      initialValue: current?.isNotEmpty == true
          ? current!
          : _displayName(widget.auth),
      maxLength: 120,
      emptyError: 'Display name wajib diisi.',
      onSubmit: (value) => ref
          .read(authControllerProvider.notifier)
          .updateProfile(displayName: value),
    );
    if (!mounted || name == null) return;
    showAppSnackBar(
      context,
      message: 'Profil berhasil diperbarui.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _editAvatar() async {
    final source = await _showAvatarSourceSheet(context);
    if (!mounted || source == null) return;

    setState(() => _saving = true);
    var uploadDialogShown = false;
    try {
      final avatar = await _avatarPicker.pick(
        context,
        source,
        onSelected: () {
          if (!mounted) return;
          _showAvatarUploadDialog(context);
          uploadDialogShown = true;
        },
      );
      if (!mounted || avatar == null) return;
      await ref.read(authControllerProvider.notifier).uploadAvatar(avatar);
      if (!mounted) return;
      if (uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        uploadDialogShown = false;
      }
      showAppSnackBar(
        context,
        message: 'Foto profil berhasil diperbarui.',
        type: AppSnackBarType.success,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        uploadDialogShown = false;
      }
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: 'Upload profile avatar failed',
        fallbackMessage: 'Gagal unggah Foto profil. Silakan coba lagi.',
      );
    } finally {
      if (mounted && uploadDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAvatarUploadDialog(BuildContext context) {
    unawaited(
      showTonztoonModal<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const PopScope(canPop: false, child: _AvatarUploadDialog()),
      ),
    );
  }

  Future<ImageSource?> _showAvatarSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(TonztoonIcons.image),
                title: const Text('Pilih dari galeri'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(TonztoonIcons.camera),
                title: const Text('Ambil foto'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayName(AuthState auth) {
    final displayName = auth.user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

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

class _ProfileEditButton extends StatelessWidget {
  const _ProfileEditButton({
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.variant = _ProfileEditButtonVariant.avatar,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;
  final _ProfileEditButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isInline = variant == _ProfileEditButtonVariant.inline;
    final size = isInline ? 24.0 : 30.0;
    final iconSize = isInline ? 12.0 : 14.0;

    return Material(
      color: isInline
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primary,
      shape: const CircleBorder(),
      elevation: isInline ? 0 : 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              TonztoonIcons.pencil,
              size: iconSize,
              color: isInline
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStats extends ConsumerWidget {
  const _ProfileStats({required this.summary});

  final AsyncValue<LibrarySummary> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingTime = ref.watch(readingTimeProvider);
    final bookmarkCount = _bookmarkCountLabel(summary);
    final activeTime = _readingTimeLabel(readingTime);

    return _SettingsSection(
      child: Row(
        children: [
          Expanded(
            child: _StatBlock(
              value: bookmarkCount,
              label: 'Bookmark',
              onTap: () => context.go(libraryBookmarksLocation),
            ),
          ),
          const SizedBox(height: 42, child: VerticalDivider(width: 1)),
          Expanded(
            child: _StatBlock(value: activeTime, label: 'Aktif'),
          ),
        ],
      ),
    );
  }

  String _bookmarkCountLabel(AsyncValue<LibrarySummary> summary) {
    final bookmarkCount = summary.asData?.value.counts.bookmarks;
    if (bookmarkCount == null) return '...';
    if (bookmarkCount > 999) return '999+';
    return '$bookmarkCount';
  }
}

class _GuestReadingTimeCard extends ConsumerWidget {
  const _GuestReadingTimeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readingTime = ref.watch(readingTimeProvider);

    return _SettingsSection(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            const _IconBubble(icon: TonztoonIcons.bookOpen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Waktu Baca Guest',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tersimpan lokal dan bisa dimigrasi saat login',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _readingTimeLabel(readingTime),
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Column(
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
    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: content,
        ),
      ),
    );
  }
}
