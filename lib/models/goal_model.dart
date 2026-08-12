class GoalModel {
  final int? id;
  final int sadhanaTypeId;
  final double targetValue;
  final String period;
  final String createdAt;

  GoalModel({
    this.id,
    required this.sadhanaTypeId,
    required this.targetValue,
    required this.period,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sadhana_type_id': sadhanaTypeId,
      'target_value': targetValue,
      'period': period,
      'created_at': createdAt,
    };
  }

  factory GoalModel.fromMap(Map<String, dynamic> map) {
    return GoalModel(
      id: map['id'],
      sadhanaTypeId: map['sadhana_type_id'],
      targetValue: (map['target_value'] as num).toDouble(),
      period: map['period'],
      createdAt: map['created_at'],
    );
  }
}
