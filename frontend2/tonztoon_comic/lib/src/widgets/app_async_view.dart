import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppAsyncView<T> extends StatefulWidget {
  const AppAsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingBuilder,
    this.skipLoadingOnRefresh = false,
    this.skipLoadingOnReload = false,
    this.skipError = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final WidgetBuilder? loadingBuilder;
  final bool skipLoadingOnRefresh;
  final bool skipLoadingOnReload;
  final bool skipError;

  @override
  State<AppAsyncView<T>> createState() => _AppAsyncViewState<T>();
}

class _AppAsyncViewState<T> extends State<AppAsyncView<T>> {
  bool _retrying = false;

  @override
  void didUpdateWidget(covariant AppAsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_retrying &&
        oldWidget.value != widget.value &&
        !widget.value.isLoading) {
      _retrying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_retrying) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    return widget.value.when(
      skipLoadingOnRefresh: widget.skipLoadingOnRefresh,
      skipLoadingOnReload: widget.skipLoadingOnReload,
      skipError: widget.skipError,
      data: widget.builder,
      loading: () =>
          widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40),
              const SizedBox(height: 12),
              Text(error.toString(), textAlign: TextAlign.center),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _handleRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleRetry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    widget.onRetry?.call();
  }
}
