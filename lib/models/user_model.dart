class UserModel {
  final int? id;
  final String name;
  final String createdAt;

  UserModel({this.id, required this.name, required this.createdAt});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'created_at': createdAt};
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'],
      createdAt: map['created_at'],
    );
  }
}
