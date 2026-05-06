import 'package:flutter_test/flutter_test.dart';

import 'package:tonztoon_comic/main.dart';

void main() {
  testWidgets('shows the splash screen on launch', (tester) async {
    await tester.pumpWidget(const TonztoonApp());

    expect(find.text('TonzToon'), findsOneWidget);
    expect(find.text('Multisource, all in one.'), findsOneWidget);
    expect(find.text('STARTING'), findsOneWidget);
  });
}
