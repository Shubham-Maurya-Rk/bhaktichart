import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/database_helper.dart';

class AutomaticBackupResult {
  final String datedFileName;
  final DateTime createdAt;

  const AutomaticBackupResult({
    required this.datedFileName,
    required this.createdAt,
  });
}

class BackupRestoreService {
  BackupRestoreService._();

  static final BackupRestoreService instance = BackupRestoreService._();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // ============================================================
  // CONSTANTS
  // ============================================================

  static const String backupPrefix = 'bhaktichart_backup';

  static const String automaticBackupPrefix = 'bhaktichart_auto_backup';

  static const String _lastAutomaticBackupKey =
      'bhaktichart_last_automatic_backup';

  static const String automaticBackupRelativePath = 'BhaktiChart/Backups/';

  /// Maximum number of automatic weekly backups.
  static const int maxAutomaticBackups = 12;

  final MediaStore _mediaStore = MediaStore();

  // ============================================================
  // DATABASE PATH
  // ============================================================

  Future<String> getDatabasePath() async {
    return _databaseHelper.databasePath;
  }

  // ============================================================
  // MANUAL DATABASE BACKUP
  // ============================================================

  Future<File> createBackupFile() async {
    try {
      // ----------------------------------------------------------
      // OPEN DATABASE
      // ----------------------------------------------------------

      final db = await _databaseHelper.database;

      // ----------------------------------------------------------
      // CHECKPOINT WAL
      // ----------------------------------------------------------

      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {
        // Ignore if WAL checkpoint is unavailable.
      }

      // ----------------------------------------------------------
      // CLOSE DATABASE
      // ----------------------------------------------------------

      await _databaseHelper.closeDatabase();

      // ----------------------------------------------------------
      // DATABASE FILE
      // ----------------------------------------------------------

      final databasePath = await _databaseHelper.databasePath;

      final databaseFile = File(databasePath);

      if (!await databaseFile.exists()) {
        throw Exception(
          'BhaktiChart database file was not found.\n'
          'Path: $databasePath',
        );
      }

      final databaseSize = await databaseFile.length();

      if (databaseSize <= 0) {
        throw Exception('BhaktiChart database is empty.');
      }

      // ----------------------------------------------------------
      // TEMP DIRECTORY
      // ----------------------------------------------------------

      final tempDirectory = await getTemporaryDirectory();

      final timestamp = _formatTimestamp(DateTime.now());

      final backupPath = path.join(
        tempDirectory.path,
        '${backupPrefix}_$timestamp.db',
      );

      await _deleteIfExists(File(backupPath));

      // ----------------------------------------------------------
      // COPY DATABASE
      // ----------------------------------------------------------

      final backupFile = await databaseFile.copy(backupPath);

      // ----------------------------------------------------------
      // REMOVE WAL / SHM
      // ----------------------------------------------------------

      await _deleteIfExists(File('$databasePath-wal'));

      await _deleteIfExists(File('$databasePath-shm'));

      // ----------------------------------------------------------
      // VALIDATE BACKUP
      // ----------------------------------------------------------

      await _validateBackupDatabase(backupFile);

      // ----------------------------------------------------------
      // REOPEN DATABASE
      // ----------------------------------------------------------

      await _databaseHelper.reopenDatabase();

      return backupFile;
    } catch (e) {
      try {
        await _databaseHelper.reopenDatabase();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // CREATE AUTOMATIC BACKUP FILE
  // ============================================================

  Future<File> createAutomaticBackupFile() async {
    File? backupFile;

    try {
      // ----------------------------------------------------------
      // OPEN DATABASE
      // ----------------------------------------------------------

      final db = await _databaseHelper.database;

      // ----------------------------------------------------------
      // TEMP DIRECTORY
      // ----------------------------------------------------------

      final tempDirectory = await getTemporaryDirectory();

      final timestamp = _formatTimestamp(DateTime.now());

      final backupPath = path.join(
        tempDirectory.path,
        '${automaticBackupPrefix}_$timestamp.db',
      );

      backupFile = File(backupPath);

      await _deleteIfExists(backupFile);

      // ----------------------------------------------------------
      // VACUUM INTO
      //
      // Creates a consistent SQLite copy while the live DB
      // remains open.
      // ----------------------------------------------------------

      final escapedPath = backupPath.replaceAll("'", "''");

      await db.execute("VACUUM INTO '$escapedPath'");

      // ----------------------------------------------------------
      // VALIDATE FILE EXISTS
      // ----------------------------------------------------------

      if (!await backupFile.exists()) {
        throw Exception('Automatic backup database was not created.');
      }

      final size = await backupFile.length();

      if (size <= 0) {
        throw Exception('Automatic backup database is empty.');
      }

      // ----------------------------------------------------------
      // VALIDATE SQLITE DATABASE
      // ----------------------------------------------------------

      await _validateBackupDatabase(backupFile);

      return backupFile;
    } catch (e) {
      if (backupFile != null) {
        await _deleteIfExists(backupFile);
      }

      rethrow;
    }
  }

  // ============================================================
  // CREATE AUTOMATIC BACKUP
  //
  // IMPORTANT:
  //
  // We create ONLY ONE shared-storage file per backup:
  //
  // bhaktichart_auto_backup_YYYYMMDD_HHMMSS.db
  //
  // There is NO "latest_backup.db".
  //
  // The newest dated file is the latest backup.
  //
  // Maximum:
  //
  // 12 automatic backups
  // ============================================================

  Future<AutomaticBackupResult> createAutomaticBackup() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Automatic shared-storage backups are currently '
        'supported on Android only.',
      );
    }

    try {
      // ----------------------------------------------------------
      // INITIALIZE MEDIA STORE
      // ----------------------------------------------------------

      await MediaStore.ensureInitialized();

      MediaStore.appFolder = 'BhaktiChart';

      // ----------------------------------------------------------
      // CREATE VALIDATED BACKUP
      // ----------------------------------------------------------

      final backupFile = await createAutomaticBackupFile();

      try {
        final timestamp = _formatTimestamp(DateTime.now());

        final datedName = '${automaticBackupPrefix}_$timestamp.db';

        // --------------------------------------------------------
        // SAVE ONE FILE ONLY
        // --------------------------------------------------------

        final result = await _mediaStore.saveFile(
          tempFilePath: backupFile.path,
          dirType: DirType.download,
          dirName: DirName.download,
          relativePath: automaticBackupRelativePath,
        );

        if (result == null) {
          throw Exception('Could not save automatic backup.');
        }

        // --------------------------------------------------------
        // IMPORTANT
        //
        // If MediaStore creates:
        //
        // xxx (1).db
        //
        // then something with the same name already exists.
        //
        // We do NOT treat this as a successful normal backup.
        // --------------------------------------------------------

        if (result.isDuplicated) {
          throw Exception('Automatic backup already exists: ${result.name}');
        }

        if (!result.isSuccessful) {
          throw Exception('Could not save automatic backup: ${result.name}');
        }

        // --------------------------------------------------------
        // CLEAN OLD BACKUPS
        // --------------------------------------------------------

        await _cleanupOldAutomaticBackups();

        // --------------------------------------------------------
        // SAVE LAST BACKUP TIME
        // --------------------------------------------------------

        final prefs = await SharedPreferences.getInstance();

        final now = DateTime.now();

        await prefs.setString(_lastAutomaticBackupKey, now.toIso8601String());

        return AutomaticBackupResult(
          datedFileName: result.name.isNotEmpty ? result.name : datedName,
          createdAt: now,
        );
      } finally {
        // --------------------------------------------------------
        // TEMP FILE
        //
        // media_store_plus normally consumes/deletes the source
        // file after saveFile().
        // --------------------------------------------------------

        await _deleteIfExists(backupFile);
      }
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================
  // CLEAN OLD AUTOMATIC BACKUPS
  //
  // Keeps newest 12 dated backups.
  //
  // Example:
  //
  // 01
  // 02
  // ...
  // 12
  //
  // When backup #13 is created:
  //
  // #1 is deleted.
  // ============================================================

  Future<void> _cleanupOldAutomaticBackups() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await MediaStore.ensureInitialized();

      MediaStore.appFolder = 'BhaktiChart';

      // ----------------------------------------------------------
      // Get folder path
      // ----------------------------------------------------------

      final rootPath = DirType.download.fullPath(
        relativePath: automaticBackupRelativePath,
        dirName: DirName.download,
      );

      final directory = Directory(rootPath);

      if (!await directory.exists()) {
        print(
          'Automatic backup directory does not exist yet: '
          '$rootPath',
        );

        return;
      }

      // ----------------------------------------------------------
      // Find dated backup files
      // ----------------------------------------------------------

      final files = <File>[];

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final fileName = path.basename(entity.path);

        if (_isDatedAutomaticBackup(fileName)) {
          files.add(entity);
        }
      }

      // ----------------------------------------------------------
      // Sort newest -> oldest
      //
      // Filename contains:
      //
      // YYYYMMDD_HHMMSS
      //
      // Therefore lexical sorting works correctly.
      // ----------------------------------------------------------

      files.sort(
        (a, b) => path.basename(b.path).compareTo(path.basename(a.path)),
      );

      // ----------------------------------------------------------
      // DELETE EVERYTHING AFTER 12
      // ----------------------------------------------------------

      if (files.length <= maxAutomaticBackups) {
        return;
      }

      for (int i = maxAutomaticBackups; i < files.length; i++) {
        final oldFile = files[i];

        print(
          'Deleting old automatic backup: '
          '${path.basename(oldFile.path)}',
        );

        await _deleteIfExists(oldFile);
      }
    } catch (e) {
      // ----------------------------------------------------------
      // IMPORTANT:
      //
      // Cleanup failure must NOT make the backup itself fail.
      // ----------------------------------------------------------

      print('Automatic backup cleanup failed: $e');
    }
  }

  // ============================================================
  // CHECK DATED BACKUP NAME
  // ============================================================

  bool _isDatedAutomaticBackup(String fileName) {
    final regex = RegExp(
      '^${RegExp.escape(automaticBackupPrefix)}_'
      r'\d{8}_\d{6}\.db$',
    );

    return regex.hasMatch(fileName);
  }

  // ============================================================
  // LAST AUTOMATIC BACKUP
  // ============================================================

  Future<DateTime?> getLastAutomaticBackupTime() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_lastAutomaticBackupKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  // ============================================================
  // RESTORE DATABASE
  // ============================================================

  Future<void> restoreDatabase(File backupFile) async {
    // ----------------------------------------------------------
    // CHECK BACKUP
    // ----------------------------------------------------------

    if (!await backupFile.exists()) {
      throw Exception('Backup file does not exist.');
    }

    final backupSize = await backupFile.length();

    if (backupSize <= 0) {
      throw Exception('Backup file is empty.');
    }

    // ----------------------------------------------------------
    // VALIDATE BACKUP
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
      // DELETE WAL / SHM
      // --------------------------------------------------------

      await _deleteIfExists(File('$currentDatabasePath-wal'));

      await _deleteIfExists(File('$currentDatabasePath-shm'));

      // --------------------------------------------------------
      // DELETE CURRENT DATABASE
      // --------------------------------------------------------

      await _deleteIfExists(currentDatabaseFile);

      // --------------------------------------------------------
      // COPY RESTORED DATABASE
      // --------------------------------------------------------

      await backupFile.copy(currentDatabasePath);

      if (!await currentDatabaseFile.exists()) {
        throw Exception('Restored database file could not be created.');
      }

      // --------------------------------------------------------
      // REOPEN DATABASE
      // --------------------------------------------------------

      final restoredDb = await _databaseHelper.reopenDatabase();

      // --------------------------------------------------------
      // BASIC TEST
      // --------------------------------------------------------

      await restoredDb.rawQuery('SELECT name FROM sqlite_master LIMIT 1');

      // --------------------------------------------------------
      // VALIDATE TABLES
      // --------------------------------------------------------

      await _validateOpenedDatabase(restoredDb);

      // --------------------------------------------------------
      // DELETE EMERGENCY COPY
      // --------------------------------------------------------

      if (emergencyBackupPath != null) {
        await _deleteIfExists(File(emergencyBackupPath));
      }
    } catch (e) {
      // --------------------------------------------------------
      // CLOSE FAILED DATABASE
      // --------------------------------------------------------

      try {
        await _databaseHelper.closeDatabase();
      } catch (_) {}

      // --------------------------------------------------------
      // DELETE FAILED DATABASE
      // --------------------------------------------------------

      await _deleteIfExists(currentDatabaseFile);

      await _deleteIfExists(File('$currentDatabasePath-wal'));

      await _deleteIfExists(File('$currentDatabasePath-shm'));

      // --------------------------------------------------------
      // RESTORE EMERGENCY COPY
      // --------------------------------------------------------

      if (emergencyBackupPath != null) {
        final emergencyBackup = File(emergencyBackupPath);

        if (await emergencyBackup.exists()) {
          await emergencyBackup.copy(currentDatabasePath);
        }
      }

      // --------------------------------------------------------
      // REOPEN ORIGINAL
      // --------------------------------------------------------

      try {
        await _databaseHelper.reopenDatabase();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // VALIDATE BACKUP DATABASE
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
      // COPY BACKUP
      // --------------------------------------------------------

      await backupFile.copy(validationPath);

      // --------------------------------------------------------
      // OPEN READ ONLY
      // --------------------------------------------------------

      testDatabase = await openDatabase(validationPath, readOnly: true);

      // --------------------------------------------------------
      // SQLITE INTEGRITY CHECK
      // --------------------------------------------------------

      final integrityResult = await testDatabase.rawQuery(
        'PRAGMA integrity_check',
      );

      if (integrityResult.isEmpty) {
        throw Exception(
          'Backup database integrity check '
          'returned no result.',
        );
      }

      final integrityValue = integrityResult.first.values.first.toString();

      if (integrityValue.toLowerCase() != 'ok') {
        throw Exception(
          'Backup database failed SQLite '
          'integrity check.',
        );
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
      // REQUIRED TABLES
      // --------------------------------------------------------

      const requiredTables = <String>{'users', 'daily_sadhana'};

      final missingTables = requiredTables
          .where((table) => !tableNames.contains(table))
          .toList();

      if (missingTables.isNotEmpty) {
        throw Exception(
          'This file does not appear to be '
          'a BhaktiChart backup.\n\n'
          'Missing table(s): '
          '${missingTables.join(', ')}',
        );
      }
    } finally {
      // --------------------------------------------------------
      // CLOSE VALIDATION DATABASE
      // --------------------------------------------------------

      try {
        await testDatabase?.close();
      } catch (_) {}

      // --------------------------------------------------------
      // DELETE TEMP FILES
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
      throw Exception(
        'Restored database is missing '
        'the users table.',
      );
    }

    if (!tableNames.contains('daily_sadhana')) {
      throw Exception(
        'Restored database is missing '
        'the daily_sadhana table.',
      );
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
    } catch (e) {
      print(
        'Could not delete file '
        '${file.path}: $e',
      );
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
