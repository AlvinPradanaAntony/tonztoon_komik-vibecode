import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'repositories/providers.dart';
import 'routing/app_router.dart';

class TonztoonApp extends ConsumerWidget {
  const TonztoonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      title: 'TonzToon Comic',
      debugShowCheckedModeBanner: false,
      theme: TonztoonTheme.light(),
      darkTheme: TonztoonTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
