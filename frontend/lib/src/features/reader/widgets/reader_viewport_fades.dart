part of '../reader_screen.dart';

class _ReaderTopViewportFade extends StatelessWidget {
  const _ReaderTopViewportFade();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 180 + MediaQuery.paddingOf(context).top,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: List.generate(9, (index) {
                final p = index / 8;
                return Colors.black.withValues(
                  alpha: math.pow(1 - p, 1.5).toDouble(),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomViewportFade extends StatelessWidget {
  const _ReaderBottomViewportFade();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 220,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: List.generate(9, (index) {
                final p = index / 8;
                return Colors.black.withValues(
                  alpha: math.pow(p, 1.5).toDouble(),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
