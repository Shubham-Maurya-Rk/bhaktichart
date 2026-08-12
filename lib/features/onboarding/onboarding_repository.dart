import '../../core/database/database_helper.dart';
import '../../models/user_model.dart';

class OnboardingRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<int> saveUser(String name) async {
    final db = await _databaseHelper.database;

    final now = DateTime.now().toIso8601String();

    return await db.insert(
      'users',
      UserModel(name: name, createdAt: now).toMap(),
    );
  }

  Future<UserModel?> getUser() async {
    final db = await _databaseHelper.database;

    final result = await db.query('users', limit: 1);

    if (result.isEmpty) {
      return null;
    }

    return UserModel.fromMap(result.first);
  }
}
