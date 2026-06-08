import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/features/library/library_screen.dart';
import 'package:tonztoon/src/models/library.dart';

void main() {
  testWidgets('renders grouped bookmark and candidate info correctly', (
    tester,
  ) async {
    const candidate = BookmarkLinkCandidate(
      bookmark: LibraryComicRef(
        sourceName: 'komiku_asia',
        slug: 'judul-bookmark',
        title: 'My Wife and I Dominate the Three Realms',
      ),
      comic: LibraryComicRef(
        sourceName: 'komikcast',
        slug: 'judul-kandidat',
        title: 'I Dominate The Game',
      ),
      confidence: 0.42,
    );

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showBookmarkLinkCandidatesDialog(
                  context,
                  const [candidate],
                ),
                child: const Text('Buka kandidat'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka kandidat'));
    await tester.pumpAndSettle();

    expect(find.text('Hubungkan source lain'), findsOneWidget);
    
    // Verify primary bookmarked comic title is rendered
    expect(find.text('My Wife and I Dominate the Three Realms'), findsOneWidget);
    
    // Verify candidate comic title is rendered
    expect(find.text('I Dominate The Game'), findsOneWidget);
    
    // Verify mapping and confidence is rendered in subtitle
    expect(find.text('-> Komikcast • kecocokan 42%'), findsOneWidget);

    // Verify detail buttons exist with correct tooltips
    expect(find.byTooltip('Buka detail bookmark utama'), findsOneWidget);
    expect(find.byTooltip('Buka detail kandidat bookmark'), findsOneWidget);
  });

  testWidgets('sorts candidate groups correctly (auto-checked first, then highest confidence)', (
    tester,
  ) async {
    const lowConfCandidate = BookmarkLinkCandidate(
      bookmark: LibraryComicRef(
        sourceName: 'komiku_asia',
        slug: 'low-conf-slug',
        title: 'Low Confidence Comic',
      ),
      comic: LibraryComicRef(
        sourceName: 'komikcast',
        slug: 'alternate-1',
        title: 'Alternate Low',
      ),
      confidence: 0.50, // No auto-check
    );

    const highConfCandidate = BookmarkLinkCandidate(
      bookmark: LibraryComicRef(
        sourceName: 'komiku_asia',
        slug: 'high-conf-slug',
        title: 'High Confidence Comic',
      ),
      comic: LibraryComicRef(
        sourceName: 'komikcast',
        slug: 'alternate-2',
        title: 'Alternate High',
      ),
      confidence: 0.70, // No auto-check but higher than 0.50
    );

    const autoCheckedCandidate = BookmarkLinkCandidate(
      bookmark: LibraryComicRef(
        sourceName: 'komiku_asia',
        slug: 'auto-check-slug',
        title: 'Auto Checked Comic',
      ),
      comic: LibraryComicRef(
        sourceName: 'komikcast',
        slug: 'alternate-3',
        title: 'Alternate Auto',
      ),
      confidence: 0.85, // Auto-checked because confidence >= 0.82
    );

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showBookmarkLinkCandidatesDialog(
                  context,
                  const [lowConfCandidate, highConfCandidate, autoCheckedCandidate],
                ),
                child: const Text('Buka kandidat'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka kandidat'));
    await tester.pumpAndSettle();

    expect(find.text('Hubungkan source lain'), findsOneWidget);

    // Get the Text widgets inside the ListView to verify order
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    
    final autoCheckedIndex = texts.indexOf('Auto Checked Comic');
    final highConfIndex = texts.indexOf('High Confidence Comic');
    final lowConfIndex = texts.indexOf('Low Confidence Comic');

    expect(autoCheckedIndex != -1, isTrue);
    expect(highConfIndex != -1, isTrue);
    expect(lowConfIndex != -1, isTrue);

    // Verify autoChecked is before highConf, and highConf is before lowConf
    expect(autoCheckedIndex < highConfIndex, isTrue);
    expect(highConfIndex < lowConfIndex, isTrue);
  });
}
