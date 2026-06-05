import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
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
      leadingTitle: 'Multi',
      accentTitle: 'Source',
      subtitle:
          'Jelajahi lebih banyak komik dari berbagai sumber. Saat satu sumber '
          'bermasalah, pindah ke alternatif lain tanpa kehilangan cerita.',
      accent: Color(0xFFFF8A00),
      image: AppAssets.onboarding1,
      imageScale: 1.15,
      imageTopOffset: 22,
      artworkHeightFactor: 0.75,
    ),
    _OnboardingSlideData(
      leadingTitle: 'Pustaka',
      accentTitle: 'Pintar',
      subtitle:
          'Simpan riwayat bacaan, susun koleksi favorit, dan lanjutkan setiap '
          'cerita dengan mudah dari satu pustaka yang selalu rapi.',
      accent: Color(0xFFFFC400),
      image: AppAssets.onboarding2,
      imageAlignment: Alignment.topCenter,
      fullBleedArtwork: true,
    ),
    _OnboardingSlideData(
      leadingTitle: 'Download',
      accentTitle: 'Offline',
      subtitle:
          'Unduh komik favorit dan nikmati setiap chapter kapan pun, di mana '
          'pun. Tetap membaca dengan nyaman meski tanpa koneksi internet.',
      accent: Color(0xFF2478FF),
      image: AppAssets.onboarding3,
      imageAlignment: Alignment.topCenter,
      fullBleedArtwork: true,
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
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final accent = _slides[_index].accent;
    final isDark = theme.brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: background,
        extendBody: true,
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            color: background,
            gradient: RadialGradient(
              center: const Alignment(0, -0.62),
              radius: 0.92,
              colors: [
                accent.withValues(alpha: isDark ? 0.09 : 0.055),
                background.withValues(alpha: 0),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                bottom: MediaQuery.paddingOf(context).bottom + 70,
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemCount: _slides.length,
                  itemBuilder: (context, index) => _OnboardingSlide(
                    controller: _controller,
                    index: index,
                    data: _slides[index],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _BottomControls(
                    count: _slides.length,
                    index: _index,
                    accent: accent,
                    onSkip: _complete,
                    onPrimaryAction: _handlePrimaryAction,
                  ),
                ),
              ),
            ],
          ),
        ),
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
      duration: const Duration(milliseconds: 420),
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
    required this.leadingTitle,
    required this.accentTitle,
    required this.subtitle,
    required this.accent,
    required this.image,
    this.imageScale = 1,
    this.imageAlignment = Alignment.center,
    this.imageTopOffset = 0,
    this.artworkHeightFactor,
    this.fullBleedArtwork = false,
  });

  final String leadingTitle;
  final String accentTitle;
  final String subtitle;
  final Color accent;
  final String image;
  final double imageScale;
  final Alignment imageAlignment;
  final double imageTopOffset;
  final double? artworkHeightFactor;
  final bool fullBleedArtwork;
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.controller,
    required this.index,
    required this.data,
  });

  final PageController controller;
  final int index;
  final _OnboardingSlideData data;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final page = controller.hasClients
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        final distance = (page - index).abs().clamp(0.0, 1.0);
        final progress = Curves.easeOutBack.transform(1 - distance);
        final opacity = Curves.easeOut.transform(1 - distance);
        final scale = progress.clamp(0.20, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 610;

          if (data.fullBleedArtwork) {
            return _FullBleedSlide(
              data: data,
              compact: compact,
              constraints: constraints,
            );
          }

          final imageHeight = math.max(
            compact ? 300.0 : 350.0,
            constraints.maxHeight *
                (data.artworkHeightFactor ?? (compact ? 0.61 : 0.66)),
          );
          final maxImageHeight = math.max(
            0.0,
            constraints.maxHeight - (compact ? 142 : 158),
          );

          return Column(
            children: [
              SizedBox(
                height: math.min(imageHeight, maxImageHeight),
                child: _FadedArtwork(data: data),
              ),
              Expanded(
                child: _SlideContent(data: data, compact: compact),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FullBleedSlide extends StatelessWidget {
  const _FullBleedSlide({
    required this.data,
    required this.compact,
    required this.constraints,
  });

  final _OnboardingSlideData data;
  final bool compact;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final artworkHeight = constraints.maxWidth * (1672 / 941) * data.imageScale;
    final contentTop = math.min(
      constraints.maxHeight - (compact ? 132 : 148),
      artworkHeight * (compact ? 0.76 : 0.79),
    );

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: artworkHeight,
          child: Image.asset(
            data.image,
            fit: BoxFit.fill,
            alignment: data.imageAlignment,
            filterQuality: FilterQuality.high,
          ),
        ),
        Positioned(
          top: math.max(0, contentTop),
          left: 0,
          right: 0,
          child: _SlideContent(data: data, compact: compact),
        ),
      ],
    );
  }
}

class _FadedArtwork extends StatelessWidget {
  const _FadedArtwork({required this.data});

  final _OnboardingSlideData data;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.68,
                colors: [
                  data.accent.withValues(alpha: 0.13),
                  data.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0, 0.035, 0.82, 1],
          ).createShader(bounds),
          child: Transform.translate(
            offset: Offset(0, data.imageTopOffset),
            child: Transform.scale(
              scale: data.imageScale,
              alignment: data.imageAlignment,
              child: Image.asset(
                data.image,
                fit: BoxFit.contain,
                alignment: data.imageAlignment,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 82,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: 0),
                  background.withValues(alpha: 0.9),
                  background,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.data, required this.compact});

  final _OnboardingSlideData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 0 : 4, 24, 8),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform(
              alignment: Alignment.bottomLeft,
              transform: Matrix4.rotationZ(-0.20),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${data.leadingTitle}\n'),
                    TextSpan(
                      text: data.accentTitle,
                      style: TextStyle(color: data.accent),
                    ),
                  ],
                ),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontFamily: 'Suffer Through',
                  fontSize: compact ? 35 : 55,
                  height: 0.88,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.skewX(-0.025),
              child: Text(
                data.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: compact ? 12.5 : 13.5,
                  height: 1.38,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.count,
    required this.index,
    required this.accent,
    required this.onSkip,
    required this.onPrimaryAction,
  });

  final int count;
  final int index;
  final Color accent;
  final VoidCallback onSkip;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = index == count - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Lewati'),
              ),
            ),
            _PageDots(
              count: count,
              index: index,
              activeColor: accent,
              inactiveColor: colorScheme.outlineVariant,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: FilledButton(
                  key: ValueKey(isLast),
                  onPressed: onPrimaryAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    backgroundColor: accent,
                    foregroundColor: accent.computeLuminance() > 0.55
                        ? const Color(0xFF111827)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(isLast ? 'Mulai' : 'Berikutnya'),
                ),
              ),
            ),
          ],
        ),
      ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}
