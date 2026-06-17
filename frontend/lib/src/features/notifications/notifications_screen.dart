import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/app_error.dart';
import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../models/app_notification.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_edge_fade.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/tonztoon_modal_dialog.dart';

part 'state/notifications_screen_state.dart';
part 'widgets/notifications_widgets.dart';
part 'widgets/notifications_states.dart';
part 'helpers/notifications_helpers.dart';
part 'models/notifications_models.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}
