import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../helpers/navigation_helpers.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/load_more_footer.dart';
import '../../widgets/metadata_separator.dart';
import '../../widgets/source_tag.dart';
import '../../widgets/scroll_to_top_fab.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import 'library_error.dart';
import 'library_shared_panes.dart';
import 'widgets/library_async_pane.dart';

part 'tabs/library_tabs.dart';
part 'helpers/library_helpers.dart';
part 'dialogs/library_dialogs.dart';
part 'widgets/library_panes.dart';
part 'widgets/library_hero.dart';
part 'widgets/library_bookmark.dart';
part 'widgets/library_collections.dart';
part 'widgets/library_history.dart';
part 'widgets/library_common.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 5,
      initialIndex: initialTabIndex.clamp(0, 4),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Text('Pustaka', style: theme.textTheme.titleLarge),
          centerTitle: false,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(54),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                tabs: [
                  Tab(text: 'Bookmark'),
                  Tab(text: 'Koleksi'),
                  Tab(text: 'Scene'),
                  Tab(text: 'Riwayat'),
                  Tab(text: 'Unduhan'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _BookmarksTab(),
            _CollectionsTab(),
            _ScenesTab(),
            _HistoryTab(),
            _DownloadsTab(),
          ],
        ),
      ),
    );
  }
}
