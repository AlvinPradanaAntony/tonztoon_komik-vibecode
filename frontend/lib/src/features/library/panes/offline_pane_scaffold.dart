part of '../library_shared_panes.dart';

// Offline-flavoured pane wrappers over the shared scaffolding in
// library_async_pane.dart. They bake in the offline copy strings; the layout
// and behaviour are identical to the Pustaka tabs.
const _offlineErrorFallback = 'Gagal memuat data offline. Silakan coba lagi.';
const _offlineRefreshLog = 'Refresh offline data failed';
const _offlineRefreshFailure =
    'Gagal memperbarui data offline. Silakan coba lagi.';

class _AsyncPane<T> extends StatelessWidget {
  const _AsyncPane({
    required this.value,
    required this.builder,
    required this.onRefresh,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AsyncPane<T>(
      value: value,
      builder: builder,
      onRefresh: onRefresh,
      onRetry: onRetry,
      errorFallbackMessage: _offlineErrorFallback,
      refreshLogContext: _offlineRefreshLog,
      refreshFailureMessage: _offlineRefreshFailure,
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 132),
    this.onRefresh = noopRefresh,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LibraryList(
      padding: padding,
      onRefresh: onRefresh,
      refreshLogContext: _offlineRefreshLog,
      refreshFailureMessage: _offlineRefreshFailure,
      children: children,
    );
  }
}

typedef _LoadingPane = LoadingPane;
typedef _EmptyState = LibraryEmptyState;

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LibraryErrorPane(
      error: error,
      onRetry: onRetry,
      fallbackMessage: _offlineErrorFallback,
    );
  }
}

// Shared library section header lives in widgets/library_async_pane.dart.
typedef _SectionHeader = LibrarySectionHeader;

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}
