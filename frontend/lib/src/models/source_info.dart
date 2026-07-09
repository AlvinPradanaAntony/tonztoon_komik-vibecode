class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.enabled,
    required this.dbComicCount,
    required this.isUnstable,
  });

  factory SourceInfo.fromJson(Map<String, dynamic> json) {
    return SourceInfo(
      id: json['id'] as String,
      label: json['label'] as String? ?? json['id'] as String,
      baseUrl: json['base_url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      dbComicCount: json['db_comic_count'] as int? ?? 0,
      isUnstable: json['is_unstable'] as bool? ?? false,
    );
  }

  final String id;
  final String label;
  final String baseUrl;
  final bool enabled;
  final int dbComicCount;
  final bool isUnstable;
}
