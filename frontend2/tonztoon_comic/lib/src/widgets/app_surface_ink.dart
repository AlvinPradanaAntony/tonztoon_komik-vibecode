import 'package:flutter/material.dart';

class AppSurfaceInk extends StatelessWidget {
  const AppSurfaceInk({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);

    return Material(
      color: colorScheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: radius,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
