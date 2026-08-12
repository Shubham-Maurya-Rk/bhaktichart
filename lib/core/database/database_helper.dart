import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper() {
    return instance;
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();

    final path = join(databasesPath, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Sadhana types
    await db.execute('''
      CREATE TABLE sadhana_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        unit TEXT NOT NULL,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Daily sadhana
    await db.execute('''
      CREATE TABLE daily_sadhana (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        sadhana_type_id INTEGER NOT NULL,
        value REAL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        UNIQUE(date, sadhana_type_id),

        FOREIGN KEY (sadhana_type_id)
          REFERENCES sadhana_types(id)
          ON DELETE CASCADE
      )
    ''');

    // Goals
    await db.execute('''
      CREATE TABLE goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sadhana_type_id INTEGER NOT NULL,
        target_value REAL NOT NULL,
        period TEXT NOT NULL,
        created_at TEXT NOT NULL,

        FOREIGN KEY (sadhana_type_id)
          REFERENCES sadhana_types(id)
          ON DELETE CASCADE
      )
    ''');

    // Settings
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await _insertDefaultSadhanaTypes(db);
  }

  Future<void> _insertDefaultSadhanaTypes(Database db) async {
    final types = [
      {'name': 'Chanting', 'icon': '📿', 'unit': 'rounds'},
      {'name': 'Reading', 'icon': '📖', 'unit': 'minutes'},
      {'name': 'Hearing', 'icon': '🎧', 'unit': 'minutes'},
      {'name': 'Aarti', 'icon': '🪔', 'unit': 'count'},
    ];

    for (final type in types) {
      await db.insert('sadhana_types', type);
    }
  }
}
