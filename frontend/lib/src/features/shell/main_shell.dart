import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../repositories/providers.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  int get _currentIndex {
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/library')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSignedIn = ref.watch(authControllerProvider).isAuthenticated;
    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: _FloatingBottomNavBar(
        currentIndex: _currentIndex,
        isSignedIn: isSignedIn,
        onSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/search');
            case 2:
              context.go('/library');
            case 3:
              context.go('/settings');
          }
        },
      ),
    );
  }
}

class _FloatingBottomNavBar extends StatelessWidget {
  const _FloatingBottomNavBar({
    required this.currentIndex,
    required this.isSignedIn,
    required this.onSelected,
  });

  final int currentIndex;
  final bool isSignedIn;
  final ValueChanged<int> onSelected;

  static const _baseItems = [
    _NavItem(label: 'Home', icon: TonztoonIcons.home),
    _NavItem(label: 'Search', icon: TonztoonIcons.search),
    _NavItem(label: 'Library', icon: TonztoonIcons.library),
  ];

  List<_NavItem> get _items => [
    ..._baseItems,
    if (isSignedIn)
      const _NavItem(label: 'Profile', icon: TonztoonIcons.accountCircle)
    else
      const _NavItem(label: 'Settings', icon: TonztoonIcons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.92),
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < _items.length; index++)
                    _FloatingNavButton(
                      item: _items[index],
                      selected: index == currentIndex,
                      onTap: () => onSelected(index),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavButton extends StatelessWidget {
  const _FloatingNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: item.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: selected ? 58 : 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(item.icon, color: foreground, size: 22),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    bottom: selected ? 6 : -6,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: selected ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const SizedBox(width: 4, height: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
