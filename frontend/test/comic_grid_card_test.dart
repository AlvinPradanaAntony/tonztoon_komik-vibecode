import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/widgets/comic_card.dart';

void main() {
  testWidgets('grid card overlays latest chapter and shows total views', (
    tester,
  ) async {
    var tapped = false;
    const comic = ComicSummary(
      title: 'Grid Comic',
      sourceName: 'komiku',
      latestChapterNumber: 94,
      totalView: 12500,
      rating: 7,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicCard(comic: comic, onTap: () => tapped = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chapterBadge = find.byKey(
      const ValueKey('comic-grid-latest-chapter-badge'),
    );
    final chapterPosition = tester.widget<Positioned>(
      find.byKey(const ValueKey('comic-grid-latest-chapter-position')),
    );
    final chapterShadow = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('comic-grid-latest-chapter-shadow')),
    );

    expect(chapterBadge, findsOneWidget);
    expect(chapterPosition.bottom, 0);
    expect(chapterShadow.painter, isNotNull);
    expect(
      find.descendant(of: chapterBadge, matching: find.text('Chapter 94')),
      findsOneWidget,
    );
    expect(find.text('13K'), findsOneWidget);
    expect(find.text('7.0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ComicCard));
    expect(tapped, isTrue);
  });
}
