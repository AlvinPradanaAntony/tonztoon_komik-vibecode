import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../helpers/app_snackbar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_error_state.dart';
import '../../../widgets/app_loading_placeholder.dart';

/// Shared building blocks for the pull-to-refresh "pane" layout used by both
/// the Pustaka tabs ([library_screen]) and the offline panes
/// ([library_shared_panes]). The two screens differ only in the copy shown on
/// refresh failure / load error, so those strings are parameters with
/// library-flavoured defaults.

Future<void> noopRefresh() async {}

/// Row header for a library section: a leading accent icon, a title, and a
/// trailing label (e.g. a count). Shared by the Pustaka tabs and the offline
/// panes so both render identically.
class LibrarySectionHeader extends StatelessWidget {
  const LibrarySectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.secondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Resolves an [AsyncValue] into the standard pane: data via [builder], a
/// shimmer while loading, and a refreshable error list on failure.
class AsyncPane<T> extends StatelessWidget {
  const AsyncPane({
    super.key,
    required this.value,
    required this.builder,
    required this.onRefresh,
    required this.onRetry,
    this.errorFallbackMessage =
        'Pustaka belum dapat dimuat. Silakan coba lagi.',
    this.refreshLogContext = 'Refresh library failed',
    this.refreshFailureMessage =
        'Pustaka belum dapat dimuat ulang. Silakan coba lagi.',
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final String errorFallbackMessage;
  final String refreshLogContext;
  final String refreshFailureMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const LoadingPane(),
      error: (error, stackTrace) => LibraryList(
        onRefresh: onRefresh,
        refreshLogContext: refreshLogContext,
        refreshFailureMessage: refreshFailureMessage,
        children: [
          LibraryErrorPane(
            error: error,
            onRetry: onRetry,
            fallbackMessage: errorFallbackMessage,
          ),
        ],
      ),
    );
  }
}

/// A scrollable, pull-to-refresh column. Refresh failures surface a snackbar
/// using [refreshLogContext] / [refreshFailureMessage].
class LibraryList extends StatelessWidget {
  const LibraryList({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 132),
    this.onRefresh = noopRefresh,
    this.refreshLogContext = 'Refresh library failed',
    this.refreshFailureMessage =
        'Pustaka belum dapat dimuat ulang. Silakan coba lagi.',
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final Future<void> Function() onRefresh;
  final String refreshLogContext;
  final String refreshFailureMessage;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refreshWithSnackBar(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }

  Future<void> _refreshWithSnackBar(BuildContext context) async {
    try {
      await onRefresh();
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: refreshLogContext,
        fallbackMessage: refreshFailureMessage,
      );
    }
  }
}

/// Full-page loading shimmer for a pane.
class LoadingPane extends StatelessWidget {
  const LoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPageLoadingPlaceholder();
  }
}

/// Centred error block for a pane, wrapping the shared [AppErrorState].
class LibraryErrorPane extends StatelessWidget {
  const LibraryErrorPane({
    super.key,
    required this.error,
    required this.onRetry,
    this.fallbackMessage = 'Pustaka belum dapat dimuat. Silakan coba lagi.',
  });

  final Object error;
  final VoidCallback onRetry;
  final String fallbackMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppErrorState(
          error: error,
          fallbackMessage: fallbackMessage,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

/// Centred empty state for a pane, wrapping the shared [AppEmptyState] in the
/// library's standard padding / max-width.
class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppEmptyState(icon: icon, title: title, message: message),
        ),
      ),
    );
  }
}
