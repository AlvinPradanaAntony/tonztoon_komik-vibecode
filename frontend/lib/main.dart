import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/app.dart';
import 'src/core/storage.dart';

export 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox<dynamic>(HiveBoxes.settings),
    Hive.openBox<dynamic>(HiveBoxes.auth),
    Hive.openBox<dynamic>(HiveBoxes.progress),
    Hive.openBox<dynamic>(HiveBoxes.library),
    Hive.openBox<dynamic>(HiveBoxes.cache),
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    const ProviderScope(retry: _disableProviderRetry, child: TonztoonApp()),
  );
}

Duration? _disableProviderRetry(int retryCount, Object error) => null;
