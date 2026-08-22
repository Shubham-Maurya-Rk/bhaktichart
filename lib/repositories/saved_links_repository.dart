import '../core/database/database_helper.dart';

class SavedLink {
  final int id;
  final String title;
  final String url;
  final int sortOrder;

  const SavedLink({
    required this.id,
    required this.title,
    required this.url,
    required this.sortOrder,
  });

  factory SavedLink.fromMap(Map<String, dynamic> map) {
    return SavedLink(
      id: map['id'] as int,
      title: (map['title'] as String?) ?? '',
      url: (map['url'] as String?) ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title, 'url': url, 'sort_order': sortOrder};
  }

  SavedLink copyWith({int? id, String? title, String? url, int? sortOrder}) {
    return SavedLink(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class SavedLinksRepository {
  SavedLinksRepository._privateConstructor();

  static final SavedLinksRepository instance =
      SavedLinksRepository._privateConstructor();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // ============================================================
  // GET ALL LINKS
  // ============================================================

  Future<List<SavedLink>> getAllLinks() async {
    final db = await _databaseHelper.database;

    final result = await db.query(
      'saved_links',
      orderBy: 'sort_order ASC, id ASC',
    );

    return result.map(SavedLink.fromMap).toList();
  }

  // ============================================================
  // ADD LINK
  // ============================================================

  Future<int> addLink({required String title, required String url}) async {
    final db = await _databaseHelper.database;

    final existing = await db.query(
      'saved_links',
      columns: ['MAX(sort_order) AS max_order'],
    );

    int maxOrder = 0;

    if (existing.isNotEmpty && existing.first['max_order'] != null) {
      maxOrder = (existing.first['max_order'] as num).toInt() + 1;
    }

    final now = DateTime.now().toIso8601String();

    return await db.insert('saved_links', {
      'title': title.trim(),
      'url': url.trim(),
      'sort_order': maxOrder,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ============================================================
  // DELETE LINK
  // ============================================================

  Future<void> deleteLink(int id) async {
    final db = await _databaseHelper.database;

    await db.delete('saved_links', where: 'id = ?', whereArgs: [id]);

    await _normalizeSortOrder();
  }

  // ============================================================
  // REORDER LINKS
  // ============================================================

  Future<void> reorderLinks(int oldIndex, int newIndex) async {
    final links = await getAllLinks();

    if (oldIndex < 0 || oldIndex >= links.length) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (newIndex < 0) {
      newIndex = 0;
    }

    if (newIndex >= links.length) {
      newIndex = links.length - 1;
    }

    final movedLink = links.removeAt(oldIndex);

    links.insert(newIndex, movedLink);

    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      for (int index = 0; index < links.length; index++) {
        await txn.update(
          'saved_links',
          {'sort_order': index, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [links[index].id],
        );
      }
    });
  }

  // ============================================================
  // UPDATE LINK
  // ============================================================

  Future<void> updateLink({
    required int id,
    required String title,
    required String url,
  }) async {
    final db = await _databaseHelper.database;

    await db.update(
      'saved_links',
      {
        'title': title.trim(),
        'url': url.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================
  // CLEAR ALL
  // ============================================================

  Future<void> clearAllLinks() async {
    final db = await _databaseHelper.database;

    await db.delete('saved_links');
  }

  // ============================================================
  // NORMALIZE SORT ORDER
  // ============================================================

  Future<void> _normalizeSortOrder() async {
    final links = await getAllLinks();

    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      for (int index = 0; index < links.length; index++) {
        await txn.update(
          'saved_links',
          {'sort_order': index, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [links[index].id],
        );
      }
    });
  }
}
