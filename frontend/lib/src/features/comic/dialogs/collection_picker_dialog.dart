part of '../comic_detail_screen.dart';

Future<Set<int>?> _showCollectionPicker(
  BuildContext context, {
  required List<CollectionSummary> collections,
  required Set<int> selectedIds,
  required Future<CollectionSummary?> Function() onCreate,
}) {
  var items = [...collections];
  final selected = {...selectedIds};
  const collectionTileExtent = 72.0;

  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

          return SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tambah ke koleksi',
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextButton.icon(
                      onPressed: () async {
                        try {
                          final created = await onCreate();
                          if (created == null || !context.mounted) return;
                          setModalState(() {
                            items = [created, ...items];
                            selected.add(created.id);
                          });
                        } catch (error, stackTrace) {
                          if (!context.mounted) return;
                          showAppErrorSnackBar(
                            context,
                            error: error,
                            stackTrace: stackTrace,
                            logContext: 'Create collection from comic failed',
                            fallbackMessage:
                                'Koleksi baru belum dapat dibuat. Silakan coba lagi.',
                          );
                        }
                      },
                      icon: const Icon(TonztoonIcons.plus),
                      label: const Text('Buat koleksi baru'),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: Text(
                                'Belum ada koleksi tersimpan.',
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final contentHeight =
                                  (items.length * collectionTileExtent) + 10;
                              final shouldScroll =
                                  contentHeight > constraints.maxHeight;

                              return ListView.builder(
                                padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                                physics: shouldScroll
                                    ? null
                                    : const NeverScrollableScrollPhysics(),
                                itemExtent: collectionTileExtent,
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final collection = items[index];
                                  return CheckboxListTile(
                                    value: selected.contains(collection.id),
                                    onChanged: (value) {
                                      setModalState(() {
                                        if (value == true) {
                                          selected.add(collection.id);
                                        } else {
                                          selected.remove(collection.id);
                                        }
                                      });
                                    },
                                    title: Text(collection.name),
                                    subtitle: Text(
                                      '${collection.totalItems} komik tersimpan',
                                    ),
                                    secondary: const Icon(
                                      TonztoonIcons.library,
                                    ),
                                  );
                                },
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
                              onPressed: () =>
                                  Navigator.of(context).pop(selected),
                              icon: const Icon(TonztoonIcons.check),
                              label: const Text('Simpan'),
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
  );
}

Future<String?> _showCollectionNameDialog(BuildContext context) {
  var value = '';
  return showTonztoonModal<String>(
    context: context,
    builder: (context) => TonztoonModalDialog(
      title: 'Koleksi baru',
      message:
          'Buat koleksi untuk menyimpan komik ini bersama judul lain yang sejenis.',
      helperText: 'Nama koleksi bisa diubah lagi dari halaman Pustaka.',
      helperIcon: TonztoonIcons.library,
      art: TonztoonModalArt.folder,
      content: TextFormField(
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
      primaryLabel: 'Buat',
      onPrimaryPressed: () => Navigator.of(context).pop(value),
    ),
  );
}
