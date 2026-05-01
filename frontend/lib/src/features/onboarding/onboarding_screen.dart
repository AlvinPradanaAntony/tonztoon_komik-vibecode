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
      title: 'Massive Catalog',
      subtitle:
          'Read manga, manhwa, and manhua from every source in one place.',
      accent: Color(0xFFFFA71A),
      visual: _OnboardingVisual.catalog,
    ),
    _OnboardingSlideData(
      title: 'Smart Library',
      subtitle:
          'Continue chapters, organize collections, and keep updates close.',
      accent: Color(0xFF18B7FF),
      visual: _OnboardingVisual.library,
    ),
    _OnboardingSlideData(
      title: 'Community',
      subtitle:
          'Save favorite scenes, read offline, and keep your rhythm synced.',
      accent: Color(0xFFFFC35A),
      visual: _OnboardingVisual.community,
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
    final isDark = theme.brightness == Brightness.dark;
    final palette = _OnboardingPalette.fromBrightness(theme.brightness);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    children: [
                      _TopBar(
                        palette: palette,
                        isLast: _index == _slides.length - 1,
                        onSkip: () => _complete('/'),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          onPageChanged: (value) {
                            setState(() => _index = value);
                          },
                          itemCount: _slides.length,
                          itemBuilder: (context, index) {
                            return _OnboardingSlide(
                              data: _slides[index],
                              palette: palette,
                              isDark: isDark,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      _PageDots(
                        count: _slides.length,
                        index: _index,
                        activeColor: _slides[_index].accent,
                        inactiveColor: palette.dotInactive,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _handlePrimaryAction,
                          iconAlignment: IconAlignment.end,
                          icon: Icon(
                            _index == _slides.length - 1
                                ? TonztoonIcons.check
                                : TonztoonIcons.chevronRight,
                          ),
                          label: Text(
                            _index == _slides.length - 1
                                ? 'Get Started'
                                : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handlePrimaryAction() {
    if (_index == _slides.length - 1) {
      _complete('/');
      return;
    }
    _controller.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _complete(String location) async {
    await ref
        .read(localStoreProvider)
        .settings
        .put('onboarding_completed', true);
    if (mounted) context.go(location);
  }
}

enum _OnboardingVisual { catalog, library, community }

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.visual,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final _OnboardingVisual visual;
}

class _OnboardingPalette {
  const _OnboardingPalette({
    required this.background,
    required this.panel,
    required this.panelHigh,
    required this.text,
    required this.muted,
    required this.border,
    required this.dotInactive,
  });

  final Color background;
  final Color panel;
  final Color panelHigh;
  final Color text;
  final Color muted;
  final Color border;
  final Color dotInactive;

  factory _OnboardingPalette.fromBrightness(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const _OnboardingPalette(
        background: Color(0xFF071020),
        panel: Color(0xFF0D182A),
        panelHigh: Color(0xFF17253A),
        text: Color(0xFFEAF0FF),
        muted: Color(0xFFB4C0D2),
        border: Color(0xFF22324B),
        dotInactive: Color(0xFF2B3B55),
      );
    }
    return const _OnboardingPalette(
      background: Color(0xFFF6FAF8),
      panel: Color(0xFFFFFFFF),
      panelHigh: Color(0xFFEAF2F1),
      text: Color(0xFF172029),
      muted: Color(0xFF64747A),
      border: Color(0xFFD9E5E2),
      dotInactive: Color(0xFFD2DDDB),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.palette,
    required this.isLast,
    required this.onSkip,
  });

  final _OnboardingPalette palette;
  final bool isLast;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(AppAssets.logoAppSplash, width: 30, height: 30),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: isLast ? 0 : 1,
          child: TextButton(
            onPressed: isLast ? null : onSkip,
            child: Text(
              'Skip',
              style: TextStyle(
                color: palette.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.data,
    required this.palette,
    required this.isDark,
  });

  final _OnboardingSlideData data;
  final _OnboardingPalette palette;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 7,
          child: _SlideVisual(data: data, palette: palette, isDark: isDark),
        ),
        const SizedBox(height: 22),
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: Text(
                  data.subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlideVisual extends StatelessWidget {
  const _SlideVisual({
    required this.data,
    required this.palette,
    required this.isDark,
  });

  final _OnboardingSlideData data;
  final _OnboardingPalette palette;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: switch (data.visual) {
          _OnboardingVisual.catalog => _CatalogVisual(
            accent: data.accent,
            palette: palette,
          ),
          _OnboardingVisual.library => _LibraryVisual(
            accent: data.accent,
            palette: palette,
          ),
          _OnboardingVisual.community => _CommunityVisual(
            accent: data.accent,
            palette: palette,
          ),
        },
      ),
    );
  }
}

class _CatalogVisual extends StatelessWidget {
  const _CatalogVisual({required this.accent, required this.palette});

  final Color accent;
  final _OnboardingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        Container(
          width: 190,
          height: 276,
          decoration: BoxDecoration(
            color: palette.panelHigh,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF162947),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Image.asset(AppAssets.logoAppSplash),
                      ),
                      Positioned(
                        left: 18,
                        top: 22,
                        child: _SolidLine(width: 74, color: accent),
                      ),
                      Positioned(
                        left: 18,
                        top: 42,
                        child: _SolidLine(
                          width: 106,
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryVisual extends StatelessWidget {
  const _LibraryVisual({required this.accent, required this.palette});

  final Color accent;
  final _OnboardingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.panelHigh,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'My Library',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Icon(TonztoonIcons.search, size: 18, color: palette.text),
                const SizedBox(width: 12),
                Icon(
                  TonztoonIcons.slidersHorizontal,
                  size: 18,
                  color: palette.text,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ContinueReadingCard(accent: accent, palette: palette),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BookTile(
                    color: const Color(0xFFDA6437),
                    accent: accent,
                    label: 'New',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BookTile(
                    color: const Color(0xFF87909C),
                    accent: palette.border,
                    label: 'Saved',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityVisual extends StatelessWidget {
  const _CommunityVisual({required this.accent, required this.palette});

  final Color accent;
  final _OnboardingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 28,
          right: 24,
          child: _SpeedBlock(width: 130, height: 14, color: accent),
        ),
        Positioned(
          top: 78,
          left: 20,
          child: _SpeedBlock(width: 92, height: 10, color: palette.border),
        ),
        Positioned(
          bottom: 104,
          left: 28,
          child: _RunnerShape(color: const Color(0xFF213A5B), scale: 0.82),
        ),
        Positioned(
          bottom: 82,
          right: 38,
          child: _RunnerShape(color: const Color(0xFF0F77A8), scale: 1.08),
        ),
        Positioned(
          bottom: 22,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: palette.panelHigh,
              border: Border.all(color: palette.border),
              shape: BoxShape.circle,
            ),
            child: Icon(TonztoonIcons.messageSquare, color: accent, size: 28),
          ),
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.accent, required this.palette});

  final Color accent;
  final _OnboardingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 66,
            decoration: BoxDecoration(
              color: const Color(0xFF503C7C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(TonztoonIcons.bookMarked, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONTINUE READING',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 6),
                _SolidLine(width: 106, color: palette.text),
                const SizedBox(height: 8),
                _SolidLine(width: 82, color: palette.muted),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: 0.42,
                    minHeight: 4,
                    color: accent,
                    backgroundColor: palette.border,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.color,
    required this.accent,
    required this.label,
  });

  final Color color;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.74,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 8,
                ),
              ),
            ),
          ),
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _SolidLine extends StatelessWidget {
  const _SolidLine({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _SpeedBlock extends StatelessWidget {
  const _SpeedBlock({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.48,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _RunnerShape extends StatelessWidget {
  const _RunnerShape({required this.color, required this.scale});

  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: 80,
        height: 82,
        child: Stack(
          children: [
            Positioned(
              top: 2,
              left: 30,
              child: _Circle(size: 18, color: color),
            ),
            Positioned(
              top: 22,
              left: 27,
              child: _Pill(width: 24, height: 36, color: color),
            ),
            Positioned(
              top: 31,
              left: 4,
              child: _Pill(width: 34, height: 9, color: color),
            ),
            Positioned(
              top: 29,
              right: 3,
              child: _Pill(width: 36, height: 9, color: color),
            ),
            Positioned(
              bottom: 2,
              left: 18,
              child: _Pill(width: 12, height: 38, color: color),
            ),
            Positioned(
              bottom: 4,
              right: 15,
              child: _Pill(width: 12, height: 34, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
