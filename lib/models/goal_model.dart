class GoalModel {
  final int? id;
  final int userId;
  final int sadhanaTypeId;
  final double targetValue;
  final String? unit;
  final bool isActive;
  final String createdAt;
  final String? updatedAt;

  const GoalModel({
    this.id,
    required this.userId,
    required this.sadhanaTypeId,
    required this.targetValue,
    this.unit,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'sadhana_type_id': sadhanaTypeId,
      'target_value': targetValue,
      'unit': unit,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory GoalModel.fromMap(Map<String, dynamic> map) {
    return GoalModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      sadhanaTypeId: map['sadhana_type_id'] as int,
      targetValue: (map['target_value'] as num).toDouble(),
      unit: map['unit'] as String?,
      isActive: map['is_active'] == 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
