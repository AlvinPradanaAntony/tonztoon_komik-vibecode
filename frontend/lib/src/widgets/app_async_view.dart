import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/app_error.dart';
import 'app_error_state.dart';
import 'app_loading_placeholder.dart';

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
  Object? _lastLoggedError;

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
          const AppPageLoadingPlaceholder();
    }

    return widget.value.when(
      skipLoadingOnRefresh: widget.skipLoadingOnRefresh,
      skipLoadingOnReload: widget.skipLoadingOnReload,
      skipError: widget.skipError,
      data: widget.builder,
      loading: () =>
          widget.loadingBuilder?.call(context) ??
          const AppPageLoadingPlaceholder(),
      error: (error, stackTrace) {
        _logErrorOnce(error, stackTrace);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppErrorState(
              error: error,
              fallbackMessage:
                  'Data belum dapat dimuat. Periksa koneksi lalu coba lagi.',
              onRetry: widget.onRetry != null ? _handleRetry : null,
              retryLabel: 'Retry',
            ),
          ),
        );
      },
    );
  }

  void _handleRetry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    widget.onRetry?.call();
  }

  void _logErrorOnce(Object error, StackTrace stackTrace) {
    if (identical(_lastLoggedError, error)) return;
    _lastLoggedError = error;
    logAppError(error, stackTrace, context: 'Async view failed');
  }
}
