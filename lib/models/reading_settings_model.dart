class ReadingSettingsModel {
  final int? id;
  final int userId;
  final String unit;
  final String updatedAt;

  const ReadingSettingsModel({
    this.id,
    required this.userId,
    required this.unit,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'user_id': userId, 'unit': unit, 'updated_at': updatedAt};
  }

  factory ReadingSettingsModel.fromMap(Map<String, dynamic> map) {
    return ReadingSettingsModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      unit: map['unit'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }
}
