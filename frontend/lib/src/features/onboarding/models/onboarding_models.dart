part of '../onboarding_screen.dart';

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
