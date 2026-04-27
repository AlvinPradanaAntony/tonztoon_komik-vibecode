import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../repositories/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final start = DateTime.now();
    await ref.read(authControllerProvider.notifier).restore();
    final elapsed = DateTime.now().difference(start);
    final remaining = const Duration(milliseconds: 900) - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;

    final onboardingDone =
        ref.read(localStoreProvider).settings.get('onboarding_completed') ==
        true;
    context.go(onboardingDone ? '/' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060708),
      body: Center(
        child: Image.asset(
          AppAssets.logoAppSplash,
          width: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
