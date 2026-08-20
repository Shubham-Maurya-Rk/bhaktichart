import 'dart:convert';

class SadhanaReminder {
  final int id;
  final int sadhanaTypeId;
  final String title;
  final String icon;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final bool enabled;
  final String? customMessage;

  const SadhanaReminder({
    required this.id,
    required this.sadhanaTypeId,
    required this.title,
    required this.icon,
    required this.hour,
    required this.minute,
    required this.weekdays,
    this.enabled = true,
    this.customMessage,
  });

  SadhanaReminder copyWith({
    int? id,
    int? sadhanaTypeId,
    String? title,
    String? icon,
    int? hour,
    int? minute,
    List<int>? weekdays,
    bool? enabled,
    String? customMessage,
  }) {
    return SadhanaReminder(
      id: id ?? this.id,
      sadhanaTypeId: sadhanaTypeId ?? this.sadhanaTypeId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? List<int>.from(this.weekdays),
      enabled: enabled ?? this.enabled,
      customMessage: customMessage ?? this.customMessage,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sadhanaTypeId': sadhanaTypeId,
    'title': title,
    'icon': icon,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'enabled': enabled,
    'customMessage': customMessage,
  };

  factory SadhanaReminder.fromMap(Map<String, dynamic> map) {
    return SadhanaReminder(
      id: (map['id'] as num).toInt(),
      sadhanaTypeId: (map['sadhanaTypeId'] as num).toInt(),
      title: map['title'] as String? ?? 'Sadhana',
      icon: map['icon'] as String? ?? '🙏',
      hour: (map['hour'] as num).toInt(),
      minute: (map['minute'] as num).toInt(),
      weekdays: (map['weekdays'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      enabled: map['enabled'] as bool? ?? true,
      customMessage: map['customMessage'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SadhanaReminder.fromJson(String value) =>
      SadhanaReminder.fromMap(jsonDecode(value) as Map<String, dynamic>);
}
