import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import '../models/library.dart';
import 'tonztoon_modal_dialog.dart';

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
  return showTonztoonModal<GuestMigrationDialogAction>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => TonztoonModalDialog(
      title: title,
      message: message,
      helperText:
          'Data lokal akan disalin ke akun cloud. File offline tetap tersimpan di perangkat ini.',
      helperIcon: TonztoonIcons.cloudUpload,
      art: TonztoonModalArt.cloudSync,
      content: GuestMigrationDialogContent(summary: summary),
      secondaryLabel: secondaryLabel,
      onSecondaryPressed: () => Navigator.of(context).pop(secondaryAction),
      primaryLabel: 'Migrasi & Sinkronkan',
      onPrimaryPressed: () =>
          Navigator.of(context).pop(GuestMigrationDialogAction.migrate),
    ),
  );
}

class GuestMigrationDialogContent extends StatelessWidget {
  const GuestMigrationDialogContent({super.key, required this.summary});

  final GuestMigrationSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = _migrationItems(summary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    return const TonztoonModalDialog(
      title: 'Menyinkronkan data',
      message:
          'Data guest sedang dipindahkan ke akun cloud. Tunggu sebentar sampai proses selesai.',
      art: TonztoonModalArt.cloudSync,
      showActions: false,
      showCloseButton: false,
      content: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 2.8),
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
