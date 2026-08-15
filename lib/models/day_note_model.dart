class DayNoteModel {
  final int? id;
  final int userId;
  final String date;

  final bool isStarred;
  final bool isSankirtan;
  final bool isEkadashi;
  final bool isFestival;

  final String? note;
  final String createdAt;
  final String? updatedAt;

  const DayNoteModel({
    this.id,
    required this.userId,
    required this.date,
    this.isStarred = false,
    this.isSankirtan = false,
    this.isEkadashi = false,
    this.isFestival = false,
    this.note,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'date': date,

      'is_starred': isStarred ? 1 : 0,
      'is_sankirtan': isSankirtan ? 1 : 0,
      'is_ekadashi': isEkadashi ? 1 : 0,
      'is_festival': isFestival ? 1 : 0,

      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory DayNoteModel.fromMap(Map<String, dynamic> map) {
    return DayNoteModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      date: map['date'] as String,

      isStarred: map['is_starred'] == 1,
      isSankirtan: map['is_sankirtan'] == 1,
      isEkadashi: map['is_ekadashi'] == 1,
      isFestival: map['is_festival'] == 1,

      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
