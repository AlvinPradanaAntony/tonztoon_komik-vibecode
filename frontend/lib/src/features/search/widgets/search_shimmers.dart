part of '../search_screen.dart';

class _SearchLoadingPlaceholder extends StatelessWidget {
  const _SearchLoadingPlaceholder({super.key, required this.gridView});

  final bool gridView;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SearchLoadingHeader(),
        const SizedBox(height: 12),
        gridView ? const _SearchGridShimmer() : const _SearchListShimmer(),
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
    return Column(
      children: [
        for (var index = 0; index < 4; index++) ...[
          const _SearchResultTileShimmer(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SearchGridShimmer extends StatelessWidget {
  const _SearchGridShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.47,
      ),
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
