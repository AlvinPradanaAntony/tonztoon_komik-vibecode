import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../utils/app_assets.dart';
import '../../utils/app_error.dart';
import '../../core/api_client.dart';
import '../../helpers/app_icons.dart';
import '../../repositories/providers.dart';
import '../../widgets/tonztoon_modal_dialog.dart';

part 'state/auth_screen_state.dart';
part 'screens/forgot_password_screen.dart';
part 'screens/reset_password_screen.dart';
part 'screens/auth_callback_screen.dart';
part 'models/auth_models.dart';
part 'helpers/auth_helpers.dart';
part 'dialogs/auth_dialogs.dart';
part 'widgets/auth_login_widgets.dart';
part 'widgets/forgot_password_widgets.dart';
part 'widgets/reset_password_widgets.dart';
part 'widgets/auth_flow_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}
