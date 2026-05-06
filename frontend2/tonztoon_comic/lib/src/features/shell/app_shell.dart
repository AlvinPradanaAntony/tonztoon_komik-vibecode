import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_icons.dart';
import '../auth/auth_screen.dart';
import '../catalog/full_catalog_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// [AppShell] adalah rangka luar aplikasi.
/// Komponen ini bertugas mengelola Bottom Navigation Bar dan berpindah
/// antar halaman utama tanpa menghilangkan state navigasi.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  bool _isSignedIn = false;
  bool _exitDialogOpen = false;
  final List<Widget> _staticPages = const [
    HomeScreen(),
    FullCatalogScreen(showBackButton: false),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Saat masuk ke Home, kembali ke mode normal dengan bar transparan
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _confirmExitApp();
        },
        child: Scaffold(
          // Penting agar konten dirender penuh hingga ke bawah layar, melewati floating nav bar
          extendBody: true,
          body: Stack(
            children: [
              // Konten Utama
              Positioned.fill(
                child: IndexedStack(index: _currentIndex, children: _pages),
              ),
              // Masking Fade Gradient di bagian bawah
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 120, // Tinggi area fade mask
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.6, 1.0],
                        colors: [
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
                          theme.scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildFloatingNavBar(context),
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(left: 56, right: 56, bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        // Material digunakan agar efek InkWell (hover/ripple) bisa terlihat
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final item in _navigationItems)
                  _NavItem(
                    item: item,
                    selected: _currentIndex == item.index,
                    onTap: () => setState(() => _currentIndex = item.index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> get _pages => [
    ..._staticPages,
    SettingsScreen(
      isSignedIn: _isSignedIn,
      onOpenAuth: _openAuth,
      onLogout: () => setState(() => _isSignedIn = false),
    ),
  ];

  List<_NavigationItem> get _navigationItems => [
    const _NavigationItem(icon: TonztoonIcons.home, index: 0, label: 'Home'),
    const _NavigationItem(icon: TonztoonIcons.list, index: 1, label: 'Katalog'),
    const _NavigationItem(icon: TonztoonIcons.search, index: 2, label: 'Cari'),
    const _NavigationItem(
      icon: TonztoonIcons.library,
      index: 3,
      label: 'Pustaka',
    ),
    _NavigationItem(
      icon: _isSignedIn ? TonztoonIcons.accountCircle : TonztoonIcons.settings,
      index: 4,
      label: _isSignedIn ? 'Profil' : 'Setelan',
    ),
  ];

  Future<void> _openAuth() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AuthScreen(
          onEmailAuthenticated: () => _completeAuth(context, signedIn: true),
          onGoogleAuthenticated: () => _completeAuth(context, signedIn: true),
          onContinueGuest: () => _completeAuth(context, signedIn: false),
        ),
      ),
    );
  }

  void _completeAuth(BuildContext authContext, {required bool signedIn}) {
    setState(() {
      _isSignedIn = signedIn;
      _currentIndex = 4;
    });
    Navigator.of(authContext).pop();
  }

  Future<void> _confirmExitApp() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(TonztoonIcons.logout, color: colorScheme.error),
          title: const Text('Keluar dari aplikasi?'),
          content: const Text('Kamu yakin ingin menutup TonzToon sekarang?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    _exitDialogOpen = false;
    if (!mounted || shouldExit != true) return;
    await SystemNavigator.pop();
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Tooltip(
      message: item.label,
      preferBelow: false,
      verticalOffset: 32,
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(item.icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.icon,
    required this.index,
    required this.label,
  });

  final IconData icon;
  final int index;
  final String label;
}
