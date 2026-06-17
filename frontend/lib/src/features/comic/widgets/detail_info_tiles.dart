part of '../comic_detail_screen.dart';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _CreatorTile extends StatelessWidget {
  const _CreatorTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.secondary, size: 19),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, this.accent});

  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accent ?? colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              comicBadgeLabel(label),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusInfoPill extends StatelessWidget {
  const _StatusInfoPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final style = comicStatusStyle(Theme.of(context).colorScheme, status);
    return _InfoPill(icon: style.icon, label: status, accent: style.color);
  }
}

class _TypeInfoPill extends StatelessWidget {
  const _TypeInfoPill({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              comicTypeFlag(type),
              style: const TextStyle(fontSize: 15, height: 1),
            ),
            const SizedBox(width: 6),
            Text(
              comicBadgeLabel(type),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
