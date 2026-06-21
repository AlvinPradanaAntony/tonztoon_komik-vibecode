import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../utils/app_error.dart';
import '../../helpers/app_snackbar.dart';
import '../../core/avatar_image.dart';
import '../../routing/library_routes.dart';
import '../../helpers/app_icons.dart';
import '../../models/auth.dart';
import '../../models/library.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_async_view.dart';
import '../../widgets/app_loading_placeholder.dart';
import '../../widgets/guest_migration_dialog.dart';
import '../../widgets/helpdesk_dialog.dart';
import '../../widgets/app_update_dialog.dart';
import '../../widgets/tonztoon_modal_dialog.dart';
import '../library/library_shared_panes.dart';

part 'state/settings_screen_state.dart';
part 'models/settings_models.dart';
part 'helpers/settings_helpers.dart';
part 'dialogs/settings_dialogs.dart';
part 'screens/settings_subscreens.dart';
part 'widgets/settings_profile.dart';
part 'widgets/settings_rows.dart';
part 'widgets/settings_sections.dart';
part 'widgets/settings_shimmers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.isSignedIn,
    required this.onOpenAuth,
    required this.onLogout,
  });

  final bool isSignedIn;
  final VoidCallback onOpenAuth;
  final Future<void> Function() onLogout;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}
