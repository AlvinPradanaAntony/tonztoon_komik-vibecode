import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';

class AnimatedNotificationBell extends StatefulWidget {
  const AnimatedNotificationBell({super.key, required this.active});

  final bool active;

  @override
  State<AnimatedNotificationBell> createState() =>
      _AnimatedNotificationBellState();
}

class _AnimatedNotificationBellState extends State<AnimatedNotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _angle = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -0.18), weight: 8),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.18, end: 0.16),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.16, end: -0.10),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.10, end: 0.07),
        weight: 8,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 0.07, end: 0), weight: 8),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 34),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant AnimatedNotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncAnimation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    final animationsDisabled =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldAnimate = widget.active && !animationsDisabled;
    if (shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
      return;
    }

    _controller
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      child: const Icon(TonztoonIcons.bell),
      builder: (context, child) {
        return Transform.rotate(
          angle: _angle.value,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
    );
  }
}
