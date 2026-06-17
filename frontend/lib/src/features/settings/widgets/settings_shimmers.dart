part of '../settings_screen.dart';

class _SettingsLoadingPlaceholder extends StatelessWidget {
  const _SettingsLoadingPlaceholder({required this.isSignedIn});

  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 132),
      children: [
        if (isSignedIn) ...[
          const _ProfileHeaderSkeleton(),
          const SizedBox(height: 18),
          const _ProfileStatsSkeleton(),
          const SizedBox(height: 24),
          const _SectionLabelSkeleton(width: 74),
          const SizedBox(height: 8),
          const _SettingsSectionSkeleton(rowCount: 6, includeSwitch: true),
          const SizedBox(height: 24),
        ] else ...[
          const _SettingsSectionSkeleton(rowCount: 1, compact: true),
          const SizedBox(height: 24),
        ],
        const _SectionLabelSkeleton(width: 96),
        const SizedBox(height: 8),
        _SettingsSectionSkeleton(rowCount: isSignedIn ? 8 : 9),
        if (isSignedIn) ...[
          const SizedBox(height: 24),
          const _SettingsButtonSkeleton(),
        ],
        const SizedBox(height: 24),
        const _SectionLabelSkeleton(width: 54),
        const SizedBox(height: 8),
        const _SettingsSectionSkeleton(rowCount: 1, compact: true),
      ],
    );
  }
}

class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: Column(
        children: [
          AppShimmerBlock(width: 88, height: 88, borderRadius: 44),
          SizedBox(height: 12),
          AppShimmerBlock(width: 170, height: 24),
          SizedBox(height: 8),
          AppShimmerBlock(width: 70, height: 24, borderRadius: 18),
        ],
      ),
    );
  }
}

class _ProfileStatsSkeleton extends StatelessWidget {
  const _ProfileStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: AppShimmer(
        child: Row(
          children: [
            Expanded(child: _StatBlockSkeleton()),
            SizedBox(width: 28),
            Expanded(child: _StatBlockSkeleton()),
          ],
        ),
      ),
    );
  }
}

class _StatBlockSkeleton extends StatelessWidget {
  const _StatBlockSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppShimmerBlock(width: 44, height: 26),
        SizedBox(height: 4),
        AppShimmerBlock(width: 68, height: 13),
      ],
    );
  }
}

class _SectionLabelSkeleton extends StatelessWidget {
  const _SectionLabelSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(child: AppShimmerBlock(width: width, height: 16));
  }
}

class _SettingsSectionSkeleton extends StatelessWidget {
  const _SettingsSectionSkeleton({
    required this.rowCount,
    this.compact = false,
    this.includeSwitch = false,
  });

  final int rowCount;
  final bool compact;
  final bool includeSwitch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < rowCount; index++) ...[
          _SettingsRowSkeleton(
            compact: compact,
            trailingWide: includeSwitch && index == rowCount - 1,
          ),
          if (index != rowCount - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SettingsRowSkeleton extends StatelessWidget {
  const _SettingsRowSkeleton({this.compact = false, this.trailingWide = false});

  final bool compact;
  final bool trailingWide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: AppShimmer(
        child: Row(
          children: [
            const AppShimmerBlock(width: 35, height: 35, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppShimmerBlock(
                    width: compact ? 132 : double.infinity,
                    height: 16,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    const AppShimmerBlock(width: 210, height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppShimmerBlock(
              width: trailingWide ? 52 : 18,
              height: trailingWide ? 28 : 18,
              borderRadius: trailingWide ? 14 : 9,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsButtonSkeleton extends StatelessWidget {
  const _SettingsButtonSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppShimmer(
      child: AppShimmerBlock(
        width: double.infinity,
        height: 50,
        borderRadius: 18,
      ),
    );
  }
}
