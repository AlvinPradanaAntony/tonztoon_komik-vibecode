part of '../comic_detail_screen.dart';

Future<List<ChapterListItem>?> _showDownloadPicker(
  BuildContext context, {
  required List<ChapterListItem> chapters,
  required int skippedCount,
}) {
  return showModalBottomSheet<List<ChapterListItem>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    requestFocus: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _DownloadPickerSheet(
        chapters: chapters,
        skippedCount: skippedCount,
      );
    },
  );
}

class _DownloadPickerSheet extends StatefulWidget {
  const _DownloadPickerSheet({
    required this.chapters,
    required this.skippedCount,
  });

  final List<ChapterListItem> chapters;
  final int skippedCount;

  @override
  State<_DownloadPickerSheet> createState() => _DownloadPickerSheetState();
}

class _DownloadPickerSheetState extends State<_DownloadPickerSheet> {
  final _selected = <double>{};
  final _inputController = TextEditingController();
  _DownloadQuickAction? _activeQuickAction;
  String? _inputError;

  List<ChapterListItem> get _latestFive => widget.chapters.take(5).toList();

  List<ChapterListItem> get _selectedChapters => widget.chapters
      .where((chapter) => _selected.contains(chapter.chapterNumber))
      .toList();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _setSelected(
    Iterable<ChapterListItem> items, {
    _DownloadQuickAction? quickAction,
  }) {
    setState(() {
      _activeQuickAction = quickAction;
      _inputError = null;
      _selected
        ..clear()
        ..addAll(items.map((chapter) => chapter.chapterNumber));
    });
  }

  void _applyInputSelection() {
    final input = _inputController.text;
    try {
      final numbers = _parseChapterSelection(input, widget.chapters);
      setState(() {
        _activeQuickAction = null;
        _inputError = null;
        _selected
          ..clear()
          ..addAll(numbers);
      });
    } on FormatException catch (error) {
      setState(() => _inputError = error.message);
    }
  }

  void _handleInputChanged(String value) {
    if (_inputError == null) return;
    try {
      _parseChapterSelection(value, widget.chapters);
      setState(() => _inputError = null);
    } on FormatException {
      // Keep the current error until the input becomes valid or focus leaves.
    }
  }

  void _clearInputError() {
    if (_inputError == null) return;
    setState(() => _inputError = null);
  }

  void _toggleChapter(ChapterListItem chapter, bool value) {
    setState(() {
      _activeQuickAction = null;
      _inputError = null;
      if (value) {
        _selected.add(chapter.chapterNumber);
      } else {
        _selected.remove(chapter.chapterNumber);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _activeQuickAction = null;
      _selected.clear();
    });
  }

  void _pop([List<ChapterListItem>? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final latestFive = _latestFive;
    final selectedChapters = _selectedChapters;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DownloadSheetHeader(
              skippedCount: widget.skippedCount,
              onClose: _pop,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _DownloadQuickActions(
                    latestFiveCount: latestFive.length,
                    activeAction: _activeQuickAction,
                    onLatest: () => _setSelected([
                      widget.chapters.first,
                    ], quickAction: _DownloadQuickAction.latest),
                    onLatestFive: latestFive.length > 1
                        ? () => _setSelected(
                            latestFive,
                            quickAction: _DownloadQuickAction.latestFive,
                          )
                        : null,
                    onAll: () => _setSelected(
                      widget.chapters,
                      quickAction: _DownloadQuickAction.all,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DownloadRangeInput(
                    controller: _inputController,
                    errorText: _inputError,
                    onChanged: _handleInputChanged,
                    onTapOutside: _clearInputError,
                    onApply: _applyInputSelection,
                  ),
                  const SizedBox(height: 18),
                  _DownloadChapterListHeader(
                    selectedCount: _selected.length,
                    chapterCount: widget.chapters.length,
                    onClear: _selected.isEmpty ? null : _clearSelection,
                  ),
                  const SizedBox(height: 10),
                  for (final chapter in widget.chapters) ...[
                    _DownloadChapterTile(
                      chapter: chapter,
                      selected: _selected.contains(chapter.chapterNumber),
                      onChanged: (value) => _toggleChapter(chapter, value),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            _DownloadSheetActions(
              selectedCount: selectedChapters.length,
              onCancel: _pop,
              onDownload: selectedChapters.isEmpty
                  ? null
                  : () => _pop(selectedChapters),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadSheetHeader extends StatelessWidget {
  const _DownloadSheetHeader({
    required this.skippedCount,
    required this.onClose,
  });

  final int skippedCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Unduh offline',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: onClose,
                icon: const Icon(TonztoonIcons.close),
              ),
            ],
          ),
          if (skippedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$skippedCount chapter dilewati karena sudah offline atau sedang antre.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _DownloadQuickAction { latest, latestFive, all }

class _DownloadQuickActions extends StatelessWidget {
  const _DownloadQuickActions({
    required this.latestFiveCount,
    required this.activeAction,
    required this.onLatest,
    required this.onLatestFive,
    required this.onAll,
  });

  final int latestFiveCount;
  final _DownloadQuickAction? activeAction;
  final VoidCallback onLatest;
  final VoidCallback? onLatestFive;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DownloadActionCard(
            icon: TonztoonIcons.download,
            title: 'Terbaru',
            subtitle: '1 chapter',
            active: activeAction == _DownloadQuickAction.latest,
            onTap: onLatest,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DownloadActionCard(
            icon: TonztoonIcons.list,
            title: '$latestFiveCount terbaru',
            subtitle: 'Batch cepat',
            active: activeAction == _DownloadQuickAction.latestFive,
            onTap: onLatestFive,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DownloadActionCard(
            icon: TonztoonIcons.bookMarked,
            title: 'Semua',
            subtitle: 'Tersedia',
            active: activeAction == _DownloadQuickAction.all,
            onTap: onAll,
          ),
        ),
      ],
    );
  }
}

class _DownloadActionCard extends StatelessWidget {
  const _DownloadActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;

    final backgroundColor = enabled
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.44);

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active && enabled ? colorScheme.primary : backgroundColor,
          width: 1.4,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 19,
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadRangeInput extends StatefulWidget {
  const _DownloadRangeInput({
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onTapOutside,
    required this.onApply,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onTapOutside;
  final VoidCallback onApply;

  @override
  State<_DownloadRangeInput> createState() => _DownloadRangeInputState();
}

class _DownloadRangeInputState extends State<_DownloadRangeInput> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasError = widget.errorText != null;
    final isFocused = _focusNode.hasFocus;
    final borderColor = hasError
        ? colorScheme.error
        : isFocused
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.62);
    final backgroundColor = isFocused
        ? colorScheme.primaryContainer.withValues(alpha: 0.18)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.62);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: isFocused || hasError ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          onChanged: widget.onChanged,
          onTapOutside: (_) {
            _focusNode.unfocus();
            widget.onTapOutside();
          },
          onSubmitted: (_) => widget.onApply(),
          decoration: InputDecoration(
            labelText: 'Range atau chapter tertentu',
            hintText: 'Contoh: 1-5, 8, 12.5',
            helperText: 'Pisahkan dengan koma. Range memilih chapter tersedia.',
            errorText: widget.errorText,
            prefixIcon: const Icon(TonztoonIcons.list),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 40,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: TextButton(
                onPressed: widget.onApply,
                style: TextButton.styleFrom(
                  backgroundColor: isFocused
                      ? colorScheme.secondary
                      : Colors.transparent,
                  foregroundColor: isFocused
                      ? colorScheme.onSecondary
                      : colorScheme.secondary,
                  minimumSize: const Size(78, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Terapkan'),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 86,
              minHeight: 40,
            ),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 10,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _DownloadChapterListHeader extends StatelessWidget {
  const _DownloadChapterListHeader({
    required this.selectedCount,
    required this.chapterCount,
    required this.onClear,
  });

  final int selectedCount;
  final int chapterCount;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            selectedCount == 0
                ? 'Pilih chapter'
                : '$selectedCount dari $chapterCount chapter dipilih',
            style: theme.textTheme.labelLarge?.copyWith(
              color: selectedCount == 0
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Bersihkan')),
      ],
    );
  }
}

class _DownloadChapterTile extends StatelessWidget {
  const _DownloadChapterTile({
    required this.chapter,
    required this.selected,
    required this.onChanged,
  });

  final ChapterListItem chapter;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chapterLabel = formatChapterNumber(chapter.chapterNumber);
    final title = chapter.title?.trim().isNotEmpty == true
        ? chapter.title!.trim()
        : 'Chapter $chapterLabel';

    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.56),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: Icon(
                  selected
                      ? TonztoonIcons.badgeCheckFilled
                      : TonztoonIcons.bookOpen,
                  size: 20,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      chapter.totalImages <= 0
                          ? 'Jumlah halaman belum tersedia'
                          : '${chapter.totalImages} halaman',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadSheetActions extends StatelessWidget {
  const _DownloadSheetActions({
    required this.selectedCount,
    required this.onCancel,
    required this.onDownload,
  });

  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(TonztoonIcons.download),
                label: Text(
                  selectedCount == 0 ? 'Pilih chapter' : 'Unduh $selectedCount',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
