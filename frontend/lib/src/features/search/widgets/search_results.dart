part of '../search_screen.dart';

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.query, required this.resultCount});

  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final text = query.trim().isEmpty ? 'Rekomendasi' : 'Hasil untuk "$query"';

    return Row(
      children: [
        Expanded(
          child: _SectionTitle(icon: TonztoonIcons.autoAwesome, title: text),
        ),
        Text(
          '$resultCount komik',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final comic in comics) ...[
          _SearchResultTile(comic: comic),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.comics});

  final List<_SearchComicUi> comics;

  @override
  Widget build(BuildContext context) {
    return AppColumnGrid<_SearchComicUi>(
      items: comics,
      minColumnWidth: 104,
      maxColumnCount: 6,
      itemBuilder: (context, comic) {
        return ComicCard(
          comic: comic.summary,
          source: comic.source,
          rating: comic.rating,
          width: double.infinity,
          onTap: () => _openComicDetail(context, comic.summary),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.comic});

  final _SearchComicUi comic;

  @override
  Widget build(BuildContext context) {
    return ComicListCard(
      comic: comic.summary,
      source: comic.source,
      rating: comic.ratingValue,
      onTap: () => _openComicDetail(context, comic.summary),
    );
  }
}

void _openComicDetail(BuildContext context, ComicSummary comic) =>
    openComicDetail(context, comic);
