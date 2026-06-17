import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import 'comic_card.dart' show comicSourceNameLabel;

/// Visual style for a [SourceTag] pill.
enum SourceTagStyle {
  /// The comic's own source — themed with the secondary container color.
  primary,

  /// A linked/secondary source — themed with the tertiary container color and a
  /// link icon to distinguish it from the primary source.
  linked,
}

/// Rounded pill showing a comic's source name, themed by [style].
///
/// Shared between the library bookmark list and the bookmark-candidate dialog,
/// which previously kept two near-identical local badge widgets.
class SourceTag extends StatelessWidget {
  const SourceTag({
    super.key,
    required this.sourceName,
    this.style = SourceTagStyle.primary,
  });

  final String sourceName;
  final SourceTagStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLinked = style == SourceTagStyle.linked;
    final background = isLinked
        ? colors.tertiaryContainer
        : colors.secondaryContainer;
    final foreground = isLinked
        ? colors.onTertiaryContainer
        : colors.onSecondaryContainer;
    final icon = isLinked ? TonztoonIcons.link : TonztoonIcons.travelExplore;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 4),
          Text(
            comicSourceNameLabel(sourceName),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
