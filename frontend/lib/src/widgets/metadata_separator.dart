import 'package:flutter/material.dart';

class MetadataSeparator extends StatelessWidget {
  const MetadataSeparator({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 2),
    this.style,
    this.color,
  });

  final EdgeInsetsGeometry padding;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: padding,
      child: Center(
        child: Text(
          '|',
          style:
              style ??
              theme.textTheme.labelSmall?.copyWith(
                color: resolvedColor,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}
