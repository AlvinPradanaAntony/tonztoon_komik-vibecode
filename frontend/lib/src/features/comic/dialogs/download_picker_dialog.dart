part of '../comic_detail_screen.dart';

Future<List<ChapterListItem>?> _showDownloadPicker(
  BuildContext context, {
  required List<ChapterListItem> chapters,
  required int skippedCount,
}) {
  final latestFive = chapters.take(5).toList();
  final selected = <double>{};
  final inputController = TextEditingController();
  String? inputError;

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
      return StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final selectedChapters = chapters
              .where((chapter) => selected.contains(chapter.chapterNumber))
              .toList();

          void setSelected(Iterable<ChapterListItem> items) {
            setModalState(() {
              inputError = null;
              selected
                ..clear()
                ..addAll(items.map((chapter) => chapter.chapterNumber));
            });
          }

          void applyInputSelection() {
            final input = inputController.text;
            try {
              final numbers = _parseChapterSelection(input, chapters);
              setModalState(() {
                inputError = null;
                selected
                  ..clear()
                  ..addAll(numbers);
              });
            } on FormatException catch (error) {
              setModalState(() => inputError = error.message);
            }
          }

          return SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Unduh offline',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(TonztoonIcons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (skippedCount > 0) ...[
                          Text(
                            '$skippedCount chapter dilewati karena sudah offline atau sedang antre.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionChip(
                              avatar: const Icon(
                                TonztoonIcons.download,
                                size: 16,
                              ),
                              label: const Text('Chapter terbaru'),
                              onPressed: () => setSelected([chapters.first]),
                            ),
                            if (latestFive.length > 1)
                              ActionChip(
                                avatar: const Icon(
                                  TonztoonIcons.list,
                                  size: 16,
                                ),
                                label: Text('${latestFive.length} terbaru'),
                                onPressed: () => setSelected(latestFive),
                              ),
                            ActionChip(
                              avatar: const Icon(
                                TonztoonIcons.bookMarked,
                                size: 16,
                              ),
                              label: const Text('Semua tersedia'),
                              onPressed: () => setSelected(chapters),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: inputController,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => applyInputSelection(),
                          decoration: InputDecoration(
                            labelText: 'Range atau chapter tertentu',
                            hintText: 'Contoh: 1-5, 8, 12.5',
                            helperText:
                                'Pisahkan dengan koma. Range hanya memilih chapter yang tersedia.',
                            errorText: inputError,
                            prefixIcon: const Icon(TonztoonIcons.list),
                            suffixIcon: TextButton(
                              onPressed: applyInputSelection,
                              child: const Text('Terapkan'),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      selected.isEmpty
                          ? 'Pilih chapter yang ingin diunduh'
                          : '${selected.length} chapter dipilih',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected.isEmpty
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        final chapterLabel = formatChapterNumber(
                          chapter.chapterNumber,
                        );
                        return CheckboxListTile(
                          value: selected.contains(chapter.chapterNumber),
                          onChanged: (value) {
                            setModalState(() {
                              inputError = null;
                              if (value == true) {
                                selected.add(chapter.chapterNumber);
                              } else {
                                selected.remove(chapter.chapterNumber);
                              }
                            });
                          },
                          secondary: const Icon(TonztoonIcons.bookOpen),
                          title: Text(
                            chapter.title?.trim().isNotEmpty == true
                                ? chapter.title!.trim()
                                : 'Chapter $chapterLabel',
                          ),
                          subtitle: Text(
                            chapter.totalImages <= 0
                                ? 'Jumlah halaman belum tersedia'
                                : '${chapter.totalImages} halaman',
                          ),
                        );
                      },
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Batal'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: selectedChapters.isEmpty
                                  ? null
                                  : () => Navigator.of(
                                      context,
                                    ).pop(selectedChapters),
                              icon: const Icon(TonztoonIcons.download),
                              label: Text(
                                selectedChapters.isEmpty
                                    ? 'Pilih chapter'
                                    : 'Unduh ${selectedChapters.length}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(inputController.dispose);
}
