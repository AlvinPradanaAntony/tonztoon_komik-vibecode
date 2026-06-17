part of '../providers.dart';

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
    );

final homeHelpdeskButtonVisibleProvider =
    NotifierProvider<HomeHelpdeskButtonVisibleController, bool>(
      HomeHelpdeskButtonVisibleController.new,
    );

class HomeHelpdeskButtonVisibleController extends Notifier<bool> {
  static const _storageKey = 'home_helpdesk_button_visible';

  @override
  bool build() {
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    return value is bool ? value : true;
  }

  Future<void> setVisible(bool value) async {
    final previous = state;
    state = value;
    try {
      await ref.read(localStoreProvider).settings.put(_storageKey, value);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final readingTimeProvider = NotifierProvider<ReadingTimeController, Duration>(
  ReadingTimeController.new,
);

class ReadingTimeController extends Notifier<Duration> {
  static const _storageKeyPrefix = 'reading_time_total_seconds';
  late String _storageKey;
  late String _pendingDeltaKey;
  bool _syncing = false;

  @override
  Duration build() {
    final auth = ref.watch(authControllerProvider);
    _storageKey = _storageKeyForAuth(auth);
    _pendingDeltaKey = '${_storageKey}_pending_delta';
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    final seconds = switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    if (auth.isAuthenticated) {
      unawaited(_syncCloudReadingTime());
    }
    return Duration(seconds: seconds);
  }

  Future<void> add(Duration duration) async {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return;

    final next = state + Duration(seconds: seconds);
    await _setLocalSeconds(next.inSeconds);

    if (ref.read(authControllerProvider).isAuthenticated) {
      await _addPendingDelta(seconds);
      unawaited(_syncCloudReadingTime());
    }
  }

  Future<void> refreshFromCloud() {
    return _syncCloudReadingTime();
  }

  Future<void> _syncCloudReadingTime() async {
    if (_syncing || !ref.read(authControllerProvider).isAuthenticated) return;
    _syncing = true;
    var shouldSyncAgain = false;
    final storageKey = _storageKey;
    final pendingDeltaKey = _pendingDeltaKey;
    try {
      final pending = _readSeconds(
        ref.read(localStoreProvider).settings.get(pendingDeltaKey),
      );
      final repository = ref.read(libraryRepositoryProvider);
      final remoteSeconds = pending > 0
          ? await repository.addReadingTimeDeltaSeconds(pending)
          : await repository.getReadingTimeSeconds();
      if (remoteSeconds == null) return;
      if (pending > 0) {
        final latestPending = _readSeconds(
          ref.read(localStoreProvider).settings.get(pendingDeltaKey),
        );
        final unsent = latestPending > pending ? latestPending - pending : 0;
        if (unsent > 0) {
          await ref
              .read(localStoreProvider)
              .settings
              .put(pendingDeltaKey, unsent);
          shouldSyncAgain = true;
        } else {
          await ref.read(localStoreProvider).settings.delete(pendingDeltaKey);
        }
        await _setLocalSeconds(remoteSeconds + unsent, storageKey: storageKey);
      } else {
        await _setLocalSeconds(remoteSeconds, storageKey: storageKey);
      }
    } finally {
      _syncing = false;
    }
    if (shouldSyncAgain && storageKey == _storageKey) {
      unawaited(_syncCloudReadingTime());
    }
  }

  Future<void> _setLocalSeconds(int seconds, {String? storageKey}) async {
    final key = storageKey ?? _storageKey;
    if (key == _storageKey) {
      state = Duration(seconds: seconds);
    }
    await ref.read(localStoreProvider).settings.put(key, seconds);
  }

  Future<void> _addPendingDelta(int seconds) async {
    final current = _readSeconds(
      ref.read(localStoreProvider).settings.get(_pendingDeltaKey),
    );
    await ref
        .read(localStoreProvider)
        .settings
        .put(_pendingDeltaKey, current + seconds);
  }

  int _readSeconds(Object? value) {
    return switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
  }

  String _storageKeyForAuth(AuthState auth) {
    final user = auth.user;
    if (!auth.isAuthenticated || user == null) {
      return '${_storageKeyPrefix}_guest';
    }

    final id = user.id.trim();
    if (id.isNotEmpty) return '${_storageKeyPrefix}_user_$id';

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      return '${_storageKeyPrefix}_user_$email';
    }

    return '${_storageKeyPrefix}_guest';
  }
}

class AppThemeModeController extends Notifier<ThemeMode> {
  static const _storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final value = ref.watch(localStoreProvider).settings.get(_storageKey);
    return _themeModeFromName(value is String ? value : null);
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(localStoreProvider).settings.put(_storageKey, mode.name);
    state = mode;
  }

  static ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

final readerPreferencesProvider =
    AsyncNotifierProvider<ReaderPreferencesController, ReaderPreferences>(
      ReaderPreferencesController.new,
    );

class ReaderPreferencesController extends AsyncNotifier<ReaderPreferences> {
  int _saveSerial = 0;

  @override
  Future<ReaderPreferences> build() {
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    return ref.watch(libraryRepositoryProvider).getReaderPreferences();
  }

  Future<void> save(ReaderPreferences prefs) async {
    final serial = ++_saveSerial;
    final previous = state.asData?.value;
    state = AsyncData(prefs);

    try {
      final saved = await ref
          .read(libraryRepositoryProvider)
          .saveReaderPreferences(prefs);
      if (serial == _saveSerial) {
        state = AsyncData(saved);
      }
    } catch (error, stackTrace) {
      if (serial == _saveSerial) {
        state = previous == null
            ? AsyncError(error, stackTrace)
            : AsyncData(previous);
      }
      rethrow;
    }
  }
}
