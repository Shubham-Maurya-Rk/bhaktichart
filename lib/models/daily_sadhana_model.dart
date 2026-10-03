class DailySadhanaModel {
  final int? id;
  final int userId;
  final String date;
  final int sadhanaTypeId;

  // ==========================================================
  // EXISTING GENERIC SADHANA VALUE
  // ==========================================================
  //
  // Keep these fields for Chanting, Hearing, Aarti, etc.
  //
  // They will also remain temporarily for Reading so that
  // existing code does not break during this migration.
  // ==========================================================

  final double value;
  final String? unit;

  // ==========================================================
  // READING VALUES
  // ==========================================================
  //
  // These are used only when the Sadhana type is Reading.
  //
  // All three can be stored simultaneously.
  //
  // Example:
  //
  // readingPages   = 10
  // readingVerses  = 25
  // readingMinutes = 35
  //
  // Nullable is intentional:
  //
  // null = user did not record that measurement
  // 0    = user explicitly recorded zero
  // ==========================================================

  final double? readingPages;
  final double? readingVerses;
  final double? readingMinutes;

  // ==========================================================
  // TIMESTAMPS
  // ==========================================================

  final String createdAt;
  final String? updatedAt;

  // ==========================================================
  // CONSTRUCTOR
  // ==========================================================

  const DailySadhanaModel({
    this.id,
    required this.userId,
    required this.date,
    required this.sadhanaTypeId,

    required this.value,
    this.unit,

    this.readingPages,
    this.readingVerses,
    this.readingMinutes,

    required this.createdAt,
    this.updatedAt,
  });

  // ==========================================================
  // TO MAP
  // ==========================================================

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'date': date,
      'sadhana_type_id': sadhanaTypeId,

      // Existing generic fields
      'value': value,
      'unit': unit,

      // Reading fields
      'reading_pages': readingPages,
      'reading_verses': readingVerses,
      'reading_minutes': readingMinutes,

      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  // ==========================================================
  // FROM MAP
  // ==========================================================

  factory DailySadhanaModel.fromMap(Map<String, dynamic> map) {
    return DailySadhanaModel(
      id: map['id'] as int?,

      userId: map['user_id'] as int,

      date: map['date'] as String,

      sadhanaTypeId: map['sadhana_type_id'] as int,

      // Existing generic fields
      value: (map['value'] as num?)?.toDouble() ?? 0.0,

      unit: map['unit'] as String?,

      // Reading fields
      readingPages: (map['reading_pages'] as num?)?.toDouble(),

      readingVerses: (map['reading_verses'] as num?)?.toDouble(),

      readingMinutes: (map['reading_minutes'] as num?)?.toDouble(),

      createdAt: map['created_at'] as String,

      updatedAt: map['updated_at'] as String?,
    );
  }
}
