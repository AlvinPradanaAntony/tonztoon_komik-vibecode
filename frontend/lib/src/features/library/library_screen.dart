import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../helpers/navigation_helpers.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../routing/library_routes.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/app_surface_ink.dart';
import '../../widgets/bookmark_status_picker.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/column_grid.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import '../../widgets/load_more_footer.dart';
import '../../widgets/metadata_separator.dart';
import '../../widgets/source_tag.dart';
import '../../widgets/scroll_to_top_fab.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import 'library_error.dart';
import 'library_shared_panes.dart';
import 'widgets/library_async_pane.dart';

part 'tabs/library_tabs.dart';
part 'state/library_screen_state.dart';
part 'helpers/library_helpers.dart';
part 'dialogs/library_dialogs.dart';
part 'widgets/library_panes.dart';
part 'widgets/library_hero.dart';
part 'widgets/library_bookmark.dart';
part 'widgets/library_collections.dart';
part 'widgets/library_history.dart';
part 'widgets/library_common.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}
