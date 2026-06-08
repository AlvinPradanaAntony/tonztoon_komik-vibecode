import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/core/app_icons.dart';
import 'package:tonztoon/src/core/app_theme.dart';
import 'package:tonztoon/src/widgets/tonztoon_modal_dialog.dart';

void main() {
  testWidgets('helper icon uses a toned surface in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TonztoonTheme.dark(),
        home: const Scaffold(
          body: TonztoonModalDialog(
            title: 'TonzToon sudah terbaru',
            message: 'Tidak ada versi baru.',
            helperText: 'Kamu sudah memakai rilis paling baru.',
            helperIcon: TonztoonIcons.badgeCheck,
            variant: TonztoonModalVariant.success,
            art: TonztoonModalArt.cloudSync,
            primaryLabel: 'OK',
          ),
        ),
      ),
    );

    final iconBackground = tester.widget<Container>(
      find.byKey(const ValueKey('tonztoon-modal-helper-icon-background')),
    );
    final decoration = iconBackground.decoration! as BoxDecoration;

    expect(decoration.color, isNot(Colors.white.withValues(alpha: 0.68)));
    expect(decoration.color!.computeLuminance(), lessThan(0.35));
  });

  testWidgets('primary action glow adapts to theme brightness', (tester) async {
    Future<List<BoxShadow>> pumpGlow(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: TonztoonModalDialog(
              title: 'Konfirmasi',
              message: 'Lanjutkan tindakan ini?',
              variant: TonztoonModalVariant.danger,
              art: TonztoonModalArt.closeApp,
              primaryLabel: 'Keluar',
              onPrimaryPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(
                      const ValueKey(
                        'tonztoon-modal-primary-action-decoration',
                      ),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      return decoration.boxShadow!;
    }

    final lightShadows = await pumpGlow(TonztoonTheme.light());
    final darkShadows = await pumpGlow(TonztoonTheme.dark());

    expect(lightShadows, hasLength(2));
    expect(darkShadows, hasLength(2));
    expect(lightShadows.first.blurRadius, 11);
    expect(darkShadows.first.blurRadius, 14);
    expect(lightShadows.first.offset.dy, 4);
    expect(darkShadows.first.offset.dy, 6);
    expect(darkShadows.first.color.a, greaterThan(lightShadows.first.color.a));
  });
}
