import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _databaseName = 'bhaktichart.db';

  static const int _databaseVersion = 3;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();

    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,

      version: _databaseVersion,

      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      onCreate: _onCreate,

      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // --------------------------------------------------
    // VERSION 2
    // --------------------------------------------------

    if (oldVersion < 2) {
      await db.execute('''
      ALTER TABLE day_notes
      ADD COLUMN is_sankirtan INTEGER NOT NULL DEFAULT 0
    ''');

      await db.execute('''
      ALTER TABLE day_notes
      ADD COLUMN is_ekadashi INTEGER NOT NULL DEFAULT 0
    ''');

      await db.execute('''
      ALTER TABLE day_notes
      ADD COLUMN is_festival INTEGER NOT NULL DEFAULT 0
    ''');
    }

    // --------------------------------------------------
    // VERSION 3 - DAILY ROUTINE
    // --------------------------------------------------

    if (oldVersion < 3) {
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
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // --------------------------------------------------
    // USERS
    // --------------------------------------------------

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    // --------------------------------------------------
    // DAILY ROUTINE
    // --------------------------------------------------

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

    // --------------------------------------------------
    // DAILY ROUTINE GOALS
    // --------------------------------------------------

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

    // --------------------------------------------------
    // SADHANA TYPES
    // --------------------------------------------------

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

    // --------------------------------------------------
    // DAILY SADHANA
    // --------------------------------------------------

    await db.execute('''
      CREATE TABLE daily_sadhana (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        user_id INTEGER NOT NULL,

        date TEXT NOT NULL,

        sadhana_type_id INTEGER NOT NULL,

        value REAL NOT NULL DEFAULT 0,

        unit TEXT,

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

    // --------------------------------------------------
    // READING SETTINGS
    // --------------------------------------------------

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

    // --------------------------------------------------
    // AARTI TYPES
    // --------------------------------------------------

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

    // --------------------------------------------------
    // DAILY AARTI
    // --------------------------------------------------

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

        FOREIGN KEY (aarti_type_id)
          REFERENCES aarti_types(id)
          ON DELETE CASCADE,

        UNIQUE (
          user_id,
          aarti_type_id,
          date
        )
      )
    ''');

    // --------------------------------------------------
    // DAY NOTES
    // --------------------------------------------------

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

    // --------------------------------------------------
    // GOALS
    // --------------------------------------------------

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

    // --------------------------------------------------
    // DEFAULT SADHANA TYPES
    // --------------------------------------------------

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
