class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.kind,
    required this.createdAt,
    this.actionRoute,
    this.unread = true,
  });

  factory AppNotification.fromJson(Map<dynamic, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      category: json['category'] as String? ?? 'Pustaka',
      kind: json['kind'] as String? ?? 'library',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      actionRoute: json['action_route'] as String?,
      unread: json['unread'] as bool? ?? true,
    );
  }

  final String id;
  final String title;
  final String message;
  final String category;
  final String kind;
  final DateTime createdAt;
  final String? actionRoute;
  final bool unread;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'category': category,
    'kind': kind,
    'created_at': createdAt.toIso8601String(),
    'action_route': actionRoute,
    'unread': unread,
  };

  AppNotification copyWith({
    String? title,
    String? message,
    String? category,
    String? kind,
    DateTime? createdAt,
    String? actionRoute,
    bool? unread,
  }) {
    return AppNotification(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      category: category ?? this.category,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      actionRoute: actionRoute ?? this.actionRoute,
      unread: unread ?? this.unread,
    );
  }
}
