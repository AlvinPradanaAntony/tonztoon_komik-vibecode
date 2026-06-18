part of '../library_screen.dart';

@visibleForTesting
Future<List<BookmarkLinkCandidate>?> showBookmarkLinkCandidatesDialog(
  BuildContext context,
  List<BookmarkLinkCandidate> candidates,
) {
  final selectedByDestination = <String, BookmarkLinkCandidate>{};
  for (final candidate in candidates) {
    if (candidate.confidence < 0.82) {
      continue;
    }
    final destinationKey =
        '${candidate.bookmark.key}::${candidate.comic.sourceName}';
    final current = selectedByDestination[destinationKey];
    if (current == null || candidate.confidence > current.confidence) {
      selectedByDestination[destinationKey] = candidate;
    }
  }
  final selectedKeys = selectedByDestination.values
      .map((candidate) => candidate.key)
      .toSet();

  // Group candidates by bookmark key
  final grouped = <String, List<BookmarkLinkCandidate>>{};
  for (final candidate in candidates) {
    grouped.putIfAbsent(candidate.bookmark.key, () => []).add(candidate);
  }

  // Sort candidates within each group by confidence (descending)
  for (final key in grouped.keys) {
    grouped[key]!.sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  final bookmarkKeys = grouped.keys.toList();

  // Sort groups: groups with automatically checked candidates first,
  // then sort descending by maximum confidence score.
  bookmarkKeys.sort((a, b) {
    final candidatesA = grouped[a]!;
    final candidatesB = grouped[b]!;

    final hasAutoCheckA = candidatesA.any((c) => c.confidence >= 0.82);
    final hasAutoCheckB = candidatesB.any((c) => c.confidence >= 0.82);

    if (hasAutoCheckA != hasAutoCheckB) {
      return hasAutoCheckA ? -1 : 1;
    }

    final maxConfA =
        candidatesA.first.confidence; // Sorted descending, first is max
    final maxConfB = candidatesB.first.confidence;

    return maxConfB.compareTo(maxConfA);
  });

  return showDialog<List<BookmarkLinkCandidate>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text('Hubungkan source lain'),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: bookmarkKeys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final key = bookmarkKeys[index];
                  final bookmarkCandidates = grouped[key]!;
                  final bookmark = bookmarkCandidates.first.bookmark;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group Header: Primary Bookmark Title and Source Badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: 'Buka detail bookmark utama',
                                child: InkWell(
                                  key: ValueKey(
                                    'bookmark-detail-${bookmark.key}',
                                  ),
                                  onTap: () => _openComicDetail(
                                    context,
                                    bookmark.toSummary(),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Text(
                                    bookmark.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.primary,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SourceTag(
                              key: ValueKey('bookmark-source-${bookmark.key}'),
                              sourceName: bookmark.sourceName,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 4),
                        // Sub-list of candidates
                        ...bookmarkCandidates.map((candidate) {
                          final selected = selectedKeys.contains(candidate.key);
                          return CheckboxListTile(
                            value: selected,
                            contentPadding: const EdgeInsets.only(left: 8.0),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedKeys.removeWhere((key) {
                                    final selectedCandidate = candidates
                                        .where((item) => item.key == key)
                                        .firstOrNull;
                                    return selectedCandidate != null &&
                                        selectedCandidate.bookmark.key ==
                                            candidate.bookmark.key &&
                                        selectedCandidate.comic.sourceName ==
                                            candidate.comic.sourceName;
                                  });
                                  selectedKeys.add(candidate.key);
                                } else {
                                  selectedKeys.remove(candidate.key);
                                }
                              });
                            },
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    candidate.comic.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey(
                                    'bookmark-candidate-detail-${candidate.key}',
                                  ),
                                  tooltip: 'Buka detail kandidat bookmark',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () => _openComicDetail(
                                    context,
                                    candidate.comic.toSummary(),
                                  ),
                                  icon: Icon(
                                    TonztoonIcons.eye,
                                    size: 18,
                                    color: colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '-> ${comicSourceNameLabel(candidate.comic.sourceName)}'
                              ' • kecocokan ${(candidate.confidence * 100).round()}%',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: selectedKeys.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      candidates
                          .where(
                            (candidate) => selectedKeys.contains(candidate.key),
                          )
                          .toList(),
                    ),
              child: Text('Hubungkan (${selectedKeys.length})'),
            ),
          ],
        );
      },
    ),
  );
}

class _BookmarkScanProgressDialog extends StatefulWidget {
  const _BookmarkScanProgressDialog({
    required this.progress,
    required this.totalBookmarks,
  });

  final ValueListenable<int> progress;
  final int totalBookmarks;

  @override
  State<_BookmarkScanProgressDialog> createState() =>
      _BookmarkScanProgressDialogState();
}

class _BookmarkScanProgressDialogState
    extends State<_BookmarkScanProgressDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  double get _target => widget.progress.value.toDouble();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _animation = AlwaysStoppedAnimation<double>(_target);
    widget.progress.addListener(_animateToProgress);
  }

  @override
  void didUpdateWidget(covariant _BookmarkScanProgressDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress == widget.progress) return;
    oldWidget.progress.removeListener(_animateToProgress);
    widget.progress.addListener(_animateToProgress);
    _animateToProgress();
  }

  void _animateToProgress() {
    final begin = _animation.value;
    final end = _target;
    if (begin == end) return;

    final itemDelta = (end - begin).abs().ceil();
    _controller
      ..stop()
      ..duration = Duration(milliseconds: (itemDelta * 90).clamp(180, 500));
    _animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_animateToProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TonztoonModalDialog(
      title: 'Memindai source lain',
      message:
          'Tunggu sampai pemindaian selesai agar hasil kandidat dapat ditampilkan.',
      eyebrow: 'Bookmark multi-source',
      helperText:
          'Tetap di halaman ini. Jika koneksi gagal, progres sementara dapat dilanjutkan.',
      helperIcon: TonztoonIcons.clock,
      art: TonztoonModalArt.cloudSync,
      showActions: false,
      showCloseButton: false,
      content: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final safeTotal = widget.totalBookmarks > 0
              ? widget.totalBookmarks
              : 1;
          final animatedScanned = _animation.value.clamp(0, safeTotal);
          final completed = animatedScanned.floor();
          final value = (animatedScanned / safeTotal).clamp(0.0, 1.0);
          final percentage = (value * 100).round();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.totalBookmarks > 0
                          ? '$completed dari ${widget.totalBookmarks} bookmark'
                          : '$completed bookmark dipindai',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookmarkLinkProgressDialog extends StatelessWidget {
  const _BookmarkLinkProgressDialog({required this.progress});

  final ValueListenable<BookmarkLinkSaveProgress> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BookmarkLinkSaveProgress>(
      valueListenable: progress,
      builder: (context, value, _) {
        final safeTotal = value.total > 0 ? value.total : 1;
        final completed = value.completed.clamp(0, safeTotal);
        final progressValue = (completed / safeTotal).clamp(0.0, 1.0);
        final syncing = value.stage == BookmarkLinkSaveStage.syncingCompleted;

        return TonztoonModalDialog(
          title: syncing
              ? 'Menyinkronkan chapter selesai'
              : 'Menghubungkan kandidat',
          message: syncing
              ? 'Status completed/read sedang diterapkan ke source yang terhubung.'
              : 'Relasi komik terpilih sedang disimpan secara bertahap.',
          eyebrow: 'Bookmark multi-source',
          helperText:
              'Setiap batch disimpan terpisah dan otomatis dicoba ulang jika koneksi melambat.',
          helperIcon: TonztoonIcons.clock,
          art: TonztoonModalArt.cloudSync,
          showActions: false,
          showCloseButton: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      syncing
                          ? '$completed dari ${value.total} grup'
                          : '$completed dari ${value.total} kandidat',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${(progressValue * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: progressValue),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, _) {
                  return LinearProgressIndicator(
                    value: animatedValue,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _showCollectionNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String? initialValue,
}) {
  var value = initialValue ?? '';

  return showTonztoonModal<String>(
    context: context,
    builder: (context) => TonztoonModalDialog(
      title: title,
      message:
          'Beri nama koleksi supaya daftar komik lebih mudah ditemukan nanti.',
      helperText: 'Gunakan nama singkat dan jelas, misalnya Favorit Utama.',
      helperIcon: TonztoonIcons.library,
      art: TonztoonModalArt.folder,
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nama koleksi',
          hintText: 'Contoh: Favorit Utama',
        ),
        textInputAction: TextInputAction.done,
        onChanged: (text) => value = text,
        onFieldSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      secondaryLabel: 'Batal',
      onSecondaryPressed: () => Navigator.of(context).pop(),
      primaryLabel: actionLabel,
      onPrimaryPressed: () => Navigator.of(context).pop(value),
    ),
  );
}

Future<void> _renameCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final name = await _showCollectionNameDialog(
    context,
    title: 'Rename koleksi',
    actionLabel: 'Simpan',
    initialValue: collection.name,
  );
  if (!context.mounted || name == null || name.trim().isEmpty) return;

  try {
    final updated = await ref
        .read(libraryRepositoryProvider)
        .renameCollection(collection.id, name);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return;
    _showMessage(context, 'Koleksi menjadi "${updated.name}".');
  } catch (error, stackTrace) {
    if (context.mounted) showLibraryActionError(context, error, stackTrace);
  }
}

Future<bool> _deleteCollection(
  BuildContext context,
  WidgetRef ref,
  CollectionSummary collection,
) async {
  final confirmed = await showTonztoonConfirmDialog(
    context,
    title: 'Hapus koleksi',
    message: 'Hapus "${collection.name}" beserta daftar komiknya?',
    helperText:
        'Koleksi akan hilang dari pustaka. Komik, bookmark, dan progress baca tetap aman.',
    helperIcon: TonztoonIcons.trash,
    cancelLabel: 'Batal',
    confirmLabel: 'Hapus',
    variant: TonztoonModalVariant.danger,
    art: TonztoonModalArt.trash,
  );
  if (!context.mounted || confirmed != true) return false;

  try {
    await ref.read(libraryRepositoryProvider).deleteCollection(collection.id);
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionDetailProvider(collection.id));
    if (!context.mounted) return false;
    _showMessage(context, 'Koleksi dihapus.');
    return true;
  } catch (error, stackTrace) {
    if (context.mounted) showLibraryActionError(context, error, stackTrace);
    return false;
  }
}
