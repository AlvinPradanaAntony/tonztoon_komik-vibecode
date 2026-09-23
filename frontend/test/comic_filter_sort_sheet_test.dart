import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/widgets/comic_filter_sort_sheet.dart';

void main() {
  testWidgets('ComicFilterSortSheet renders dynamic source options', (
    tester,
  ) async {
    ComicFilterSortState? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showComicFilterSortSheet(
                  context: context,
                  initialState: const ComicFilterSortState(),
                  sourceOptions: const ['Sumber Alpha', 'Sumber Beta'],
                  showGenre: false,
                  showType: false,
                  showStatus: false,
                );
              },
              child: const Text('Buka Filter'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka Filter'));
    await tester.pumpAndSettle();

    // Verify dynamic sources and 'Semua' exist
    expect(find.text('Semua'), findsWidgets);
    expect(find.text('Sumber Alpha'), findsOneWidget);
    expect(find.text('Sumber Beta'), findsOneWidget);

    // Select dynamic source
    await tester.tap(find.text('Sumber Alpha'));
    await tester.pumpAndSettle();

    // Apply filter
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(result?.source, 'Sumber Alpha');
  });

  testWidgets('ComicFilterSortSheet resolves sourceOptionsFuture asynchronously', (
    tester,
  ) async {
    final completer = Completer<List<String>>();
    ComicFilterSortState? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showComicFilterSortSheet(
                  context: context,
                  initialState: const ComicFilterSortState(),
                  sourceOptionsFuture: completer.future,
                  showGenre: false,
                  showType: false,
                  showStatus: false,
                );
              },
              child: const Text('Buka Filter Asinkron'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka Filter Asinkron'));
    await tester.pump();

    // Not yet completed
    expect(find.text('Sumber Asinkron'), findsNothing);

    // Complete the future
    completer.complete(['Sumber Asinkron']);
    await tester.pumpAndSettle();

    expect(find.text('Sumber Asinkron'), findsOneWidget);

    await tester.tap(find.text('Sumber Asinkron'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(result?.source, 'Sumber Asinkron');
  });
}
