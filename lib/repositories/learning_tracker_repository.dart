import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../models/learning_book.dart';
import '../models/learning_shloka.dart';

class LearningTrackerRepository {
  final DatabaseHelper databaseHelper;

  LearningTrackerRepository({DatabaseHelper? databaseHelper})
    : databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  // ============================================================
  // BOOKS
  // ============================================================

  Future<List<LearningBook>> getBooks(int userId) async {
    final db = await databaseHelper.database;

    final rows = await db.query(
      'learning_books',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(LearningBook.fromMap).toList();
  }

  Future<LearningBook?> getBookById(int id) async {
    final db = await databaseHelper.database;

    final rows = await db.query(
      'learning_books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return LearningBook.fromMap(rows.first);
  }

  Future<int> addBook(LearningBook book) async {
    final db = await databaseHelper.database;

    try {
      final data = book.toMap();
      data.remove('id');

      return await db.insert(
        'learning_books',
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception('A book with this name already exists.');
      }

      rethrow;
    }
  }

  Future<void> updateBook(LearningBook book) async {
    if (book.id == null) {
      throw Exception('Book ID is required.');
    }

    final db = await databaseHelper.database;

    final data = book.toMap();
    data.remove('id');

    try {
      await db.update(
        'learning_books',
        data,
        where: 'id = ?',
        whereArgs: [book.id],
      );
    } on DatabaseException catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception('A book with this name already exists.');
      }

      rethrow;
    }
  }

  Future<void> deleteBook(int bookId) async {
    final db = await databaseHelper.database;

    await db.delete('learning_books', where: 'id = ?', whereArgs: [bookId]);
  }

  // ============================================================
  // SHLOKAS
  // ============================================================

  Future<List<LearningShloka>> getShlokas({
    required int userId,
    required int bookId,
    LearningStatus? status,
  }) async {
    final db = await databaseHelper.database;

    String? where;
    List<Object?>? whereArgs;

    if (status != null) {
      where = 'user_id = ? AND book_id = ? AND status = ?';

      whereArgs = [userId, bookId, status.value];
    } else {
      where = 'user_id = ? AND book_id = ?';

      whereArgs = [userId, bookId];
    }

    final rows = await db.query(
      'learning_shlokas',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'reference ASC',
    );

    return rows.map(LearningShloka.fromMap).toList();
  }

  Future<LearningShloka?> getShlokaById(int id) async {
    final db = await databaseHelper.database;

    final rows = await db.query(
      'learning_shlokas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return LearningShloka.fromMap(rows.first);
  }

  Future<bool> referenceExists({
    required int bookId,
    required String reference,
    int? excludeShlokaId,
  }) async {
    final db = await databaseHelper.database;

    String where = 'book_id = ? AND LOWER(reference) = LOWER(?)';

    final args = <Object?>[bookId, reference.trim()];

    if (excludeShlokaId != null) {
      where += ' AND id != ?';
      args.add(excludeShlokaId);
    }

    final rows = await db.query(
      'learning_shlokas',
      where: where,
      whereArgs: args,
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<int> addShloka(LearningShloka shloka) async {
    final db = await databaseHelper.database;

    final exists = await referenceExists(
      bookId: shloka.bookId,
      reference: shloka.reference,
    );

    if (exists) {
      throw Exception('This reference already exists in this book.');
    }

    final data = shloka.toMap();
    data.remove('id');

    try {
      return await db.insert(
        'learning_shlokas',
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception('This reference already exists in this book.');
      }

      rethrow;
    }
  }

  Future<void> updateShloka(LearningShloka shloka) async {
    if (shloka.id == null) {
      throw Exception('Shloka ID is required.');
    }

    final exists = await referenceExists(
      bookId: shloka.bookId,
      reference: shloka.reference,
      excludeShlokaId: shloka.id,
    );

    if (exists) {
      throw Exception('This reference already exists in this book.');
    }

    final db = await databaseHelper.database;

    final data = shloka.toMap();
    data.remove('id');

    await db.update(
      'learning_shlokas',
      data,
      where: 'id = ?',
      whereArgs: [shloka.id],
    );
  }

  Future<void> updateStatus({
    required int shlokaId,
    required LearningStatus status,
  }) async {
    final db = await databaseHelper.database;

    await db.update(
      'learning_shlokas',
      {'status': status.value, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [shlokaId],
    );
  }

  Future<void> deleteShloka(int id) async {
    final db = await databaseHelper.database;

    await db.delete('learning_shlokas', where: 'id = ?', whereArgs: [id]);
  }

  // ============================================================
  // STATISTICS
  // ============================================================

  Future<Map<LearningStatus, int>> getStatusCounts({
    required int userId,
    required int bookId,
  }) async {
    final db = await databaseHelper.database;

    final rows = await db.rawQuery(
      '''
      SELECT status, COUNT(*) AS count
      FROM learning_shlokas
      WHERE user_id = ?
        AND book_id = ?
      GROUP BY status
      ''',
      [userId, bookId],
    );

    final result = <LearningStatus, int>{};

    for (final status in LearningStatus.values) {
      result[status] = 0;
    }

    for (final row in rows) {
      final status = LearningStatusExtension.fromValue(
        row['status'] as String?,
      );

      result[status] = (row['count'] as int?) ?? 0;
    }

    return result;
  }
}
