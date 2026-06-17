part of '../comic_detail_screen.dart';

class _BottomReadBar extends StatelessWidget {
  const _BottomReadBar({
    required this.detail,
    required this.chaptersLoading,
    required this.progress,
    required this.downloadState,
    required this.downloadBusy,
    required this.collectionBusy,
    required this.onDownload,
    required this.onManageCollections,
    required this.onContinueReading,
  });

  final _ComicDetailUi detail;
  final bool chaptersLoading;
  final ReadingProgress? progress;
  final _ComicDownloadState downloadState;
  final bool downloadBusy;
  final bool collectionBusy;
  final VoidCallback? onDownload;
  final VoidCallback onManageCollections;
  final VoidCallback onContinueReading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasChapters = detail.chapters.isNotEmpty;
    final canRead = hasChapters && !chaptersLoading;
    final continueChapter = _continueChapter(detail, progress);
    final downloadTooltip = downloadState.label ?? 'Unduh';
    final hasReadingProgress = progress != null;
    final readProgress = _readingProgressFraction(progress);
    final readLabel = chaptersLoading
        ? 'Memuat chapter...'
        : progress == null
        ? hasChapters
              ? 'Baca ${continueChapter?.title ?? detail.firstChapterLabel}'
              : 'Chapter belum tersedia'
        : 'Lanjut ${continueChapter?.title ?? 'Chapter ${formatChapterNumber(progress!.chapterNumber)}'}';

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DecoratedBox(
          key: const ValueKey('comic-detail-bottom-read-bar'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: downloadTooltip,
                        onPressed: downloadBusy ? null : onDownload,
                        icon: downloadBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(downloadState.icon),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: hasReadingProgress
                            ? _ProgressReadButton(
                                onPressed: canRead ? onContinueReading : null,
                                icon: chaptersLoading
                                    ? TonztoonIcons.clock
                                    : TonztoonIcons.play,
                                label: readLabel,
                                progress: readProgress,
                              )
                            : FilledButton.icon(
                                onPressed: canRead ? onContinueReading : null,
                                icon: Icon(
                                  chaptersLoading
                                      ? TonztoonIcons.clock
                                      : TonztoonIcons.play,
                                ),
                                label: Text(readLabel),
                              ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        tooltip: 'Tambah ke koleksi',
                        onPressed: collectionBusy ? null : onManageCollections,
                        icon: collectionBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(TonztoonIcons.library),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressReadButton extends StatelessWidget {
  const _ProgressReadButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.progress,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onPressed != null;
    final value = enabled ? progress.clamp(0, 1).toDouble() : 0.0;
    final backgroundColor = enabled
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = enabled
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final fillColor = colorScheme.primary.withValues(
      alpha: value >= 0.98 ? 1 : 0.32,
    );
    final filledForegroundColor = value >= 0.98
        ? colorScheme.onPrimary
        : foregroundColor;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: value > 0 ? '${(value * 100).round()}% terbaca' : null,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (value > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      widthFactor: value,
                      heightFactor: 1,
                      child: ColoredBox(color: fillColor),
                    ),
                  ),
                if (value > 0 && value < 0.98)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      widthFactor: value,
                      heightFactor: 1,
                      child: SizedBox(
                        height: 4,
                        child: ColoredBox(color: colorScheme.primary),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: filledForegroundColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: filledForegroundColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
