import 'package:flutter/material.dart';

import '../models/comic.dart';
import 'comic_cover.dart';

class ComicCard extends StatelessWidget {
  const ComicCard({super.key, required this.comic, required this.onTap});

  final ComicSummary comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComicCover(imageUrl: comic.coverImageUrl, width: 132, height: 184),
            const SizedBox(height: 8),
            Text(
              comic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (comic.type != null) comic.type!,
                if (comic.latestChapterNumber != null)
                  'Ch ${formatChapterNumber(comic.latestChapterNumber!)}',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
