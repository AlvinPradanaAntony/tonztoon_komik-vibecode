import 'package:flutter/material.dart';

/// Reusable empty-state block: a circular icon bubble, a title, and a
/// supporting message, with an optional action below.
///
/// Renders an intrinsically-sized [Column] so callers stay in control of the
/// outer layout (wrap it in [Center], [Padding], or a sliver as needed).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.iconSize = 38,
    this.maxWidth = 320,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final double iconSize;
  final double maxWidth;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(icon, size: iconSize, color: colorScheme.secondary),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.38,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    );
  }
}
