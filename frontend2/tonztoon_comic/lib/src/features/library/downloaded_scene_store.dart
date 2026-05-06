import 'package:flutter/foundation.dart';

import '../../models/comic.dart';

class DownloadedSceneItem {
  const DownloadedSceneItem({
    required this.comic,
    required this.chapterTitle,
    required this.pageNumber,
    required this.label,
    required this.downloadedAt,
    this.imageUrl,
  });

  final ComicSummary comic;
  final String chapterTitle;
  final int pageNumber;
  final String label;
  final DateTime downloadedAt;
  final String? imageUrl;

  String get id => '${comic.title}|$chapterTitle|$pageNumber';
}

final downloadedSceneStore = ValueNotifier<List<DownloadedSceneItem>>(const []);

void saveDownloadedScene(DownloadedSceneItem scene) {
  final current = downloadedSceneStore.value;
  final existingIndex = current.indexWhere((item) => item.id == scene.id);

  if (existingIndex == -1) {
    downloadedSceneStore.value = [scene, ...current];
    return;
  }

  final next = [...current];
  next[existingIndex] = scene;
  downloadedSceneStore.value = next;
}
