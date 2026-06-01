import 'package:flutter/material.dart';

import '../core/app_icons.dart';
import '../models/comic.dart';
import 'comic_cover.dart';

/// [ComicCard] adalah kartu yang membungkus [ComicCover] dan menampilkan
/// judul serta metadata (seperti tipe dan chapter terbaru).
/// Dilengkapi dengan interaksi UX: hover effect dan tekan (scale).
class ComicCard extends StatefulWidget {
  const ComicCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.source,
    this.rating,
    this.width = 138,
    this.showNewBadge = false,
  });

  final ComicSummary comic;
  final VoidCallback onTap;
  final String? source;
  final String? rating;
  final double? width;
  final bool showNewBadge;

  @override
  State<ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<ComicCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chapterNumber = widget.comic.latestChapterNumber;
    final source = widget.source ?? comicSourceLabel(widget.comic);
    final ratingLabel =
        widget.rating ?? widget.comic.rating?.toStringAsFixed(1);

    // MouseRegion untuk mendeteksi kursor mouse (berguna di Desktop/Web)
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),

      // GestureDetector untuk mendeteksi sentuhan jari (berguna di Mobile)
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),

        // Animasi memperbesar/memperkecil kartu
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.02 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,

          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.12,
              child: SizedBox(
                width: widget.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _hovered ? 0.2 : 0.12,
                            ),
                            blurRadius: _hovered ? 22 : 14,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ComicCover(
                              imageUrl: widget.comic.coverImageUrl,
                              borderRadius: 12,
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: ComicSourceBadge(label: source),
                            ),
                            if (widget.comic.type != null)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: ComicTypeFlagBadge(
                                  type: widget.comic.type!,
                                ),
                              ),
                            if (widget.showNewBadge &&
                                widget.comic.hasNewChapter())
                              const Positioned(
                                right: 8,
                                bottom: 8,
                                child: ComicNewBadge(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Flexible(
                      child: Text(
                        widget.comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (chapterNumber != null)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ComicMetaBadge(
                                label:
                                    'Chapter ${formatChapterNumber(chapterNumber)}',
                                color: colorScheme.primary,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (ratingLabel != null)
                          ComicMetaBadge(
                            label: ratingLabel,
                            icon: TonztoonIcons.starFilled,
                            iconColor: Colors.amber,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

class ComicSourceBadge extends StatelessWidget {
  const ComicSourceBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              TonztoonIcons.travelExplore,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
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
    final color = comicGenreColor(genre);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
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
            color: color,
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
        borderRadius: BorderRadius.circular(14),
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

String comicSourceLabel(ComicSummary comic) {
  return comicSourceNameLabel(comic.sourceName);
}

String comicSourceNameLabel(String sourceName) {
  final value = sourceName.trim();
  if (value.isEmpty) return 'Komiku';
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_capitalizeBadgeWord)
      .join(' ');
}

String comicTypeFlag(String? type) {
  return switch (type?.toLowerCase()) {
    'manhwa' => '🇰🇷',
    'manga' => '🇯🇵',
    'manhua' => '🇨🇳',
    _ => '🏳️',
  };
}

String comicBadgeLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_\s]+'), ' ');
  if (normalized.isEmpty) return value;
  return normalized
      .split(' ')
      .map((word) => word.split('-').map(_capitalizeBadgeWord).join('-'))
      .join(' ');
}

String _capitalizeBadgeWord(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}

Color comicGenreColor(String genre) {
  return switch (genre.toLowerCase()) {
    'action' => const Color(0xFFE11D48),
    'adventure' => const Color(0xFF2563EB),
    'fantasy' => const Color(0xFF7C3AED),
    'drama' => const Color(0xFFDB2777),
    'system' => const Color(0xFF0891B2),
    'comedy' => const Color(0xFFF59E0B),
    'shounen' => const Color(0xFFEA580C),
    'apocalypse' => const Color(0xFF475569),
    'psychological' => const Color(0xFF9333EA),
    'supernatural' => const Color(0xFF059669),
    'swordplay' => const Color(0xFFDC2626),
    'sports' => const Color(0xFF16A34A),
    'romance' => const Color(0xFFEC4899),
    _ => const Color(0xFF3A86FF),
  };
}

ComicStatusStyle comicStatusStyle(ColorScheme colorScheme, String status) {
  final normalized = status.trim().toLowerCase();
  return switch (normalized) {
    'completed' ||
    'complete' ||
    'end' ||
    'ended' ||
    'tamat' ||
    'finish' ||
    'finished' => const ComicStatusStyle(
      icon: TonztoonIcons.badgeCheckFilled,
      color: Color(0xFF16A34A),
    ),
    'hiatus' => const ComicStatusStyle(
      icon: TonztoonIcons.circleDotDashed,
      color: Color(0xFFF59E0B),
    ),
    _ => ComicStatusStyle(
      icon: TonztoonIcons.clock,
      color: colorScheme.secondary,
    ),
  };
}

class ComicStatusStyle {
  const ComicStatusStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}
