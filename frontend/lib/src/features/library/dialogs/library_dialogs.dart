part of '../library_screen.dart';

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
  final expandedKeys = <String>{};
  for (final key in bookmarkKeys) {
    final hasAutoChecked = grouped[key]!.any((candidate) => selectedKeys.contains(candidate.key));
    if (hasAutoChecked) {
      expandedKeys.add(key);
    }
  }

  return showTonztoonModal<List<BookmarkLinkCandidate>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return TonztoonModalDialog(
          title: 'Hubungkan source lain',
          message: 'Pilih versi komik dari source lain yang ingin Anda hubungkan dengan komik ini.',
          eyebrow: 'Sinkronisasi',
          art: TonztoonModalArt.cloudSync,
          content: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: bookmarkKeys.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final key = bookmarkKeys[index];
              final bookmarkCandidates = grouped[key]!;
              final bookmark = bookmarkCandidates.first.bookmark;
              final isExpanded = expandedKeys.contains(key);

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group Header: Primary Bookmark Title, SourceTag & Collapse/Expand Trigger
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bookmarks_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
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
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: isExpanded ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right-side actions: Circular Badge (count), SourceTag, and Chevron Toggle
                          Flexible(
                            child: InkWell(
                              key: ValueKey('expand-toggle-${bookmark.key}'),
                              onTap: () {
                                setDialogState(() {
                                  if (isExpanded) {
                                    expandedKeys.remove(key);
                                  } else {
                                    expandedKeys.add(key);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${bookmarkCandidates.length}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: SourceTag(
                                        key: ValueKey('bookmark-source-${bookmark.key}'),
                                        sourceName: bookmark.sourceName,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      isExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isExpanded) ...[
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        // Sub-list of candidates
                        ...bookmarkCandidates.map((candidate) {
                          final selected = selectedKeys.contains(candidate.key);
                          final confidencePercent = (candidate.confidence * 100).round();

                          // Color coding for match confidence
                          Color confidenceColor;
                          if (candidate.confidence >= 0.90) {
                            confidenceColor = const Color(0xFF22C55E); // Green
                          } else if (candidate.confidence >= 0.80) {
                            confidenceColor = colorScheme.primary; // Primary (Orange)
                          } else {
                            confidenceColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.8);
                          }

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              color: selected
                                  ? colorScheme.primary.withValues(alpha: 0.06)
                                  : colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                width: selected ? 1.5 : 1.0,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                        setDialogState(() {
                                          if (selected == false) {
                                            // Remove any other selected candidate for the same bookmark and source
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
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Custom rounded checkbox
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? colorScheme.primary
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: selected
                                              ? colorScheme.primary
                                              : colorScheme.outline,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    // Title & Subtitle Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            candidate.comic.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            children: [
                                              Text(
                                                comicSourceNameLabel(
                                                  candidate.comic.sourceName,
                                                ),
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '·',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: confidenceColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '$confidencePercent% cocok',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: confidenceColor,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Preview icon button with modern background
                                    Material(
                                      color: colorScheme.secondary.withValues(alpha: 0.08),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        key: ValueKey(
                                          'bookmark-candidate-detail-${candidate.key}',
                                        ),
                                        tooltip: 'Buka detail kandidat bookmark',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                        padding: EdgeInsets.zero,
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
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          primaryLabel: 'Hubungkan (${selectedKeys.length})',
          onPrimaryPressed: selectedKeys.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    candidates
                        .where((candidate) => selectedKeys.contains(candidate.key))
                        .toList(),
                  ),
          secondaryLabel: 'Batal',
          onSecondaryPressed: () => Navigator.of(context).pop(),
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

class BookmarkLinkProgressDialog extends StatelessWidget {
  const BookmarkLinkProgressDialog({super.key, required this.progress});

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
