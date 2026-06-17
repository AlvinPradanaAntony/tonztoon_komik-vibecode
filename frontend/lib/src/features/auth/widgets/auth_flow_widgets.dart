part of '../auth_screen.dart';

class _ResetIconBadge extends StatelessWidget {
  const _ResetIconBadge({required this.icon, required this.palette});

  final IconData icon;
  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 54,
        child: Icon(icon, color: palette.accent, size: 26),
      ),
    );
  }
}

class _ResetStep extends StatelessWidget {
  const _ResetStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _AuthPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(icon, size: 18, color: palette.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAuthMessage extends StatelessWidget {
  const _InlineAuthMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              TonztoonIcons.warning,
              color: colorScheme.onErrorContainer,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
