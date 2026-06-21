part of '../search_screen.dart';

class _SearchLoadingPlaceholder extends StatelessWidget {
  const _SearchLoadingPlaceholder({
    super.key,
    required this.gridView,
    required this.controller,
    required this.listTopPadding,
  });

  final bool gridView;
  final ScrollController controller;
  final double listTopPadding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: listTopPadding)),
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _SearchLoadingHeader(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: gridView ? const _SearchGridShimmer() : const _SearchListShimmer(),
        ),
      ],
    );
  }
}

class _SearchLoadingHeader extends StatelessWidget {
  const _SearchLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionTitle(
            icon: TonztoonIcons.autoAwesome,
            title: 'Mencari...',
          ),
        ),
      ],
    );
  }
}

class _SearchListShimmer extends StatelessWidget {
  const _SearchListShimmer();

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index.isOdd) return const SizedBox(height: 12);
          return const _SearchResultTileShimmer();
        },
        childCount: 7, // 4 items + 3 spacers
      ),
    );
  }
}

class _SearchGridShimmer extends StatelessWidget {
  const _SearchGridShimmer();

  @override
  Widget build(BuildContext context) {
    return AppSliverColumnGrid<int>(
      items: const [0, 1, 2, 3],
      minColumnWidth: 104,
      maxColumnCount: 6,
      itemBuilder: (context, index) => const _SearchGridCardShimmer(),
    );
  }
}

class _SearchResultTileShimmer extends StatelessWidget {
  const _SearchResultTileShimmer();

  @override
  Widget build(BuildContext context) {
    return const ComicListCardShimmer();
  }
}

class _SearchGridCardShimmer extends StatelessWidget {
  const _SearchGridCardShimmer();

  @override
  Widget build(BuildContext context) {
    return const ComicGridCardShimmer();
  }
}
