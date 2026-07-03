part of '../comic_detail_screen.dart';

Set<double> _parseChapterSelection(
  String input,
  List<ChapterListItem> availableChapters,
) {
  final normalized = input.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Masukkan range atau nomor chapter.');
  }

  final chunks = normalized
      .split(RegExp(r'[,;\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .expand((item) {
        if (item.contains('-') || item.contains('–') || item.contains('—')) {
          return [item];
        }
        return item.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
      });
  final selected = <double>{};

  for (final chunk in chunks) {
    final rangeParts = chunk
        .split(RegExp(r'\s*[-–—]\s*'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (rangeParts.length == 2) {
      final start = _parseChapterInputNumber(rangeParts.first);
      final end = _parseChapterInputNumber(rangeParts.last);
      if (start == null || end == null) {
        throw FormatException('Range "$chunk" tidak valid.');
      }
      final min = start < end ? start : end;
      final max = start > end ? start : end;
      final matches = availableChapters
          .where(
            (chapter) =>
                chapter.chapterNumber >= min && chapter.chapterNumber <= max,
          )
          .map((chapter) => chapter.chapterNumber)
          .toList();
      if (matches.isEmpty) {
        throw FormatException(
          'Tidak ada chapter tersedia untuk range "$chunk".',
        );
      }
      selected.addAll(matches);
      continue;
    }
    if (rangeParts.length > 2) {
      throw FormatException('Range "$chunk" tidak valid.');
    }

    final number = _parseChapterInputNumber(chunk);
    if (number == null) {
      throw FormatException('Chapter "$chunk" tidak valid.');
    }
    final exists = availableChapters.any(
      (chapter) => chapter.chapterNumber == number,
    );
    if (!exists) {
      throw FormatException(
        'Chapter ${formatChapterNumber(number)} tidak tersedia.',
      );
    }
    selected.add(number);
  }

  if (selected.isEmpty) {
    throw const FormatException('Tidak ada chapter yang cocok.');
  }
  return selected;
}

double? _parseChapterInputNumber(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.'));
}

_ChapterReadState _chapterReadState(
  _ChapterUi chapter,
  ReadingProgress? progress,
  Set<double> completedChapterNumbers,
) {
  if (completedChapterNumbers.contains(chapter.chapterNumber)) {
    return _ChapterReadState.completed;
  }
  if (progress == null || progress.chapterNumber != chapter.chapterNumber) {
    return _ChapterReadState.none;
  }
  return progress.isCompleted
      ? _ChapterReadState.completed
      : _ChapterReadState.current;
}

String _comicKey(String sourceName, String slug) => '$sourceName|$slug';

double _readingProgressFraction(ReadingProgress? progress) {
  if (progress == null) return 0;
  if (progress.isCompleted) return 1;
  final total = progress.totalPageItems;
  if (total == null || total <= 0) return 0;
  final currentIndex =
      progress.lastReadPageItemIndex ?? progress.pageIndex ?? 0;
  return ((currentIndex + 1) / total).clamp(0, 1).toDouble();
}

_ChapterUi? _continueChapter(
  _ComicDetailUi detail,
  ReadingProgress? progress,
  Set<double> completedChapterNumbers,
) {
  if (detail.chapters.isEmpty) return null;

  final maxCompleted = completedChapterNumbers.isEmpty
      ? -1.0
      : completedChapterNumbers.reduce((a, b) => a > b ? a : b);
  final progressChapter = progress?.chapterNumber;
  final progressCompleted = progress?.isCompleted ?? false;

  double? targetChapterNumber;

  if (progressChapter != null &&
      !progressCompleted &&
      !completedChapterNumbers.contains(progressChapter)) {
    targetChapterNumber = progressChapter;
  } else {
    final lastRead = (progressChapter != null && progressChapter > maxCompleted)
        ? progressChapter
        : maxCompleted;

    if (lastRead == -1.0) {
      return detail.chapters.reduce(
        (earliest, chapter) =>
            chapter.chapterNumber < earliest.chapterNumber ? chapter : earliest,
      );
    }

    final ascendingChapters = detail.chapters.toList()
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

    for (final chapter in ascendingChapters) {
      if (chapter.chapterNumber > lastRead) {
        targetChapterNumber = chapter.chapterNumber;
        break;
      }
    }

    if (targetChapterNumber == null) {
      return ascendingChapters.last;
    }
  }

  for (final chapter in detail.chapters) {
    if (chapter.chapterNumber == targetChapterNumber) return chapter;
  }

  return _ChapterUi(
    title: 'Chapter ${formatChapterNumber(targetChapterNumber)}',
    subtitle: 'Lanjutkan bacaan terakhir',
    chapterNumber: targetChapterNumber,
  );
}

Future<void> _openReader(
  BuildContext context,
  _ComicDetailUi detail,
  _ChapterUi chapter,
) {
  final comic = ComicSummary(
    title: detail.title,
    slug: detail.slug,
    sourceName: detail.sourceName,
    coverImageUrl: detail.coverImageUrl,
    type: detail.type,
  );
  return openReaderForComic(context, comic, chapter.chapterNumber);
}

String _sourceLabel(String sourceName) => comicSourceNameLabel(sourceName);

String _relativeDateLabel(DateTime date) {
  final now = DateTime.now();
  final localDate = date.toLocal();
  final difference = now.difference(localDate);
  if (difference.inDays <= 0) return 'Hari ini';
  if (difference.inDays == 1) return 'Kemarin';
  if (difference.inDays < 7) return '${difference.inDays} hari lalu';
  if (difference.inDays < 30) {
    return '${(difference.inDays / 7).floor()} minggu lalu';
  }
  return _absoluteDateLabel(localDate);
}

String _absoluteDateLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
