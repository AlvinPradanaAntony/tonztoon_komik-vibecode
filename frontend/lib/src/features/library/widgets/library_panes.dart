part of '../library_screen.dart';

// The generic async-pane scaffolding lives in library_async_pane.dart so it
// can be shared with library_shared_panes.dart. These aliases keep the local
// (library-flavoured) call sites terse.
typedef _AsyncPane<T> = AsyncPane<T>;
typedef _LibraryList = LibraryList;
typedef _ErrorPane = LibraryErrorPane;

class _BookmarkLoadingPane extends StatelessWidget {
  const _BookmarkLoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: AppShimmer(
              child: AppShimmerBlock(width: double.infinity, height: 172),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HistoryLoadingPane extends StatelessWidget {
  const _HistoryLoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
              SizedBox(height: 12),
              _BookmarkTileShimmer(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _BookmarkErrorPane extends StatelessWidget {
  const _BookmarkErrorPane({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorPane(error: error, onRetry: onRetry),
        ),
      ],
    );
  }
}

class _BookmarkTileShimmer extends StatelessWidget {
  const _BookmarkTileShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: const AppShimmer(
        child: Row(
          children: [
            AppShimmerBlock(width: 72, height: 108, borderRadius: 15),
            SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppShimmerBlock(width: double.infinity, height: 18),
                    SizedBox(height: 8),
                    AppShimmerBlock(width: 150, height: 14),
                  ],
                ),
              ),
            ),
            SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
