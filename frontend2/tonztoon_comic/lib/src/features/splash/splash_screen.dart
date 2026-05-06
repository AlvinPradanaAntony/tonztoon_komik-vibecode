import 'package:flutter/material.dart';
import '../../core/app_assets.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.08;
  String _status = 'STARTING';

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final start = DateTime.now();
    await precacheImage(const AssetImage(AppAssets.logoAppSplash), context);
    _setProgress(0.22, 'LOADING ASSETS');

    // Simulate backend/storage initialization for UI purposes
    await Future.delayed(const Duration(milliseconds: 400));
    _setProgress(0.48, 'RESTORING SESSION');

    await Future.delayed(const Duration(milliseconds: 400));
    _setProgress(0.62, 'SYNCING LIBRARY');

    await Future.delayed(const Duration(milliseconds: 600));
    _setProgress(1, 'READY');

    final elapsed = DateTime.now().difference(start);
    final remaining = const Duration(milliseconds: 2000) - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;

    // Navigate to OnboardingScreen after splash screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  void _setProgress(double progress, String status) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Menggunakan palet yang diatur di app_theme.dart
    final background =
        theme.scaffoldBackgroundColor; // Latar belakang utama aplikasi
    final titleColor = colorScheme.primary; // Orange
    final subtitleColor =
        theme.textTheme.bodySmall?.color ?? Colors.grey; // Muted text (Slate)
    final trackColor = colorScheme.outline.withValues(
      alpha: 0.3,
    ); // Warna track progress bar

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          child: Column(
            children: [
              const Spacer(flex: 9),
              Image.asset(
                AppAssets.logoAppSplash,
                width: 118,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 18),
              Text(
                'TonzToon',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: titleColor,
                  fontSize: 24,
                  fontFamily: 'GROBOLD',
                  fontStyle: FontStyle.normal,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Multisource, all in one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: subtitleColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(flex: 11),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: subtitleColor.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.6,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  color: colorScheme.tertiary, // Yellow
                  backgroundColor: trackColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
