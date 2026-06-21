import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../utils/app_assets.dart';
import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../helpers/navigation_helpers.dart';
import 'section/comic_section_screen.dart';
import 'section/continue_reading_section_screen.dart';
import '../../models/auth.dart';
import '../../models/comic.dart';
import '../../models/progress.dart';
import '../../models/source_info.dart';
import '../../repositories/providers.dart';
import '../../widgets/animated_notification_bell.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/comic_cover.dart';
import '../../widgets/comic_filter_sort_sheet.dart';
import '../../widgets/guest_migration_dialog.dart';
import '../../widgets/helpdesk_dialog.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import '../../widgets/tonztoon_dropdown.dart';
import 'widgets/continue_reading_progress_card.dart';

part 'state/home_screen_state.dart';
part 'helpers/home_helpers.dart';
part 'widgets/home_app_bar.dart';
part 'widgets/home_shimmers.dart';
part 'widgets/home_sections.dart';
part 'widgets/home_top_ranking.dart';
part 'widgets/home_recommendation.dart';

/// [HomeScreen] adalah halaman beranda aplikasi komik.
/// Menampilkan rekomendasi dan update terbaru.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}
