import 'package:flutter/material.dart';

import '../models/comic.dart';
import 'comic_cover.dart';

class ComicCard extends StatefulWidget {
  const ComicCard({super.key, required this.comic, required this.onTap});

  final ComicSummary comic;
  final VoidCallback onTap;

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
    final meta = [
      if (widget.comic.type != null) widget.comic.type!,
      if (widget.comic.latestChapterNumber != null)
        'Ch ${formatChapterNumber(widget.comic.latestChapterNumber!)}',
    ].join(' • ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.025 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: SizedBox(
              width: 138,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
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
                    child: ComicCover(
                      imageUrl: widget.comic.coverImageUrl,
                      width: 138,
                      height: 192,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
