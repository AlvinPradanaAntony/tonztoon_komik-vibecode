import 'package:flutter/material.dart';

import '../helpers/app_icons.dart';
import '../models/comic.dart';

const bookmarkStatusOptions = <String>['ongoing', 'completed', 'hiatus'];

String bookmarkStatusLabel(String status) => switch (status) {
  'ongoing' => 'Ongoing',
  'completed' => 'Selesai',
  'hiatus' => 'Hiatus',
  _ => status,
};

IconData bookmarkStatusIcon(String status) => switch (status) {
  'ongoing' => TonztoonIcons.clock,
  'completed' => TonztoonIcons.badgeCheck,
  'hiatus' => TonztoonIcons.circleDotDashed,
  _ => TonztoonIcons.bookmark,
};

Future<String?> showBookmarkStatusPicker(
  BuildContext context,
  ComicSummary comic,
) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ubah status komik',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                comic.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final status in bookmarkStatusOptions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(bookmarkStatusIcon(status)),
                  title: Text(bookmarkStatusLabel(status)),
                  trailing: comic.status?.trim().toLowerCase() == status
                      ? const Icon(TonztoonIcons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(status),
                ),
              const SizedBox(height: 4),
              Text(
                'Saat source menemukan chapter baru, status otomatis kembali ke Ongoing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
