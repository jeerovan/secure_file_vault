import '../utils/common.dart';
import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelTransfer {
  String id;
  int download;
  int progress;
  int updatedAt;

  ModelTransfer(
      {required this.id,
      required this.download,
      required this.progress,
      required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'download': download,
      'progress': progress,
      'updated_at': updatedAt
    };
  }

  static Future<ModelTransfer> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelTransfer(
        id: map['id'],
        download: map['download'],
        progress: getValueFromMap(map, "progress", defaultValue: 0),
        updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow));
  }

  static Future<ModelTransfer?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.transfers.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  static Future<void> deleteTransfer(String id) async {
    ModelTransfer? transfer = await get(id);
    if (transfer != null) {
      transfer.delete();
    }
  }

  static Future<String?> fetchPendingUpload(Set<String> activeUploads) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;

    String query = 'SELECT id FROM transfers WHERE download = 0';
    List<dynamic> args = [];

    // Dynamically exclude currently running uploadIds (item_id)
    if (activeUploads.isNotEmpty) {
      final String placeholders =
          List.filled(activeUploads.length, '?').join(',');
      query += ' AND id NOT IN ($placeholders)';
      args.addAll(activeUploads);
    }

    // Process oldest created/updated transfers first
    query += ' ORDER BY updated_at ASC LIMIT 1';

    final List<Map<String, dynamic>> results = await db.rawQuery(query, args);

    if (results.isNotEmpty) {
      return results.first['id'] as String;
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.transfers.string, map);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    Map<String, dynamic> updatedMap = {"updated_at": utcNow};
    for (String attr in attrs) {
      updatedMap[attr] = map[attr];
    }
    int updated =
        await dbHelper.update(Tables.transfers.string, updatedMap, id);
    return updated;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.transfers.string, id);
    // delete related categories
    return deleted;
  }

  static Future<void> clear() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.delete(Tables.transfers.string);
  }
}
