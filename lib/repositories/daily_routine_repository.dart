import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../models/daily_routine.dart';
import '../models/daily_routine_goal.dart';

class DailyRoutineRepository {
  final DatabaseHelper databaseHelper;

  DailyRoutineRepository({DatabaseHelper? databaseHelper})
    : databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  // ============================================================
  // DATE
  // ============================================================

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isBeyondTomorrow(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final selected = _dateOnly(date);

    return selected.isAfter(tomorrow);
  }

  // ============================================================
  // GET BY DATE
  // ============================================================

  Future<DailyRoutine?> getByDate(int userId, DateTime date) async {
    final db = await databaseHelper.database;

    final rows = await db.query(
      'daily_routine',
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, DailyRoutine.dateOnly(date).toIso8601String()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return DailyRoutine.fromMap(rows.first);
  }

  // ============================================================
  // GET MONTH
  // ============================================================

  Future<List<DailyRoutine>> getMonth(int userId, DateTime month) async {
    final db = await databaseHelper.database;

    final firstDay = DateTime(month.year, month.month, 1);

    final lastDay = DateTime(month.year, month.month + 1, 0);

    final rows = await db.query(
      'daily_routine',
      where: '''
        user_id = ?
        AND date >= ?
        AND date <= ?
      ''',
      whereArgs: [
        userId,
        firstDay.toIso8601String(),
        lastDay.toIso8601String(),
      ],
      orderBy: 'date ASC',
    );

    return rows.map(DailyRoutine.fromMap).toList();
  }

  // ============================================================
  // UPSERT ROUTINE
  // ============================================================

  Future<int> save(DailyRoutine routine) async {
    if (_isBeyondTomorrow(routine.date)) {
      throw Exception('You cannot add a routine for a future date.');
    }

    final db = await databaseHelper.database;

    final existing = await getByDate(routine.userId, routine.date);

    final data = routine.toMap();

    data.remove('id');

    if (existing == null) {
      return db.insert(
        'daily_routine',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await db.update(
      'daily_routine',
      data,
      where: 'id = ?',
      whereArgs: [existing.id],
    );

    return existing.id!;
  }

  // ============================================================
  // UPDATE WAKE TIME
  // ============================================================

  Future<void> updateWakeTime({
    required int userId,
    required DateTime date,
    required DateTime time,
  }) async {
    if (_isBeyondTomorrow(date)) {
      throw Exception('Future dates are not allowed.');
    }

    final existing = await getByDate(userId, date);

    final now = DateTime.now();

    if (existing == null) {
      await dbInsert(
        DailyRoutine(
          userId: userId,
          date: _dateOnly(date),
          wakeUpTime: time,
          sleepTime: null,
          createdAt: now,
        ),
      );

      return;
    }

    final updated = existing.copyWith(wakeUpTime: time, updatedAt: now);

    await save(updated);
  }

  // ============================================================
  // UPDATE SLEEP TIME
  // ============================================================

  Future<void> updateSleepTime({
    required int userId,
    required DateTime date,
    required DateTime time,
  }) async {
    if (_isBeyondTomorrow(date)) {
      throw Exception('Future dates are not allowed.');
    }

    final existing = await getByDate(userId, date);

    final now = DateTime.now();

    if (existing == null) {
      await dbInsert(
        DailyRoutine(
          userId: userId,
          date: _dateOnly(date),
          wakeUpTime: null,
          sleepTime: time,
          createdAt: now,
        ),
      );

      return;
    }

    final updated = existing.copyWith(sleepTime: time, updatedAt: now);

    await save(updated);
  }

  Future<void> dbInsert(DailyRoutine routine) async {
    final db = await databaseHelper.database;

    await db.insert(
      'daily_routine',
      routine.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> delete(int id) async {
    final db = await databaseHelper.database;

    await db.delete('daily_routine', where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // GOAL
  // ============================================================

  Future<DailyRoutineGoal?> getGoal(int userId) async {
    final db = await databaseHelper.database;

    final rows = await db.query(
      'daily_routine_goals',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return DailyRoutineGoal.fromMap(rows.first);
  }

  Future<void> saveGoal(DailyRoutineGoal goal) async {
    final db = await databaseHelper.database;

    final data = goal.toMap();
    data.remove('id');

    await db.insert(
      'daily_routine_goals',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
