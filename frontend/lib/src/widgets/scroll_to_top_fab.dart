import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';

class ScrollToTopFab extends StatefulWidget {
  const ScrollToTopFab({
    super.key,
    required this.controller,
    this.visibilityOffset = 220,
  });

  final ScrollController controller;
  final double visibilityOffset;

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
  }

  @override
  void didUpdateWidget(covariant ScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncVisibility);
    widget.controller.addListener(_syncVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      ignoring: !_isVisible,
      child: AnimatedScale(
        scale: _isVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: FloatingActionButton(
          mini: true,
          onPressed: _scrollToTop,
          tooltip: 'Kembali ke atas',
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.surface,
          shape: const CircleBorder(),
          child: const Icon(TonztoonIcons.arrowUp),
        ),
      ),
    );
  }

  void _syncVisibility() {
    if (!mounted) return;
    final isVisible =
        widget.controller.hasClients &&
        widget.controller.offset > widget.visibilityOffset;
    if (isVisible == _isVisible) return;
    setState(() => _isVisible = isVisible);
  }

  void _scrollToTop() {
    if (!widget.controller.hasClients) return;
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }
}
