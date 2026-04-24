import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon_komik/src/features/placeholder/placeholder_screen.dart';

void main() {
  testWidgets('placeholder shell renders title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlaceholderScreen(title: 'Library', message: 'Coming next.'),
      ),
    );

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Coming next.'), findsOneWidget);
  });
}
