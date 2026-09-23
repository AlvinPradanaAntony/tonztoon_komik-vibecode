import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source_info.dart';
import '../repositories/providers.dart';
import 'app_snackbar.dart';

/// Source filter options shared by search and catalog filter sheets.
///
/// Both screens read the catalog's cached sources for the filter sheet and
/// refresh them on demand with identical error-snackbar handling.

/// Cached source labels for the filter sheet (empty list while none cached yet).
List<String> cachedSourceOptionNames(WidgetRef ref) {
  return _sourceNames(ref.read(catalogRepositoryProvider).getCachedSources());
}

Future<List<String>>? _sourceWarmupFuture;

/// Warms the local source cache before a filter sheet is opened.
///
/// The repository returns cached sources immediately when available and only
/// fetches from the API when the local cache is empty. The shared in-flight
/// future keeps multiple callers from starting duplicate requests.
Future<List<String>> warmSourceOptionCache(WidgetRef ref) {
  final cached = cachedSourceOptionNames(ref);
  if (cached.isNotEmpty) return Future.value(cached);

  final inFlight = _sourceWarmupFuture;
  if (inFlight != null) return inFlight;

  final future = ref
      .read(catalogRepositoryProvider)
      .getSources()
      .then((sources) {
        ref.invalidate(sourcesProvider);
        return _sourceNames(sources);
      })
      .whenComplete(() => _sourceWarmupFuture = null);
  _sourceWarmupFuture = future;
  return future;
}

/// Refreshes sources from the API, invalidates [sourcesProvider], and returns the
/// updated labels. On failure, shows an error snackbar (guarded by
/// `context.mounted`) and returns an empty list. [logContext] labels the log.
Future<List<String>> refreshSourceOptionNames(
  WidgetRef ref,
  BuildContext context, {
  required String logContext,
}) async {
  try {
    final sources = await ref.read(catalogRepositoryProvider).refreshSources();
    ref.invalidate(sourcesProvider);
    return _sourceNames(sources);
  } catch (error, stackTrace) {
    if (context.mounted) {
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: logContext,
        fallbackMessage: 'Daftar sumber belum dapat dimuat.',
      );
    }
    return const [];
  }
}

List<String> _sourceNames(List<SourceInfo> sources) {
  return sources
      .where((source) => source.enabled)
      .map((source) => source.label.trim())
      .where((label) => label.isNotEmpty)
      .toList(growable: false);
}
