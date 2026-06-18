part of '../reader_screen.dart';

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppErrorState(
          message: message,
          onRetry: onRetry,
          retryLabel: 'Retry',
          iconSize: 42,
          iconColor: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
