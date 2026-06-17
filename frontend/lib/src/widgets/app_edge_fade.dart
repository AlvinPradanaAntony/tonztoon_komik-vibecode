import 'package:flutter/material.dart';

/// Which edge of a [Stack] the fade is anchored to.
enum AppFadeEdge { top, bottom }

/// A non-interactive gradient that fades a solid [background] colour into
/// transparency along a [Stack] edge — used to soften where scrolling content
/// meets a fixed app bar or bottom bar.
///
/// Renders a [Positioned] child, so it must live inside a [Stack]. The gradient
/// is solid at the anchored edge and transparent at the inner edge (reversed
/// for [AppFadeEdge.top]).
class AppEdgeFade extends StatelessWidget {
  const AppEdgeFade({
    super.key,
    required this.background,
    this.edge = AppFadeEdge.bottom,
    this.height = 96,
    this.midStop = 0.62,
    this.midAlpha = 0.88,
    this.opacity = 1.0,
    this.opacityDuration,
    this.opacityCurve = Curves.easeOutCubic,
  });

  /// Solid colour the content fades into (usually the scaffold background).
  final Color background;

  /// Edge the solid end is anchored to.
  final AppFadeEdge edge;

  /// Height of the fade band in logical pixels.
  final double height;

  /// Position (0..1) of the middle gradient stop.
  final double midStop;

  /// Opacity of [background] at the middle stop.
  final double midAlpha;

  /// Overall opacity of the fade (0..1). Use to show/hide it conditionally.
  final double opacity;

  /// When set, opacity changes animate over this duration (via
  /// [AnimatedOpacity]); otherwise the opacity is applied instantly.
  final Duration? opacityDuration;

  /// Curve for the opacity animation when [opacityDuration] is set.
  final Curve opacityCurve;

  @override
  Widget build(BuildContext context) {
    final solid = background;
    final mid = background.withValues(alpha: midAlpha);
    final clear = background.withValues(alpha: 0.0);
    final isBottom = edge == AppFadeEdge.bottom;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, midStop, 1.0],
          colors: isBottom ? [clear, mid, solid] : [solid, mid, clear],
        ),
      ),
    );

    if (opacityDuration != null) {
      content = AnimatedOpacity(
        opacity: opacity,
        duration: opacityDuration!,
        curve: opacityCurve,
        child: content,
      );
    } else if (opacity != 1.0) {
      content = Opacity(opacity: opacity, child: content);
    }

    return Positioned(
      left: 0,
      right: 0,
      top: isBottom ? null : 0,
      bottom: isBottom ? 0 : null,
      height: height,
      child: IgnorePointer(child: content),
    );
  }
}
