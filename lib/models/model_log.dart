import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelLog {
  final int? id;
  final String log;

  ModelLog({this.id, required this.log});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'log': log,
    };
  }

  static Future<ModelLog> fromMap(Map<String, dynamic> map) async {
    return ModelLog(
      id: map['id'],
      log: map['log'],
    );
  }

  @override
  String toString() {
    return 'Log(id: $id, log: $log)';
  }

  static Future<List<ModelLog>> all(List<String> words) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<String> searches = [];
    for (String word in words) {
      if (word != 'All') {
        searches.add(word);
      }
    }
    if (searches.isEmpty) {
      List<Map<String, dynamic>> rows =
          await db.query(Tables.logs.string, orderBy: "id DESC");
      return await Future.wait(rows.map((map) => fromMap(map)));
    }

    // Build WHERE clause with OR conditions for each search term
    final where = searches.map((word) => 'log LIKE ?').join(' AND ');
    final args = searches.map((word) => '%$word%').toList();

    List<Map<String, dynamic>> rows = await db.query(Tables.logs.string,
        where: where, whereArgs: args, orderBy: "id DESC");
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelLog?> get(int id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.logs.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.logs.string, map);
    return inserted;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.logs.string, id);
    // delete related categories
    return deleted;
  }

  static Future<void> clear() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.delete(Tables.logs.string);
  }
}
