class LearningBook {
  final int? id;
  final int userId;
  final String name;
  final int levelCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const LearningBook({
    this.id,
    required this.userId,
    required this.name,
    required this.levelCount,
    required this.createdAt,
    this.updatedAt,
  });

  factory LearningBook.fromMap(Map<String, dynamic> map) {
    return LearningBook(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      name: map['name'] as String,
      levelCount: map['level_count'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'level_count': levelCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  LearningBook copyWith({
    int? id,
    int? userId,
    String? name,
    int? levelCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LearningBook(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      levelCount: levelCount ?? this.levelCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
