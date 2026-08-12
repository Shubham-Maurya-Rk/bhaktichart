import 'package:sqflite/sqflite.dart';
import '../models/user_model.dart';
import '../core/database/database_helper.dart';
import '../models/aarti_type_model.dart';
import '../models/daily_aarti_model.dart';
import '../models/daily_sadhana_model.dart';
import '../models/day_note_model.dart';
import '../models/goal_model.dart';
import '../models/reading_settings_model.dart';
import '../models/sadhana_type_model.dart';

class SadhanaRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<Database> get _db => _databaseHelper.database;

  Future<void> createDefaultGoals(int userId) async {
    final db = await _db;

    final now = DateTime.now().toIso8601String();

    // Get the active Sadhana types
    final types = await db.query(
      'sadhana_types',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'sort_order ASC',
    );

    for (final type in types) {
      final typeId = type['id'] as int;
      final name = (type['name'] as String).toLowerCase();

      String? unit;
      double? target;

      switch (name) {
        case 'chanting':
          target = 16;
          unit = 'rounds';
          break;

        case 'reading':
          target = 10;
          unit = 'pages';
          break;

        case 'hearing':
          target = 30;
          unit = 'minutes';
          break;

        case 'aarti':
          target = 1;
          unit = 'aartis';
          break;

        default:
          // Don't automatically create a goal
          // for unknown/custom Sadhana types.
          continue;
      }

      await db.insert('goals', {
        'user_id': userId,
        'sadhana_type_id': typeId,
        'target_value': target,
        'unit': unit,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> deleteGoal(int userId, int sadhanaTypeId) async {
    final db = await _db;

    await db.update(
      'goals',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: '''
      user_id = ?
      AND sadhana_type_id = ?
      AND is_active = ?
    ''',
      whereArgs: [userId, sadhanaTypeId, 1],
    );
  }

  Future<List<DailyAartiModel>> getAartiAttendanceForMonth(
    int userId,
    String startDate,
    String endDate,
  ) async {
    final db = await _db;

    final result = await db.query(
      'daily_aarti',
      where: '''
      user_id = ?
      AND date >= ?
      AND date <= ?
    ''',
      whereArgs: [userId, startDate, endDate],
      orderBy: 'date ASC',
    );

    return result.map((map) => DailyAartiModel.fromMap(map)).toList();
  }

  Future<UserModel?> getUser() async {
    final db = await _db;

    final result = await db.query('users', orderBy: 'id ASC', limit: 1);

    if (result.isEmpty) {
      return null;
    }

    return UserModel.fromMap(result.first);
  }

  Future<int> createUser(String name) async {
    final db = await _db;

    final now = DateTime.now().toIso8601String();

    final userId = await db.insert('users', {
      'name': name.trim(),
      'created_at': now,
    });

    await createDefaultGoals(userId);

    return userId;
  }
  // =====================================================
  // SADHANA TYPES
  // =====================================================

  Future<List<SadhanaTypeModel>> getSadhanaTypes() async {
    final db = await _db;

    final result = await db.query(
      'sadhana_types',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'sort_order ASC',
    );

    return result.map(SadhanaTypeModel.fromMap).toList();
  }

  // =====================================================
  // DAILY SADHANA
  // =====================================================

  Future<void> saveSadhana(DailySadhanaModel sadhana) async {
    final db = await _db;

    final existing = await db.query(
      'daily_sadhana',
      where: '''
        user_id = ?
        AND date = ?
        AND sadhana_type_id = ?
      ''',
      whereArgs: [sadhana.userId, sadhana.date, sadhana.sadhanaTypeId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('daily_sadhana', sadhana.toMap());
    } else {
      await db.update(
        'daily_sadhana',
        {
          'value': sadhana.value,
          'unit': sadhana.unit,
          'updated_at': sadhana.updatedAt,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<DailySadhanaModel?> getSadhana(
    int userId,
    String date,
    int sadhanaTypeId,
  ) async {
    final db = await _db;

    final result = await db.query(
      'daily_sadhana',
      where: '''
        user_id = ?
        AND date = ?
        AND sadhana_type_id = ?
      ''',
      whereArgs: [userId, date, sadhanaTypeId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return DailySadhanaModel.fromMap(result.first);
  }

  Future<List<DailySadhanaModel>> getSadhanaForMonth(
    int userId,
    String startDate,
    String endDate,
  ) async {
    final db = await _db;

    final result = await db.query(
      'daily_sadhana',
      where: '''
        user_id = ?
        AND date >= ?
        AND date <= ?
      ''',
      whereArgs: [userId, startDate, endDate],
      orderBy: 'date ASC',
    );

    return result.map(DailySadhanaModel.fromMap).toList();
  }

  // =====================================================
  // READING SETTINGS
  // =====================================================

  Future<ReadingSettingsModel?> getReadingSettings(int userId) async {
    final db = await _db;

    final result = await db.query(
      'reading_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return ReadingSettingsModel.fromMap(result.first);
  }

  Future<void> saveReadingUnit(int userId, String unit) async {
    final db = await _db;

    final now = DateTime.now().toIso8601String();

    await db.insert('reading_settings', {
      'user_id': userId,
      'unit': unit,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =====================================================
  // AARTI TYPES
  // =====================================================

  Future<List<AartiTypeModel>> getAartiTypes(int userId) async {
    final db = await _db;

    final result = await db.query(
      'aarti_types',
      where: '''
        user_id = ?
        AND is_active = ?
      ''',
      whereArgs: [userId, 1],
      orderBy: 'sort_order ASC',
    );

    return result.map(AartiTypeModel.fromMap).toList();
  }

  Future<int> addAarti(AartiTypeModel aarti) async {
    final db = await _db;

    return await db.insert('aarti_types', aarti.toMap());
  }

  Future<void> disableAarti(int aartiId) async {
    final db = await _db;

    await db.update(
      'aarti_types',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [aartiId],
    );
  }

  // =====================================================
  // DAILY AARTI
  // =====================================================

  Future<void> saveAartiAttendance(DailyAartiModel attendance) async {
    final db = await _db;

    await db.insert(
      'daily_aarti',
      attendance.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeAartiAttendance(
    int userId,
    int aartiTypeId,
    String date,
  ) async {
    final db = await _db;

    await db.delete(
      'daily_aarti',
      where: '''
        user_id = ?
        AND aarti_type_id = ?
        AND date = ?
      ''',
      whereArgs: [userId, aartiTypeId, date],
    );
  }

  Future<List<DailyAartiModel>> getAartiAttendance(
    int userId,
    String date,
  ) async {
    final db = await _db;

    final result = await db.query(
      'daily_aarti',
      where: '''
        user_id = ?
        AND date = ?
      ''',
      whereArgs: [userId, date],
    );

    return result.map(DailyAartiModel.fromMap).toList();
  }

  // =====================================================
  // DAY NOTES
  // =====================================================

  Future<DayNoteModel?> getDayNote(int userId, String date) async {
    final db = await _db;

    final result = await db.query(
      'day_notes',
      where: '''
        user_id = ?
        AND date = ?
      ''',
      whereArgs: [userId, date],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return DayNoteModel.fromMap(result.first);
  }

  Future<void> saveDayNote(DayNoteModel note) async {
    final db = await _db;

    final existing = await db.query(
      'day_notes',
      where: '''
        user_id = ?
        AND date = ?
      ''',
      whereArgs: [note.userId, note.date],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('day_notes', note.toMap());
    } else {
      await db.update(
        'day_notes',
        {
          'is_starred': note.isStarred ? 1 : 0,
          'note': note.note,
          'updated_at': note.updatedAt,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // =====================================================
  // GOALS
  // =====================================================

  Future<GoalModel?> getGoal(int userId, int sadhanaTypeId) async {
    final db = await _db;

    final result = await db.query(
      'goals',
      where: '''
        user_id = ?
        AND sadhana_type_id = ?
        AND is_active = ?
      ''',
      whereArgs: [userId, sadhanaTypeId, 1],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return GoalModel.fromMap(result.first);
  }

  Future<void> saveGoal(GoalModel goal) async {
    final db = await _db;

    final existing = await db.query(
      'goals',
      where: '''
      user_id = ?
      AND sadhana_type_id = ?
    ''',
      whereArgs: [goal.userId, goal.sadhanaTypeId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('goals', goal.toMap());
    } else {
      await db.update(
        'goals',
        {
          'target_value': goal.targetValue,
          'unit': goal.unit,
          'is_active': 1,
          'updated_at': goal.updatedAt ?? DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }
}
