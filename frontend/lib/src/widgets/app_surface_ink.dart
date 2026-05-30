import 'package:flutter/material.dart';

class AppSurfaceInk extends StatelessWidget {
  const AppSurfaceInk({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(10),
    this.showBorder = true,
    this.boxShadow,
    this.elevation = 0,
    this.shadowColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showBorder;
  final List<BoxShadow>? boxShadow;
  final double elevation;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: boxShadow),
      child: Material(
        color: colorScheme.surface,
        elevation: elevation,
        shadowColor: shadowColor,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: showBorder
                  ? Border.all(color: colorScheme.outlineVariant)
                  : null,
              borderRadius: radius,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
