import 'package:flutter/material.dart';

import '../models/library.dart';

enum GuestMigrationDialogAction { cancel, skip, migrate }

int guestMigrationItemCount(GuestMigrationSummary summary) {
  return summary.bookmarks +
      summary.collections +
      summary.progress +
      summary.favoriteScenes +
      summary.downloads +
      (summary.hasReaderPreferences ? 1 : 0) +
      (summary.readingTimeSeconds > 0 ? 1 : 0);
}

Future<GuestMigrationDialogAction?> showGuestMigrationDialog(
  BuildContext context, {
  required GuestMigrationSummary summary,
  required String title,
  required String message,
  bool barrierDismissible = true,
  String secondaryLabel = 'Batal',
  GuestMigrationDialogAction secondaryAction =
      GuestMigrationDialogAction.cancel,
}) {
  return showDialog<GuestMigrationDialogAction>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: GuestMigrationDialogContent(summary: summary, message: message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(secondaryAction),
          child: Text(secondaryLabel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(GuestMigrationDialogAction.migrate),
          child: const Text('Migrasi & Sinkronkan'),
        ),
      ],
    ),
  );
}

class GuestMigrationDialogContent extends StatelessWidget {
  const GuestMigrationDialogContent({
    super.key,
    required this.summary,
    required this.message,
  });

  final GuestMigrationSummary summary;
  final String message;

  @override
  Widget build(BuildContext context) {
    final items = _migrationItems(summary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.label)),
                        Text(
                          item.suffix == null
                              ? '${item.value}'
                              : '${item.value} ${item.suffix}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_MigrationSummaryItem> _migrationItems(GuestMigrationSummary summary) {
    return [
      _MigrationSummaryItem('Bookmark', summary.bookmarks),
      _MigrationSummaryItem('Koleksi', summary.collections),
      _MigrationSummaryItem('Progress baca', summary.progress),
      _MigrationSummaryItem('Scene favorit', summary.favoriteScenes),
      _MigrationSummaryItem('Antrean download', summary.downloads),
      if (summary.hasReaderPreferences)
        const _MigrationSummaryItem('Preferensi reader', 1),
      if (summary.readingTimeSeconds > 0)
        _MigrationSummaryItem(
          'Waktu baca',
          (summary.readingTimeSeconds / 60).ceil(),
          suffix: 'menit',
        ),
    ].where((item) => item.value > 0).toList();
  }
}

class GuestMigrationLoadingDialog extends StatelessWidget {
  const GuestMigrationLoadingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Menyinkronkan data guest...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationSummaryItem {
  const _MigrationSummaryItem(this.label, this.value, {this.suffix});

  final String label;
  final int value;
  final String? suffix;
}
