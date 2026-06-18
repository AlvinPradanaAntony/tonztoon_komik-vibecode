part of '../comic_detail_screen.dart';

class _ChapterPanel extends StatelessWidget {
  const _ChapterPanel({
    required this.chapters,
    required this.downloadState,
    required this.progress,
    required this.completedChapterNumbers,
    required this.showReadSync,
    required this.readSyncBusy,
    required this.loading,
    required this.onRetry,
    required this.onOpenChapter,
    required this.onSyncReadStatus,
    this.error,
  });

  final List<_ChapterUi> chapters;
  final _ComicDownloadState downloadState;
  final ReadingProgress? progress;
  final Set<double> completedChapterNumbers;
  final bool showReadSync;
  final bool readSyncBusy;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<_ChapterUi> onOpenChapter;
  final VoidCallback onSyncReadStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.24 : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          children: [
            Row(
              children: [
                const _SectionHeader(
                  icon: TonztoonIcons.list,
                  title: 'Daftar Chapter',
                ),
                const Spacer(),
                if (showReadSync) ...[
                  _ReadSyncIconButton(
                    busy: readSyncBusy,
                    onPressed: readSyncBusy ? null : onSyncReadStatus,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${chapters.length} terbaru',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const _ChapterListShimmer()
            else if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: AppErrorState(
                  error: error!,
                  fallbackMessage:
                      'Chapter belum dapat dimuat. Silakan coba lagi.',
                  onRetry: onRetry,
                  retryLabel: 'Retry',
                  icon: null,
                  messageStyle: theme.textTheme.bodyMedium,
                ),
              )
            else if (chapters.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Belum ada chapter tersedia.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              SizedBox(
                height: 430,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Scrollbar(
                    child: ListView.separated(
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 4),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        return _ChapterRow(
                          chapter: chapters[index],
                          isLatest: index == 0,
                          offline: downloadState.offlineChapterNumbers.contains(
                            chapters[index].chapterNumber,
                          ),
                          readState: _chapterReadState(
                            chapters[index],
                            progress,
                            completedChapterNumbers,
                          ),
                          onTap: () => onOpenChapter(chapters[index]),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemCount: chapters.length,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadSyncIconButton extends StatefulWidget {
  const _ReadSyncIconButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_ReadSyncIconButton> createState() => _ReadSyncIconButtonState();
}

class _ReadSyncIconButtonState extends State<_ReadSyncIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ReadSyncIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.busy) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = widget.busy
        ? 'Menyinkronkan status read'
        : 'Sinkronkan status read';
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: tooltip,
          onPressed: widget.onPressed,
          icon: RotationTransition(
            turns: _controller,
            child: Icon(
              Icons.sync_rounded,
              size: 18,
              color: widget.busy
                  ? colorScheme.secondary
                  : colorScheme.secondary.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestChapterBadge extends StatelessWidget {
  const _LatestChapterBadge();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _LatestChapterBadgeClipper(),
      child: ColoredBox(
        color: const Color(0xFFFF9700),
        child: SizedBox(
          width: 66,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 7, bottom: 2),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'TERBARU',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestChapterBadgeClipper extends CustomClipper<Path> {
  const _LatestChapterBadgeClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(16, size.height)
      ..quadraticBezierTo(8, size.height - 1, 5, size.height - 8)
      ..close();
  }

  @override
  bool shouldReclip(covariant _LatestChapterBadgeClipper oldClipper) => false;
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.isLatest,
    required this.offline,
    required this.readState,
    required this.onTap,
  });

  final _ChapterUi chapter;
  final bool isLatest;
  final bool offline;
  final _ChapterReadState readState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 2.6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 11, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      TonztoonIcons.bookOpen,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: isLatest ? 26 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            chapter.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (readState != _ChapterReadState.none) ...[
                            const SizedBox(height: 7),
                            _ChapterReadBadge(state: readState),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (offline) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Tersedia offline',
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colorScheme.secondary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          TonztoonIcons.badgeCheckFilled,
                          size: 15,
                          color: colorScheme.secondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Icon(TonztoonIcons.chevronRight, size: 18),
                ],
              ),
            ),
            if (isLatest)
              const Positioned(top: 0, right: 0, child: _LatestChapterBadge()),
          ],
        ),
      ),
    );
  }
}

class _ChapterReadBadge extends StatelessWidget {
  const _ChapterReadBadge({required this.state});

  final _ChapterReadState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final completed = state == _ChapterReadState.completed;
    final color = completed ? const Color(0xFF16A34A) : colorScheme.secondary;
    final label = completed ? 'Selesai dibaca' : 'Terakhir dibaca';
    final icon = completed
        ? TonztoonIcons.badgeCheckFilled
        : TonztoonIcons.clock;

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
