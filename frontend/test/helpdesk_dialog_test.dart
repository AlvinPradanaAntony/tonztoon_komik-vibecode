import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/models/helpdesk.dart';
import 'package:tonztoon/src/widgets/helpdesk_dialog.dart';

void main() {
  Widget buildSubject() {
    return MaterialApp(
      home: Scaffold(
        body: HelpdeskDialog(
          onSubmit: (draft) async => HelpdeskSubmissionReceipt(
            id: 'submission-id',
            referenceCode: 'TT-12345678',
            category: draft.category,
            status: 'open',
            createdAt: DateTime(2026),
          ),
        ),
      ),
    );
  }

  testWidgets('shows review and report category cards', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.byKey(const ValueKey('helpdesk-review-form')), findsNothing);
    expect(find.byKey(const ValueKey('helpdesk-report-form')), findsNothing);
    expect(find.text('Pilih'), findsNothing);
    expect(find.text('Kirim'), findsNothing);
    expect(find.byTooltip('Tutup'), findsOneWidget);
  });

  testWidgets('review category displays rating and review field', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey('helpdesk-review-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('helpdesk-review-form')), findsOneWidget);
    expect(find.byKey(const ValueKey('helpdesk-rating-5')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('helpdesk-review-message')),
      findsOneWidget,
    );
  });

  testWidgets('report category validates required fields', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey('helpdesk-report-card')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kirim'));
    await tester.tap(find.text('Kirim'));
    await tester.pump();

    expect(find.text('Judul masalah wajib diisi.'), findsOneWidget);
    expect(find.text('Pesan wajib diisi.'), findsOneWidget);
  });

  testWidgets('submits a valid review to the callback', (tester) async {
    HelpdeskSubmissionDraft? submittedDraft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpdeskDialog(
            onSubmit: (draft) async {
              submittedDraft = draft;
              return HelpdeskSubmissionReceipt(
                id: 'submission-id',
                referenceCode: 'TT-12345678',
                category: draft.category,
                status: 'open',
                createdAt: DateTime(2026),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('helpdesk-review-card')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('helpdesk-review-message')),
      'Aplikasi nyaman digunakan dan koleksinya lengkap.',
    );
    await tester.ensureVisible(find.text('Kirim'));
    await tester.tap(find.text('Kirim'));
    await tester.pumpAndSettle();

    expect(submittedDraft?.category, HelpdeskCategory.review);
    expect(submittedDraft?.rating, 5);
    expect(
      submittedDraft?.message,
      'Aplikasi nyaman digunakan dan koleksinya lengkap.',
    );
  });
}
