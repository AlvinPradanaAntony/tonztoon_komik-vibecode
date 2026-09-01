import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/app_icons.dart';
import '../../helpers/app_snackbar.dart';
import '../../helpers/navigation_helpers.dart';
import '../../core/reader_image_cache.dart';
import '../../models/comic.dart';
import '../../models/library.dart';
import '../../models/progress.dart';
import '../../repositories/providers.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/comic_cover.dart';

part 'state/reader_screen_state.dart';
part 'models/reader_models.dart';
part 'helpers/reader_helpers.dart';
part 'widgets/reader_scaffolds.dart';
part 'widgets/reader_viewport_fades.dart';
part 'widgets/vertical_reader.dart';
part 'widgets/paged_reader.dart';
part 'widgets/preparing_chapter_view.dart';
part 'widgets/reader_bars.dart';
part 'widgets/reader_error.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  ReaderScreen({
    super.key,
    String? comicTitle,
    String? chapterTitle,
    ComicSummary? comic,
    String? sourceName,
    String? slug,
    double? chapterNumber,
    ComicSummary? initialComic,
  }) : comic = initialComic ?? comic,
       sourceName = sourceName ?? comic?.sourceName ?? 'komiku',
       slug = slug ?? comic?.slug ?? '',
       chapterNumber = chapterNumber ?? 1,
       comicTitle =
           comicTitle ?? initialComic?.title ?? comic?.title ?? 'Komik',
       chapterTitle =
           chapterTitle ??
           'Chapter ${chapterNumber == null ? 1 : formatChapterNumber(chapterNumber)}';

  final String sourceName;
  final String slug;
  final double chapterNumber;
  final String comicTitle;
  final String chapterTitle;
  final ComicSummary? comic;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}
