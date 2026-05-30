import 'package:flutter/material.dart';

class SectionLoadMoreFooter extends StatelessWidget {
  const SectionLoadMoreFooter({
    super.key,
    required this.hasNextPage,
    required this.loadedCount,
    this.completeLabel = 'Semua item sudah dimuat',
  });

  final bool hasNextPage;
  final int loadedCount;
  final String completeLabel;

  @override
  Widget build(BuildContext context) {
    if (hasNextPage || loadedCount == 0) {
      return const SizedBox(height: 20);
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        completeLabel,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class BottomViewportFade extends StatelessWidget {
  const BottomViewportFade({super.key, required this.background});

  final Color background;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 96,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.62, 1.0],
              colors: [
                background.withValues(alpha: 0.0),
                background.withValues(alpha: 0.88),
                background,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
