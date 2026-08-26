import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/models/comic.dart';
import 'package:tonztoon/src/widgets/bookmark_status_picker.dart';

void main() {
  testWidgets('bookmark status picker exposes shared status options', (
    tester,
  ) async {
    String? selectedStatus;
    final comic = ComicSummary(title: 'Shared status comic', status: 'ongoing');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedStatus = await showBookmarkStatusPicker(context, comic);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah status komik'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(find.text('Hiatus'), findsOneWidget);

    await tester.tap(find.text('Selesai'));
    await tester.pumpAndSettle();

    expect(selectedStatus, 'completed');
  });
}
