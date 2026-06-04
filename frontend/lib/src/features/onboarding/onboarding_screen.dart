import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/app_icons.dart';
import '../../repositories/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _controller;
  int _index = 0;

  static const _slides = [
    _OnboardingSlideData(
      title: 'Katalog Tanpa Batas',
      subtitle:
          'Jelajahi ribuan Manga, Manhwa, dan Manhua dari berbagai genre dalam genggamanmu.',
      accent: Color(0xFFFF9D00), // Primary Orange
      image: AppAssets.onboarding1,
    ),
    _OnboardingSlideData(
      title: 'Pustaka Pintar',
      subtitle:
          'Simpan riwayat bacaan, kelola koleksi favorit, dan pantau update chapter terbaru dengan mudah.',
      accent: Color(0xFF3A86FF), // Secondary Blue
      image: AppAssets.onboarding2,
    ),
    _OnboardingSlideData(
      title: 'Multisource Engine',
      subtitle:
          'Server down? Tidak masalah. Ganti sumber (source) bacaan dengan mulus tanpa perlu berpindah aplikasi.',
      accent: Color(0xFFFFD60A), // Tertiary Yellow
      image: AppAssets.onboarding3,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Fullscreen PageView
          PageView.builder(
            controller: _controller,
            onPageChanged: (value) => setState(() => _index = value),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              return _OnboardingFullscreenSlide(data: _slides[index]);
            },
          ),

          // 2. Top Bar (Skip button & Logo) - SafeArea
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: _TopBar(
                  isLast: _index == _slides.length - 1,
                  onSkip: _complete,
                ),
              ),
            ),
          ),

          // 3. Bottom controls (Dots & Button)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PageDots(
                      count: _slides.length,
                      index: _index,
                      activeColor: _slides[_index].accent,
                      inactiveColor: Colors.white24,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 56, // Menyesuaikan tinggi
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _slides[_index].accent,
                          // Menentukan warna foreground berdasarkan keterangan background (luminance) agar kontras dinamis
                          foregroundColor:
                              _slides[_index].accent.computeLuminance() > 0.5
                              ? Colors.black87
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: _handlePrimaryAction,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                _index == _slides.length - 1
                                    ? 'Get Started'
                                    : 'Next',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (_index != _slides.length - 1)
                              const Positioned(
                                right:
                                    0, // Icon diposisikan absolute di sebelah kanan agar tidak mendorong teks ke kiri
                                child: Icon(TonztoonIcons.chevronRight),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePrimaryAction() {
    if (_index == _slides.length - 1) {
      _complete();
      return;
    }
    _controller.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _complete() async {
    await ref
        .read(localStoreProvider)
        .settings
        .put('onboarding_completed', true);
    if (mounted) context.go('/');
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.image,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final String image;
}

class _OnboardingFullscreenSlide extends StatelessWidget {
  final _OnboardingSlideData data;
  const _OnboardingFullscreenSlide({required this.data});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fullscreen Image
        Image.asset(data.image, fit: BoxFit.cover),
        // Smooth Gradient Fade to Black
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 0.1),
                Colors.black.withValues(alpha: 0.6),
                Colors.black.withValues(alpha: 0.95),
                Colors.black,
              ],
              stops: const [0.0, 0.4, 0.65, 0.85, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 148, // Space for dots and button, calculated responsively
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isLast, required this.onSkip});

  final bool isLast;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(AppAssets.logoAppSplash, width: 36, height: 36),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: isLast ? 0 : 1,
          child: TextButton(
            onPressed: isLast ? null : onSkip,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int count;
  final int index;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}
