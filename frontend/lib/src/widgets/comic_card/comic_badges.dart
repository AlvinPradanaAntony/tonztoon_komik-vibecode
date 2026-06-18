part of '../comic_card.dart';

class ComicNewBadge extends StatelessWidget {
  const ComicNewBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE11D48),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: compact ? 5 : 8,
            offset: Offset(0, compact ? 2 : 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 3 : 5,
        ),
        child: Text(
          'NEW',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 9 : null,
            letterSpacing: compact ? 0.5 : 0.7,
          ),
        ),
      ),
    );
  }
}

/// Dark overlay badge showing a comic's source, placed on top of a cover image.
///
/// The default compact style is used on grid cards. The [prominent] style — a
/// larger pill with a subtle border — is used as the hero badge on the comic
/// detail screen.
class ComicSourceBadge extends StatelessWidget {
  const ComicSourceBadge({
    super.key,
    required this.label,
    this.prominent = false,
  });

  final String label;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        (prominent ? theme.textTheme.labelMedium : theme.textTheme.labelSmall)
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        border: prominent
            ? Border.all(color: Colors.white.withValues(alpha: 0.18))
            : null,
        borderRadius: BorderRadius.circular(prominent ? 18 : 14),
      ),
      child: Padding(
        padding: prominent
            ? const EdgeInsets.symmetric(horizontal: 11, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TonztoonIcons.travelExplore,
              size: prominent ? 14 : 12,
              color: Colors.white,
            ),
            SizedBox(width: prominent ? 6 : 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComicMetaBadge extends StatelessWidget {
  const ComicMetaBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.iconColor,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColor = color ?? colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: icon == null
            ? Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: iconColor ?? badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ComicTypeFlagBadge extends StatelessWidget {
  const ComicTypeFlagBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Center(
          child: Text(
            comicTypeFlag(type),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1),
          ),
        ),
      ),
    );
  }
}

class ComicGenreBadge extends StatelessWidget {
  const ComicGenreBadge({super.key, required this.genre, this.compact = false});

  final String genre;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = DynamicBadgePalette.fromSeed(context, genre);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 8,
        ),
        child: Text(
          comicBadgeLabel(genre),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: palette.foreground,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class ComicStatusBadge extends StatelessWidget {
  const ComicStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = comicStatusStyle(theme.colorScheme, status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 13, color: style.color),
            const SizedBox(width: 5),
            Text(
              comicBadgeLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: style.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
