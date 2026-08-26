import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/features/home/widgets/continue_reading_progress_card.dart';
import 'package:tonztoon/src/models/progress.dart';

void main() {
  testWidgets('continue reading card scales dense content on narrow screens', (
    tester,
  ) async {
    final progress = ReadingProgress(
      sourceName: 'komiku_asia',
      comicSlug: 'very-long-comic-slug',
      comicTitle:
          'A very long comic title that needs to stay compact on narrow devices',
      chapterNumber: 123.5,
      lastReadAt: DateTime(2026, 1, 1),
      totalPageItems: 80,
      lastReadPageItemIndex: 79,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(220, 400),
          textScaler: TextScaler.linear(1.8),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: ContinueReadingProgressCard(
              progress: progress,
              fullWidth: true,
              showTrailingArrow: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('continue-reading-content-scale')),
      findsOneWidget,
    );
  });
}
