import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/app.dart';
import 'src/core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox<dynamic>(HiveBoxes.settings),
    Hive.openBox<dynamic>(HiveBoxes.auth),
    Hive.openBox<dynamic>(HiveBoxes.progress),
    Hive.openBox<dynamic>(HiveBoxes.cache),
  ]);

  runApp(const ProviderScope(child: TonztoonApp()));
}
