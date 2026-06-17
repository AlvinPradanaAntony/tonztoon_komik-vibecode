part of '../library_shared_panes.dart';

class _SceneCard extends ConsumerWidget {
  const _SceneCard({required this.scene, required this.allowDelete});

  final FavoriteScene scene;
  final bool allowDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showScenePreview(context, scene),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ComicCover(imageUrl: scene.imageUrl, borderRadius: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: List.generate(9, (index) {
                      final p = index / 8;
                      return Colors.black.withValues(
                        alpha: math.pow(p, 1.5).toDouble(),
                      );
                    }),
                  ),
                ),
              ),
              if (allowDelete)
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Hapus scene',
                    onPressed: () => _deleteScene(context, ref),
                    icon: const Icon(TonztoonIcons.trash, size: 18),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scene.comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Ch ${formatChapterNumber(scene.chapterNumber)} - Page ${scene.pageItemIndex + 1}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteScene(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(libraryRepositoryProvider).deleteFavoriteScene(scene.id);
      ref.invalidate(favoriteScenesProvider);
      if (context.mounted) _showMessage(context, 'Scene favorit dihapus.');
    } catch (error, stackTrace) {
      if (context.mounted) showLibraryActionError(context, error, stackTrace);
    }
  }
}

Future<void> _showScenePreview(BuildContext context, FavoriteScene scene) {
  final comic = scene.comic.toSummary();
  final chapterLabel = formatChapterNumber(scene.chapterNumber);

  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);

      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: scene.imageUrl == null || scene.imageUrl!.isEmpty
                      ? const Icon(
                          Icons.broken_image_rounded,
                          size: 56,
                          color: Colors.white54,
                        )
                      : Image.network(
                          scene.imageUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.cloud_off_rounded,
                              size: 56,
                              color: Colors.white54,
                            );
                          },
                        ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(TonztoonIcons.close),
                        color: Colors.white,
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: List.generate(9, (index) {
                      final p = index / 8;
                      return Colors.black.withValues(
                        alpha: math.pow(p, 1.5).toDouble(),
                      );
                    }),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scene.comic.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chapter $chapterLabel - Page ${scene.pageItemIndex + 1}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.76),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _openComicDetail(context, comic);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                                icon: const Icon(TonztoonIcons.bookOpen),
                                label: const Text('Detail'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _openSceneReader(context, scene);
                                },
                                icon: const Icon(TonztoonIcons.play),
                                label: const Text('Baca dari scene'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
