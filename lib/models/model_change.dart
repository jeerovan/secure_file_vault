import 'dart:convert';
import '../utils/common.dart';
import '../services/service_logger.dart';

import '../utils/enums.dart';
import '../storage/storage_sqlite.dart';

class ModelChange {
  static AppLogger logger = AppLogger(prefixes: ["ModelChange"]);

  String id;
  String tableName;
  Map<String, dynamic> data;
  int updatedAt;

  ModelChange(
      {required this.id,
      required this.tableName,
      required this.data,
      required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_name': tableName,
      'data': data is String ? data : jsonEncode(data),
      'updated_at': updatedAt
    };
  }

  static Future<ModelChange> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    final changedData = map['data'];
    return ModelChange(
        id: map['id'],
        tableName: map['table_name'],
        data: changedData is String ? jsonDecode(changedData) : changedData,
        updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow));
  }

  static Future<List<ModelChange>> all() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.changes.string,
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> fetchForTable(String table,
      {int singlePushLimit = 100}) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(Tables.changes.string,
        where: "table_name = ?", whereArgs: [table], limit: singlePushLimit);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelChange?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.changes.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.changes.string, map);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    Map<String, dynamic> updateMap = {"updated_at": utcNow};
    for (String attr in attrs) {
      updateMap[attr] = map[attr];
    }
    int updated = await dbHelper.update(Tables.changes.string, updateMap, id);
    return updated;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.changes.string, id);
    return deleted;
  }
}
