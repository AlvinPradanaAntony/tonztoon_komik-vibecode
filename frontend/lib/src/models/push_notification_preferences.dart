class PushNotificationPreferences {
  const PushNotificationPreferences({this.enabled = false});

  factory PushNotificationPreferences.fromJson(Map<dynamic, dynamic> json) {
    return PushNotificationPreferences(
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  final bool enabled;

  bool get shouldDeliver => enabled;

  Map<String, dynamic> toJson() => {'enabled': enabled};

  PushNotificationPreferences copyWith({bool? enabled}) {
    return PushNotificationPreferences(enabled: enabled ?? this.enabled);
  }
}
