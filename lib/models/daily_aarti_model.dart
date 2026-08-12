class DailyAartiModel {
  final int? id;
  final int userId;
  final int aartiTypeId;
  final String date;
  final String createdAt;

  const DailyAartiModel({
    this.id,
    required this.userId,
    required this.aartiTypeId,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'aarti_type_id': aartiTypeId,
      'date': date,
      'created_at': createdAt,
    };
  }

  factory DailyAartiModel.fromMap(Map<String, dynamic> map) {
    return DailyAartiModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      aartiTypeId: map['aarti_type_id'] as int,
      date: map['date'] as String,
      createdAt: map['created_at'] as String,
    );
  }
}
