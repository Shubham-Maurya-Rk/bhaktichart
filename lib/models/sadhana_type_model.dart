class SadhanaTypeModel {
  final int? id;
  final String name;
  final String icon;
  final String unit;
  final bool isActive;

  SadhanaTypeModel({
    this.id,
    required this.name,
    required this.icon,
    required this.unit,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'unit': unit,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory SadhanaTypeModel.fromMap(Map<String, dynamic> map) {
    return SadhanaTypeModel(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
      unit: map['unit'],
      isActive: map['is_active'] == 1,
    );
  }
}
