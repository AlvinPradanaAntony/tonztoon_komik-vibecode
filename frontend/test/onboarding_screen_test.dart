import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/core/app_theme.dart';
import 'package:tonztoon/src/features/onboarding/onboarding_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'onboarding adapts to ${brightness.name} theme without overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: TonztoonTheme.light(),
              darkTheme: TonztoonTheme.dark(),
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: const OnboardingScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Multi\nSource'), findsOneWidget);
        expect(find.text('Berikutnya'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Berikutnya'));
        await tester.pumpAndSettle();
        expect(find.text('Pustaka\nPintar'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Berikutnya'));
        await tester.pumpAndSettle();
        expect(find.text('Download\nOffline'), findsOneWidget);
        expect(find.text('Mulai'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
