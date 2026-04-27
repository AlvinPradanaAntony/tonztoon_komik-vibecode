import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../repositories/providers.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF101318),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Image.asset(AppAssets.logoApp, width: 140),
              const SizedBox(height: 28),
              Text(
                'Read manga, manhwa, and manhua with a reader built for flow.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Browse multi-source catalogs, continue your last chapter, and sync progress when you sign in.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _complete(context, ref, '/'),
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Start Reading'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _complete(context, ref, '/auth'),
                  icon: const Icon(Icons.login),
                  label: const Text('Login / Register'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _complete(BuildContext context, WidgetRef ref, String location) {
    ref.read(localStoreProvider).settings.put('onboarding_completed', true);
    context.go(location);
  }
}
