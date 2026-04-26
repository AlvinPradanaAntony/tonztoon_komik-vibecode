import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ReaderImageCacheManager {
  static const key = 'tonztoonReaderImages';

  static final CacheManager instance = CacheManager(
    Config(key, stalePeriod: const Duration(days: 1), maxNrOfCacheObjects: 800),
  );
}
