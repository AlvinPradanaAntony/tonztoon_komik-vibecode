part of '../comic_detail_screen.dart';

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.detail,
    required this.status,
    this.onStatusTap,
    this.isStatusLoading = false,
  });

  final _ComicDetailUi detail;
  final String status;
  final VoidCallback? onStatusTap;
  final bool isStatusLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              detail.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: AppResponsive.compactTitleSize(context),
                height: 1.12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TypeInfoPill(type: detail.type),
              _StatusInfoPill(
                status: status,
                onTap: isStatusLoading ? null : onStatusTap,
                isLoading: isStatusLoading,
              ),
              _InfoPill(
                icon: TonztoonIcons.starFilled,
                label: detail.rating,
                accent: Colors.amber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _CreatorTile(
                icon: TonztoonIcons.user,
                label: 'Author',
                value: detail.author,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CreatorTile(
                icon: TonztoonIcons.paintbrush,
                label: 'Artist',
                value: detail.artist,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AlternativeTitleTile(
          icon: TonztoonIcons.tags,
          label: 'Alternative Title',
          value: detail.alternativeTitle,
        ),
      ],
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.detail});

  final _ComicDetailUi detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.list,
            value: detail.totalChapters,
            label: 'Chapter',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.eye,
            value: detail.totalViews,
            label: 'Views',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: TonztoonIcons.calendar,
            value: detail.updatedAt,
            label: 'Update',
          ),
        ),
      ],
    );
  }
}
