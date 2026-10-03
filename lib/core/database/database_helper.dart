import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _databaseName = 'bhaktichart.db';

  // ============================================================
  // DATABASE VERSION
  // ============================================================
  //
  // Keep this as version 1.
  //
  // We are reinstalling the app, so no database migration is
  // required for this change.
  // ============================================================

  static const int _databaseVersion = 1;

  Database? _database;

  // ============================================================
  // DATABASE
  // ============================================================

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  // ============================================================
  // DATABASE PATH
  // ============================================================

  Future<String> get databasePath async {
    final databasesPath = await getDatabasesPath();

    return join(databasesPath, _databaseName);
  }

  // ============================================================
  // INIT DATABASE
  // ============================================================

  Future<Database> _initDatabase() async {
    final path = await databasePath;

    return await openDatabase(
      path,

      // IMPORTANT:
      // Keep this as version 1.
      version: _databaseVersion,

      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      onCreate: _onCreate,
    );
  }

  // ============================================================
  // CLOSE DATABASE
  // ============================================================

  Future<void> closeDatabase() async {
    final db = _database;

    if (db != null && db.isOpen) {
      await db.close();
    }

    _database = null;
  }

  // ============================================================
  // REOPEN DATABASE
  // ============================================================

  Future<Database> reopenDatabase() async {
    await closeDatabase();

    _database = await _initDatabase();

    return _database!;
  }

  // ============================================================
  // CREATE DATABASE
  // ============================================================

  Future<void> _onCreate(Database db, int version) async {
    // ==========================================================
    // USERS
    // ==========================================================

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        name TEXT NOT NULL,

        created_at TEXT NOT NULL,

        updated_at TEXT
      )
    ''');

    // ==========================================================
    // DAILY ROUTINE
    // ==========================================================

    await db.execute('''
      CREATE TABLE daily_routine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        date TEXT NOT NULL,

        wake_up_time TEXT,

        sleep_time TEXT,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          date
        )
      )
    ''');

    // ==========================================================
    // DAILY ROUTINE GOALS
    // ==========================================================

    await db.execute('''
      CREATE TABLE daily_routine_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL UNIQUE,

        wake_up_hour INTEGER NOT NULL DEFAULT 6,

        wake_up_minute INTEGER NOT NULL DEFAULT 0,

        sleep_hour INTEGER NOT NULL DEFAULT 22,

        sleep_minute INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // SADHANA TYPES
    // ==========================================================

    await db.execute('''
      CREATE TABLE sadhana_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        name TEXT NOT NULL UNIQUE,

        icon TEXT,

        is_active INTEGER NOT NULL DEFAULT 1,

        sort_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // DAILY SADHANA
    // ==========================================================
    //
    // IMPORTANT:
    //
    // One row still represents one Sadhana entry for:
    //
    // user + date + sadhana_type
    //
    // For Reading, the same row can now store:
    //
    //   reading_pages
    //   reading_verses
    //   reading_minutes
    //
    // All three can exist at the same time.
    //
    // Existing value/unit columns are intentionally retained
    // for compatibility with the current model/repository.
    // They will be handled in the next code changes.
    // ==========================================================

    await db.execute('''
      CREATE TABLE daily_sadhana (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        date TEXT NOT NULL,

        sadhana_type_id INTEGER NOT NULL,

        value REAL NOT NULL DEFAULT 0,

        unit TEXT,

        reading_pages REAL,

        reading_verses REAL,

        reading_minutes REAL,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        FOREIGN KEY (sadhana_type_id)
          REFERENCES sadhana_types(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          date,
          sadhana_type_id
        )
      )
    ''');

    // ==========================================================
    // READING SETTINGS
    // ==========================================================

    await db.execute('''
      CREATE TABLE reading_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL UNIQUE,

        unit TEXT NOT NULL DEFAULT 'pages',

        updated_at TEXT NOT NULL,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE
      )
    ''');

    // ==========================================================
    // AARTI TYPES
    // ==========================================================

    await db.execute('''
      CREATE TABLE aarti_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        name TEXT NOT NULL,

        is_active INTEGER NOT NULL DEFAULT 1,

        sort_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          name
        )
      )
    ''');

    // ==========================================================
    // DAILY AARTI
    // ==========================================================

    await db.execute('''
      CREATE TABLE daily_aarti (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        aarti_type_id INTEGER NOT NULL,

        date TEXT NOT NULL,

        created_at TEXT NOT NULL,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          aarti_type_id,
          date
        )
      )
    ''');

    // ==========================================================
    // DAY NOTES
    // ==========================================================

    await db.execute('''
      CREATE TABLE day_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        date TEXT NOT NULL,

        is_starred INTEGER NOT NULL DEFAULT 0,

        is_sankirtan INTEGER NOT NULL DEFAULT 0,

        is_ekadashi INTEGER NOT NULL DEFAULT 0,

        is_festival INTEGER NOT NULL DEFAULT 0,

        note TEXT,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          date
        )
      )
    ''');

    // ==========================================================
    // GOALS
    // ==========================================================

    await db.execute('''
      CREATE TABLE goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        sadhana_type_id INTEGER NOT NULL,

        target_value REAL NOT NULL,

        unit TEXT,

        is_active INTEGER NOT NULL DEFAULT 1,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          sadhana_type_id
        )
      )
    ''');

    // ==========================================================
    // LEARNING TRACKER
    // ==========================================================

    // ----------------------------------------------------------
    // LEARNING BOOKS
    // ----------------------------------------------------------

    await db.execute('''
      CREATE TABLE learning_books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        name TEXT NOT NULL,

        level_count INTEGER NOT NULL DEFAULT 1,

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          name
        )
      )
    ''');

    // ----------------------------------------------------------
    // LEARNING SHLOKAS
    // ----------------------------------------------------------

    await db.execute('''
      CREATE TABLE learning_shlokas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        book_id INTEGER NOT NULL,

        reference TEXT NOT NULL,

        shloka TEXT NOT NULL,

        translation TEXT,

        url TEXT,

        status TEXT NOT NULL DEFAULT 'not_learned',

        created_at TEXT NOT NULL,

        updated_at TEXT,

        FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

        FOREIGN KEY (book_id)
          REFERENCES learning_books(id)
          ON DELETE CASCADE,

        UNIQUE (
          book_id,
          reference
        )
      )
    ''');

    // ==========================================================
    // DAILY TODO TASKS
    //
    // IMPORTANT:
    //
    // One database row = one task.
    //
    // Tasks are NOT duplicated every day.
    //
    // completion_date tells us when the current completion
    // status was last updated.
    //
    // Example:
    //
    // 2026-08-23 -> completed = 1
    //
    // On 2026-08-24 the repository changes:
    //
    // completed = 0
    // completion_date = 2026-08-24
    //
    // The same task row remains in the database.
    // ==========================================================

    await db.execute('''
      CREATE TABLE daily_todo_tasks (
        id TEXT PRIMARY KEY,

        title TEXT NOT NULL,

        description TEXT NOT NULL DEFAULT '',

        category TEXT NOT NULL DEFAULT 'Morning',

        emoji TEXT NOT NULL DEFAULT '🙏',

        completed INTEGER NOT NULL DEFAULT 0,

        completion_date TEXT NOT NULL,

        sort_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        updated_at TEXT
      )
    ''');

    // ==========================================================
    // DO NOT CREATE daily_todo_settings
    //
    // The repository handles the date reset using
    // completion_date directly in daily_todo_tasks.
    //
    // Therefore there is no need for another table.
    // ==========================================================

    // ==========================================================
    // SAVED LINKS
    // ==========================================================

    await db.execute('''
      CREATE TABLE saved_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        title TEXT,

        url TEXT NOT NULL,

        sort_order INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        updated_at TEXT
      )
    ''');

    // ==========================================================
    // DEFAULT SADHANA TYPES
    // ==========================================================

    final now = DateTime.now().toIso8601String();

    await db.insert('sadhana_types', {
      'name': 'Chanting',
      'icon': '📿',
      'is_active': 1,
      'sort_order': 1,
      'created_at': now,
    });

    await db.insert('sadhana_types', {
      'name': 'Reading',
      'icon': '📖',
      'is_active': 1,
      'sort_order': 2,
      'created_at': now,
    });

    await db.insert('sadhana_types', {
      'name': 'Hearing',
      'icon': '🎧',
      'is_active': 1,
      'sort_order': 3,
      'created_at': now,
    });

    await db.insert('sadhana_types', {
      'name': 'Aarti',
      'icon': '🪔',
      'is_active': 1,
      'sort_order': 4,
      'created_at': now,
    });
  }
}
