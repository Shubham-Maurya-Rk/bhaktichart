import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';

class DailyTodoTask {
  final String id;
  final String title;
  final String description;
  final String category;
  final String emoji;
  final bool completed;
  final String completionDate;
  final int sortOrder;

  const DailyTodoTask({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.emoji,
    required this.completed,
    required this.completionDate,
    required this.sortOrder,
  });

  DailyTodoTask copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? emoji,
    bool? completed,
    String? completionDate,
    int? sortOrder,
  }) {
    return DailyTodoTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      completed: completed ?? this.completed,
      completionDate: completionDate ?? this.completionDate,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory DailyTodoTask.fromMap(Map<String, dynamic> map) {
    return DailyTodoTask(
      id: map['id'].toString(),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Morning',
      emoji: map['emoji']?.toString() ?? '🙏',
      completed: map['completed'] == 1,
      completionDate: map['completion_date']?.toString() ?? '',
      sortOrder: map['sort_order'] is int
          ? map['sort_order'] as int
          : int.tryParse(map['sort_order']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'emoji': emoji,
      'completed': completed ? 1 : 0,
      'completion_date': completionDate,
      'sort_order': sortOrder,
    };
  }
}

class DailyTodoRepository {
  DailyTodoRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  static const String _table = 'daily_todo_tasks';

  // ============================================================
  // DATE
  // ============================================================

  String get todayKey {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  // ============================================================
  // GET ALL TASKS
  // ============================================================

  Future<List<DailyTodoTask>> getTasks() async {
    final db = await _databaseHelper.database;

    await _resetForNewDay(db);

    final result = await db.query(
      _table,
      orderBy: 'sort_order ASC, created_at ASC',
    );

    return result.map((map) => DailyTodoTask.fromMap(map)).toList();
  }

  // ============================================================
  // RESET FOR NEW DAY
  //
  // Same behavior as the old SharedPreferences implementation.
  //
  // If the stored completion_date is not today:
  //     completed = 0
  //     completion_date = today
  //
  // No historical records are created.
  // ============================================================

  Future<void> _resetForNewDay(Database db) async {
    final today = todayKey;

    await db.transaction((txn) async {
      final result = await txn.query(
        _table,
        columns: ['id'],
        where: 'completion_date != ?',
        whereArgs: [today],
      );

      if (result.isEmpty) {
        return;
      }

      await txn.update(
        _table,
        {
          'completed': 0,
          'completion_date': today,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'completion_date != ?',
        whereArgs: [today],
      );
    });
  }

  // ============================================================
  // ADD TASK
  // ============================================================

  Future<void> addTask({
    required String id,
    required String title,
    required String description,
    required String category,
    required String emoji,
  }) async {
    final db = await _databaseHelper.database;

    final maxResult = await db.rawQuery('''
      SELECT MAX(sort_order) AS max_order
      FROM $_table
      ''');

    final maxOrder = (maxResult.first['max_order'] as int?) ?? -1;

    final now = DateTime.now().toIso8601String();

    await db.insert(_table, {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'emoji': emoji,
      'completed': 0,
      'completion_date': todayKey,
      'sort_order': maxOrder + 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ============================================================
  // UPDATE TASK
  // ============================================================

  Future<void> updateTask(DailyTodoTask task) async {
    final db = await _databaseHelper.database;

    await db.update(
      _table,
      {
        'title': task.title,
        'description': task.description,
        'category': task.category,
        'emoji': task.emoji,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // ============================================================
  // TOGGLE COMPLETION
  // ============================================================

  Future<void> toggleTask(DailyTodoTask task) async {
    final db = await _databaseHelper.database;

    await db.update(
      _table,
      {
        'completed': task.completed ? 0 : 1,
        'completion_date': todayKey,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // ============================================================
  // SET COMPLETION
  // ============================================================

  Future<void> setCompleted(DailyTodoTask task, bool completed) async {
    final db = await _databaseHelper.database;

    await db.update(
      _table,
      {
        'completed': completed ? 1 : 0,
        'completion_date': todayKey,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // ============================================================
  // DELETE TASK
  // ============================================================

  Future<void> deleteTask(String id) async {
    final db = await _databaseHelper.database;

    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // CLEAR COMPLETED
  // ============================================================

  Future<void> clearCompleted() async {
    final db = await _databaseHelper.database;

    await db.delete(_table, where: 'completed = ?', whereArgs: [1]);
  }

  // ============================================================
  // RESET TODAY
  // ============================================================

  Future<void> resetToday() async {
    final db = await _databaseHelper.database;

    await db.update(_table, {
      'completed': 0,
      'completion_date': todayKey,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ============================================================
  // REORDER
  //
  // Receives the complete task order and saves sort_order.
  // ============================================================

  Future<void> reorderTasks(List<DailyTodoTask> tasks) async {
    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      for (int i = 0; i < tasks.length; i++) {
        await txn.update(
          _table,
          {'sort_order': i, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [tasks[i].id],
        );
      }
    });
  }
}
