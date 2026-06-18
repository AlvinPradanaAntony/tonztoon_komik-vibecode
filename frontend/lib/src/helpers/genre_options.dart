import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/comic.dart';
import '../repositories/providers.dart';
import 'app_snackbar.dart';

/// Genre filter options shared by the search and catalog filter sheets.
///
/// Both screens read the catalog's cached genres for the filter sheet and
/// refresh them on demand with identical error-snackbar handling — kept here
/// as a single source instead of duplicated per screen.

/// Cached genre names for the filter sheet (empty list while none cached yet).
List<String> cachedGenreOptionNames(WidgetRef ref) {
  return _genreNames(ref.read(catalogRepositoryProvider).getCachedGenres());
}

/// Refreshes genres from the API, invalidates [genresProvider], and returns the
/// updated names. On failure, shows an error snackbar (guarded by
/// `context.mounted`) and returns an empty list. [logContext] labels the log.
Future<List<String>> refreshGenreOptionNames(
  WidgetRef ref,
  BuildContext context, {
  required String logContext,
}) async {
  try {
    final genres = await ref.read(catalogRepositoryProvider).refreshGenres();
    ref.invalidate(genresProvider);
    return _genreNames(genres);
  } catch (error, stackTrace) {
    if (context.mounted) {
      showAppErrorSnackBar(
        context,
        error: error,
        stackTrace: stackTrace,
        logContext: logContext,
        fallbackMessage: 'Daftar genre belum dapat dimuat.',
      );
    }
    return const [];
  }
}

List<String> _genreNames(List<Genre> genres) {
  return genres
      .map((genre) => genre.name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
}
