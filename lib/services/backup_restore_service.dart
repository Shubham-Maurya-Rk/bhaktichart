import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';

class BackupRestoreService {
  BackupRestoreService._();

  static final BackupRestoreService instance = BackupRestoreService._();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // ============================================================
  // CONSTANTS
  // ============================================================

  static const String backupPrefix = 'bhaktichart_backup';

  // ============================================================
  // DATABASE PATH
  // ============================================================

  Future<String> getDatabasePath() async {
    return _databaseHelper.databasePath;
  }

  // ============================================================
  // EXPORT DATABASE
  // ============================================================

  Future<File> createBackupFile() async {
    Database? db;

    try {
      // --------------------------------------------------------
      // Open database if it is not already open.
      //
      // This also makes sure the database exists.
      // --------------------------------------------------------

      db = await _databaseHelper.database;

      // --------------------------------------------------------
      // Checkpoint WAL
      // --------------------------------------------------------

      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (e) {
        // WAL checkpoint is not available on every configuration.
        // Closing the DB below is still important.
      }

      // --------------------------------------------------------
      // CLOSE DATABASE
      //
      // This is VERY important.
      //
      // We don't want to copy the SQLite database while
      // sqflite is actively writing to it.
      // --------------------------------------------------------

      await _databaseHelper.closeDatabase();

      // --------------------------------------------------------
      // DATABASE FILE
      // --------------------------------------------------------

      final databasePath = await _databaseHelper.databasePath;

      final databaseFile = File(databasePath);

      if (!await databaseFile.exists()) {
        throw Exception(
          'Bhaktichart database file was not found.\n'
          'Path: $databasePath',
        );
      }

      final databaseSize = await databaseFile.length();

      if (databaseSize <= 0) {
        throw Exception('Bhaktichart database is empty.');
      }

      // --------------------------------------------------------
      // CACHE DIRECTORY
      // --------------------------------------------------------

      final tempDirectory = await getTemporaryDirectory();

      final timestamp = _formatTimestamp(DateTime.now());

      final backupPath = path.join(
        tempDirectory.path,
        '${backupPrefix}_$timestamp.db',
      );

      // --------------------------------------------------------
      // REMOVE OLD FILE IF EXISTS
      // --------------------------------------------------------

      await _deleteIfExists(File(backupPath));

      // --------------------------------------------------------
      // COPY DATABASE
      // --------------------------------------------------------

      final backupFile = await databaseFile.copy(backupPath);

      // --------------------------------------------------------
      // DELETE WAL / SHM FROM CURRENT DATABASE LOCATION
      //
      // Since the DB has been closed, these should normally
      // already be handled by SQLite.
      // --------------------------------------------------------

      await _deleteIfExists(File('$databasePath-wal'));

      await _deleteIfExists(File('$databasePath-shm'));

      // --------------------------------------------------------
      // VALIDATE CREATED BACKUP
      // --------------------------------------------------------

      await _validateBackupDatabase(backupFile);

      // --------------------------------------------------------
      // REOPEN DATABASE
      //
      // Important because the app is still running.
      // --------------------------------------------------------

      await _databaseHelper.reopenDatabase();

      return backupFile;
    } catch (e) {
      // --------------------------------------------------------
      // IMPORTANT:
      // Always try to reopen DB if export failed.
      // --------------------------------------------------------

      try {
        await _databaseHelper.reopenDatabase();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // RESTORE DATABASE
  // ============================================================

  Future<void> restoreDatabase(File backupFile) async {
    // ----------------------------------------------------------
    // CHECK BACKUP EXISTS
    // ----------------------------------------------------------

    if (!await backupFile.exists()) {
      throw Exception('Backup file does not exist.');
    }

    final backupSize = await backupFile.length();

    if (backupSize <= 0) {
      throw Exception('Backup file is empty.');
    }

    // ----------------------------------------------------------
    // VALIDATE BACKUP BEFORE TOUCHING CURRENT DATABASE
    // ----------------------------------------------------------

    await _validateBackupDatabase(backupFile);

    final currentDatabasePath = await _databaseHelper.databasePath;

    final currentDatabaseFile = File(currentDatabasePath);

    String? emergencyBackupPath;

    try {
      // --------------------------------------------------------
      // CLOSE CURRENT DATABASE
      // --------------------------------------------------------

      await _databaseHelper.closeDatabase();

      // --------------------------------------------------------
      // CREATE EMERGENCY BACKUP
      //
      // If restore fails, we can restore the current database.
      // --------------------------------------------------------

      if (await currentDatabaseFile.exists()) {
        final tempDirectory = await getTemporaryDirectory();

        emergencyBackupPath = path.join(
          tempDirectory.path,
          'bhaktichart_before_restore_'
          '${DateTime.now().millisecondsSinceEpoch}.db',
        );

        await currentDatabaseFile.copy(emergencyBackupPath);
      }

      // --------------------------------------------------------
      // REMOVE CURRENT SQLITE AUXILIARY FILES
      // --------------------------------------------------------

      await _deleteIfExists(File('$currentDatabasePath-wal'));

      await _deleteIfExists(File('$currentDatabasePath-shm'));

      // --------------------------------------------------------
      // REMOVE CURRENT DATABASE
      // --------------------------------------------------------

      await _deleteIfExists(currentDatabaseFile);

      // --------------------------------------------------------
      // COPY RESTORED DATABASE
      // --------------------------------------------------------

      await backupFile.copy(currentDatabasePath);

      // --------------------------------------------------------
      // MAKE SURE RESTORED FILE EXISTS
      // --------------------------------------------------------

      if (!await currentDatabaseFile.exists()) {
        throw Exception('Restored database file could not be created.');
      }

      // --------------------------------------------------------
      // OPEN RESTORED DATABASE
      //
      // DatabaseHelper will automatically run migrations if
      // backup DB version is lower than current app DB version.
      // --------------------------------------------------------

      final restoredDb = await _databaseHelper.reopenDatabase();

      // --------------------------------------------------------
      // BASIC SQLITE TEST
      // --------------------------------------------------------

      await restoredDb.rawQuery('SELECT name FROM sqlite_master LIMIT 1');

      // --------------------------------------------------------
      // CHECK DATABASE TABLES
      // --------------------------------------------------------

      await _validateOpenedDatabase(restoredDb);

      // --------------------------------------------------------
      // RESTORE SUCCESSFUL
      // --------------------------------------------------------

      if (emergencyBackupPath != null) {
        await _deleteIfExists(File(emergencyBackupPath));
      }
    } catch (e) {
      // --------------------------------------------------------
      // RESTORE FAILED
      // --------------------------------------------------------

      try {
        await _databaseHelper.closeDatabase();
      } catch (_) {}

      // Remove corrupted/partially restored DB.
      await _deleteIfExists(currentDatabaseFile);

      await _deleteIfExists(File('$currentDatabasePath-wal'));

      await _deleteIfExists(File('$currentDatabasePath-shm'));

      // --------------------------------------------------------
      // RESTORE EMERGENCY BACKUP
      // --------------------------------------------------------

      if (emergencyBackupPath != null) {
        final emergencyBackup = File(emergencyBackupPath);

        if (await emergencyBackup.exists()) {
          await emergencyBackup.copy(currentDatabasePath);
        }
      }

      // --------------------------------------------------------
      // TRY TO OPEN ORIGINAL DATABASE AGAIN
      // --------------------------------------------------------

      try {
        await _databaseHelper.reopenDatabase();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // VALIDATE BACKUP FILE
  // ============================================================

  Future<void> _validateBackupDatabase(File backupFile) async {
    final tempDirectory = await getTemporaryDirectory();

    final validationPath = path.join(
      tempDirectory.path,
      'bhaktichart_validation_'
      '${DateTime.now().millisecondsSinceEpoch}.db',
    );

    final validationFile = File(validationPath);

    Database? testDatabase;

    try {
      // --------------------------------------------------------
      // COPY BACKUP TO TEMPORARY LOCATION
      // --------------------------------------------------------

      await backupFile.copy(validationPath);

      // --------------------------------------------------------
      // OPEN SQLITE DATABASE
      // --------------------------------------------------------

      testDatabase = await openDatabase(validationPath, readOnly: true);

      // --------------------------------------------------------
      // SQLITE INTEGRITY CHECK
      // --------------------------------------------------------

      final integrityResult = await testDatabase.rawQuery(
        'PRAGMA integrity_check',
      );

      if (integrityResult.isEmpty) {
        throw Exception('Backup database integrity check returned no result.');
      }

      final integrityValue = integrityResult.first.values.first.toString();

      if (integrityValue.toLowerCase() != 'ok') {
        throw Exception('Backup database failed SQLite integrity check.');
      }

      // --------------------------------------------------------
      // CHECK TABLES
      // --------------------------------------------------------

      final tables = await testDatabase.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
      ''');

      final tableNames = tables
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();

      // --------------------------------------------------------
      // REQUIRED BHKTICHART TABLES
      // --------------------------------------------------------

      const requiredTables = <String>{'users', 'daily_sadhana'};

      final missingTables = requiredTables
          .where((table) => !tableNames.contains(table))
          .toList();

      if (missingTables.isNotEmpty) {
        throw Exception(
          'This file does not appear to be a Bhaktichart backup.\n\n'
          'Missing table(s): ${missingTables.join(', ')}',
        );
      }
    } finally {
      // --------------------------------------------------------
      // CLOSE TEMP DATABASE
      // --------------------------------------------------------

      try {
        await testDatabase?.close();
      } catch (_) {}

      // --------------------------------------------------------
      // REMOVE TEMP DATABASE
      // --------------------------------------------------------

      await _deleteIfExists(validationFile);

      await _deleteIfExists(File('$validationPath-wal'));

      await _deleteIfExists(File('$validationPath-shm'));
    }
  }

  // ============================================================
  // VALIDATE OPENED DATABASE
  // ============================================================

  Future<void> _validateOpenedDatabase(Database database) async {
    final result = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
    ''');

    final tableNames = result
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();

    if (!tableNames.contains('users')) {
      throw Exception('Restored database is missing the users table.');
    }

    if (!tableNames.contains('daily_sadhana')) {
      throw Exception('Restored database is missing the daily_sadhana table.');
    }
  }

  // ============================================================
  // DELETE FILE SAFELY
  // ============================================================

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  String _formatTimestamp(DateTime date) {
    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${date.year}'
        '${two(date.month)}'
        '${two(date.day)}_'
        '${two(date.hour)}'
        '${two(date.minute)}'
        '${two(date.second)}';
  }
}
