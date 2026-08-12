class DailySadhanaModel {
  final int? id;
  final String date;
  final int sadhanaTypeId;
  final double value;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  DailySadhanaModel({
    this.id,
    required this.date,
    required this.sadhanaTypeId,
    required this.value,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'sadhana_type_id': sadhanaTypeId,
      'value': value,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory DailySadhanaModel.fromMap(Map<String, dynamic> map) {
    return DailySadhanaModel(
      id: map['id'],
      date: map['date'],
      sadhanaTypeId: map['sadhana_type_id'],
      value: (map['value'] as num).toDouble(),
      notes: map['notes'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
    );
  }
}
