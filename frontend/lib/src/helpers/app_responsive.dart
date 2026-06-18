import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppResponsive extends StatelessWidget {
  const AppResponsive({super.key, required this.child});

  final Widget child;

  static double compactTitleSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).shortestSide;
    return (width * 0.062).clamp(21.0, 26.0).toDouble();
  }

  static double heroHeaderHeight(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return (height * 0.47).clamp(340.0, 390.0).toDouble();
  }

  static Size detailCoverSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final availableHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : heroHeaderHeight(context);
    final width = MediaQuery.sizeOf(context).shortestSide;
    final coverHeight = math
        .min(availableHeight * 0.68, width * 0.68)
        .clamp(214.0, 268.0)
        .toDouble();
    return Size(coverHeight * 0.68, coverHeight);
  }

  static double _maxTextScaleFactor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).shortestSide;
    if (width < 360) return 1.06;
    if (width < 400) return 1.12;
    return 1.18;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScaleFactor(context),
      child: child,
    );
  }
}
