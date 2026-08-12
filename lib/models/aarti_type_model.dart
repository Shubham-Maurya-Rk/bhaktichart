class AartiTypeModel {
  final int? id;
  final int userId;
  final String name;
  final bool isActive;
  final int sortOrder;
  final String createdAt;
  final String? updatedAt;

  const AartiTypeModel({
    this.id,
    required this.userId,
    required this.name,
    this.isActive = true,
    this.sortOrder = 0,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory AartiTypeModel.fromMap(Map<String, dynamic> map) {
    return AartiTypeModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      name: map['name'] as String,
      isActive: map['is_active'] == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
