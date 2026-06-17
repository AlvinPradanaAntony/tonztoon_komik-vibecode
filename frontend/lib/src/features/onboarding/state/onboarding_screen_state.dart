part of '../onboarding_screen.dart';

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
