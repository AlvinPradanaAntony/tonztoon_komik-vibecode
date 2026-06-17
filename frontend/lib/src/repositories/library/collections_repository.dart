part of '../library_repository.dart';

/// Collections (user-curated lists of comics): CRUD plus comic membership.
extension LibraryCollections on LibraryRepository {
  Future<List<CollectionSummary>> getCollections() async {
    if (await _isLoggedIn) {
      final response = await _api.get<List<dynamic>>('/library/collections');
      return (response.data ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CollectionSummary.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
    return _localCollections()
        .map(
          (collection) => CollectionSummary(
            id: collection.id,
            name: collection.name,
            totalItems: collection.items.length,
          ),
        )
        .toList();
  }

  Future<CollectionDetail> getCollectionDetail(int collectionId) async {
    if (await _isLoggedIn) {
      final response = await _api.get<Map<String, dynamic>>(
        '/library/collections/$collectionId',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collection = _localCollections()
        .where((item) => item.id == collectionId)
        .firstOrNull;
    if (collection == null) {
      throw ApiException('Collection not found.');
    }
    return collection;
  }

  Future<CollectionDetail> createCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Collection name cannot be empty.');
    }
    if (await _isLoggedIn) {
      final response = await _api.post<Map<String, dynamic>>(
        '/library/collections',
        data: {'name': trimmed},
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    if (collections.any(
      (item) => item.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw ApiException('Collection name already exists.');
    }
    final nextId = collections.isEmpty
        ? 1
        : collections.map((item) => item.id).reduce((a, b) => a > b ? a : b) +
              1;
    final created = CollectionDetail(
      id: nextId,
      name: trimmed,
      totalItems: 0,
      items: const [],
    );
    collections.add(created);
    await _saveLocalCollections(collections);
    return created;
  }

  Future<CollectionDetail> renameCollection(
    int collectionId,
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Collection name cannot be empty.');
    }
    if (await _isLoggedIn) {
      final response = await _api.patch<Map<String, dynamic>>(
        '/library/collections/$collectionId',
        data: {'name': trimmed},
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    if (collections.any(
      (item) =>
          item.id != collectionId &&
          item.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      throw ApiException('Collection name already exists.');
    }
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final updated = CollectionDetail(
      id: current.id,
      name: trimmed,
      totalItems: current.items.length,
      items: current.items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }

  Future<void> deleteCollection(int collectionId) async {
    if (await _isLoggedIn) {
      await _api.delete<Map<String, dynamic>>(
        '/library/collections/$collectionId',
      );
      return;
    }

    final collections = _localCollections()
        .where((collection) => collection.id != collectionId)
        .toList();
    await _saveLocalCollections(collections);
  }

  Future<void> setComicCollections(
    ComicSummary comic,
    Set<int> selectedCollectionIds,
  ) async {
    if (await _isLoggedIn) {
      final current = await getComicState(comic);
      final currentIds = current.collections.map((item) => item.id).toSet();
      for (final id in selectedCollectionIds.difference(currentIds)) {
        await _api.put<Map<String, dynamic>>(
          '/library/collections/$id/comics/${comic.sourceName}/${comic.slug}',
        );
      }
      for (final id in currentIds.difference(selectedCollectionIds)) {
        await _api.delete<Map<String, dynamic>>(
          '/library/collections/$id/comics/${comic.sourceName}/${comic.slug}',
        );
      }
      return;
    }

    final collections = _localCollections();
    final ref = LibraryComicRef.fromSummary(comic);
    final updated = collections.map((collection) {
      final items = collection.items
          .where((item) => item.key != comic.key)
          .toList();
      if (selectedCollectionIds.contains(collection.id)) {
        items.add(ref);
      }
      return CollectionDetail(
        id: collection.id,
        name: collection.name,
        totalItems: items.length,
        items: items,
      );
    }).toList();
    await _saveLocalCollections(updated);
  }

  Future<CollectionDetail> addComicToCollection(
    int collectionId,
    ComicSummary comic,
  ) async {
    if (await _isLoggedIn) {
      final response = await _api.put<Map<String, dynamic>>(
        '/library/collections/$collectionId/comics/${comic.sourceName}/${comic.slug}',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final items = current.items.where((item) => item.key != comic.key).toList()
      ..add(LibraryComicRef.fromSummary(comic));
    final updated = CollectionDetail(
      id: current.id,
      name: current.name,
      totalItems: items.length,
      items: items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }

  Future<CollectionDetail> removeComicFromCollection(
    int collectionId,
    ComicSummary comic,
  ) async {
    if (await _isLoggedIn) {
      final response = await _api.delete<Map<String, dynamic>>(
        '/library/collections/$collectionId/comics/${comic.sourceName}/${comic.slug}',
      );
      return CollectionDetail.fromJson(response.data ?? const {});
    }

    final collections = _localCollections();
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index < 0) {
      throw ApiException('Collection not found.');
    }
    final current = collections[index];
    final items = current.items.where((item) => item.key != comic.key).toList();
    final updated = CollectionDetail(
      id: current.id,
      name: current.name,
      totalItems: items.length,
      items: items,
    );
    collections[index] = updated;
    await _saveLocalCollections(collections);
    return updated;
  }
}
