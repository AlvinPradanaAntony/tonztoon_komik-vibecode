import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'helpers/app_responsive.dart';
import 'repositories/providers.dart';
import 'routing/app_router.dart';

class TonztoonApp extends ConsumerStatefulWidget {
  const TonztoonApp({super.key});

  @override
  ConsumerState<TonztoonApp> createState() => _TonztoonAppState();
}

class _TonztoonAppState extends ConsumerState<TonztoonApp> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(downloadNotificationServiceProvider).initialize());
    unawaited(ref.read(pushNotificationLifecycleServiceProvider).initialize());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'TonzToon',
      theme: TonztoonTheme.light(),
      darkTheme: TonztoonTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) =>
          AppResponsive(child: child ?? const SizedBox.shrink()),
    );
  }
}
