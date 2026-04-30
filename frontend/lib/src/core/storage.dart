import 'package:hive/hive.dart';

class HiveBoxes {
  static const settings = 'settings';
  static const auth = 'auth';
  static const progress = 'progress';
  static const library = 'library';
  static const cache = 'cache';
}

class LocalStore {
  LocalStore({
    Box<dynamic>? settings,
    Box<dynamic>? auth,
    Box<dynamic>? progress,
    Box<dynamic>? library,
    Box<dynamic>? cache,
  }) : settings = settings ?? Hive.box<dynamic>(HiveBoxes.settings),
       auth = auth ?? Hive.box<dynamic>(HiveBoxes.auth),
       progress = progress ?? Hive.box<dynamic>(HiveBoxes.progress),
       library = library ?? Hive.box<dynamic>(HiveBoxes.library),
       cache = cache ?? Hive.box<dynamic>(HiveBoxes.cache);

  final Box<dynamic> settings;
  final Box<dynamic> auth;
  final Box<dynamic> progress;
  final Box<dynamic> library;
  final Box<dynamic> cache;
}
