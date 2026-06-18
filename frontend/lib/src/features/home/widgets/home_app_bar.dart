part of '../home_screen.dart';

class _HomeTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeTopAppBar({
    required this.floating,
    required this.authenticated,
    required this.unreadNotifications,
    required this.onActionPressed,
  });

  final bool floating;
  final bool authenticated;
  final int unreadNotifications;
  final VoidCallback onActionPressed;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBarColor =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final transparentAppBarColor = appBarColor.withValues(alpha: 0);
    final capsuleColor = theme.colorScheme.surface;
    final transparentCapsuleColor = capsuleColor.withValues(alpha: 0);
    final statusBarStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemStatusBarContrastEnforced: false,
    );

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: floating ? 1 : 0),
      builder: (context, progress, child) {
        return AppBar(
          backgroundColor: Color.lerp(
            appBarColor,
            transparentAppBarColor,
            progress,
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.none,
          systemOverlayStyle: statusBarStyle,
          titleSpacing: 0,
          title: Padding(
            padding: EdgeInsets.lerp(
              EdgeInsets.zero,
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              progress,
            )!,
            child: Container(
              key: const ValueKey('home-top-app-bar-capsule'),
              decoration: BoxDecoration(
                color: Color.lerp(
                  transparentCapsuleColor,
                  capsuleColor,
                  progress,
                ),
                borderRadius: BorderRadius.circular(28 * progress),
                boxShadow: progress == 0
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.10 * progress,
                          ),
                          blurRadius: 20 * progress,
                          offset: Offset(0, 10 * progress),
                        ),
                      ],
              ),
              child: Padding(
                padding: EdgeInsets.lerp(
                  const EdgeInsets.only(left: 16, right: 10),
                  const EdgeInsets.only(left: 14, right: 6),
                  progress,
                )!,
                child: Row(
                  children: [
                    Image.asset(
                      AppAssets.logoAppLarge,
                      height: 32 - (4 * progress),
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    if (!authenticated) ...[
                      const _GuestModeChip(),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      tooltip: authenticated ? 'Notifikasi' : 'Login',
                      onPressed: onActionPressed,
                      icon: authenticated
                          ? _NotificationBellBadge(count: unreadNotifications)
                          : const Icon(TonztoonIcons.accountCircle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GuestModeChip extends StatelessWidget {
  const _GuestModeChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      label: 'Mode Guest',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              'Mode Guest',
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationBellBadge extends StatelessWidget {
  const _NotificationBellBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      alignment: Alignment.topRight,
      offset: const Offset(4, -4),
      child: AnimatedNotificationBell(active: count > 0),
    );
  }
}
