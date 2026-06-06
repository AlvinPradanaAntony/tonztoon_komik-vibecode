import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/widgets/comic_card.dart';

void main() {
  testWidgets('comic list card renders shared metadata and handles taps', (
    tester,
  ) async {
    var tapped = false;
    final comic = ComicSummary(
      title: 'The Shared Comic Card',
      sourceName: 'komiku',
      type: 'Manhwa',
      status: 'Ongoing',
      rating: 8,
      latestChapterNumber: 61,
      latestChapterReleaseDate: DateTime.now().subtract(
        const Duration(hours: 8),
      ),
      genres: const [
        Genre(id: 1, name: 'Action', slug: 'action'),
        Genre(id: 2, name: 'Fantasy', slug: 'fantasy'),
        Genre(id: 3, name: 'Romance', slug: 'romance'),
        Genre(id: 4, name: 'Adventure', slug: 'adventure'),
        Genre(id: 5, name: 'Supernatural', slug: 'supernatural'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ComicListCard(comic: comic, onTap: () => tapped = true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('The Shared Comic Card'), findsOneWidget);
    expect(find.text('Komiku'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Chapter 61'), findsOneWidget);
    expect(find.text('8.0'), findsOneWidget);
    expect(find.byType(ComicTypeFlagBadge), findsOneWidget);

    final genreList = tester.widget<ListView>(
      find.descendant(
        of: find.byType(ComicListCard),
        matching: find.byType(ListView),
      ),
    );
    expect(genreList.scrollDirection, Axis.horizontal);

    final fadeFinder = find.descendant(
      of: find.byType(ComicListCard),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(fadeFinder).opacity, 1);

    await tester.drag(
      find.descendant(
        of: find.byType(ComicListCard),
        matching: find.byType(ListView),
      ),
      const Offset(-1000, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(fadeFinder).opacity, 0);

    await tester.tap(find.byType(ComicListCard));
    expect(tapped, isTrue);
  });
}
