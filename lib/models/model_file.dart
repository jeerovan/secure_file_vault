import 'dart:convert';

import '../utils/utils_sync.dart';

import '../utils/common.dart';
import '../utils/enums.dart';
import '../storage/storage_sqlite.dart';

class ModelFile {
  String id;
  int itemCount;
  int parts;
  int uploadedAt;
  int? storageId;
  int? providerId;
  Map<String, dynamic> data;
  int updatedAt;

  ModelFile({
    required this.id,
    required this.itemCount,
    required this.parts,
    required this.uploadedAt,
    this.providerId,
    this.storageId,
    required this.data,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_count': itemCount,
      'parts': parts,
      'uploaded_at': uploadedAt,
      'storage_id': storageId,
      'provider_id': providerId,
      'data': data is String ? data : jsonEncode(data),
      'updated_at': updatedAt
    };
  }

  static Future<ModelFile> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    final data = getValueFromMap(map, "data", defaultValue: "{}");
    return ModelFile(
      id: map["id"],
      itemCount: getValueFromMap(map, "item_count", defaultValue: 1),
      parts: getValueFromMap(map, "parts", defaultValue: 0),
      uploadedAt: getValueFromMap(map, "uploaded_at", defaultValue: 0),
      storageId: getValueFromMap(map, "storage_id", defaultValue: null),
      providerId: getValueFromMap(map, "provider_id", defaultValue: null),
      data: data is String ? jsonDecode(data) : data,
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<ModelFile> fromServerMap(Map<String, dynamic> changeMap) async {
    final data = changeMap["12"];
    return ModelFile(
      id: changeMap["6"],
      itemCount: int.parse(changeMap["7"].toString()),
      parts: int.parse(changeMap["8"].toString()),
      uploadedAt: int.parse(changeMap["9"].toString()),
      providerId: int.tryParse(changeMap["10"].toString()),
      storageId: int.tryParse(changeMap["11"].toString()),
      data: data is String ? jsonDecode(data) : data,
      updatedAt: int.parse(changeMap["13"].toString()),
    );
  }

  static Future<List<ModelFile>> pendingForUpload() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db
        .query(Tables.files.string, where: "uploaded_at = ?", whereArgs: [0]);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelFile?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.files.string, id);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<void> updateCount(int count) async {
    itemCount = count;
    await update(["item_count"]);
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.files.string, map);
    map["table"] = Tables.files.string;
    SyncUtils.logChangeToPush(
      map,
    );
    return inserted;
  }

  Future<int> update(List<String> attrs, {bool pushToSync = true}) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    Map<String, dynamic> updatedMap = {"updated_at": utcNow};
    for (String attr in attrs) {
      updatedMap[attr] = map[attr];
    }
    int updated = await dbHelper.update(Tables.files.string, updatedMap, id);
    if (pushToSync) {
      map["updated_at"] = utcNow;
      map["table"] = Tables.files.string;
      SyncUtils.logChangeToPush(
        map,
      );
    }
    return updated;
  }

  Future<int> upcertFromServer({bool overwrite = false}) async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.files.string, id);
    if (rows.isEmpty) {
      result = await dbHelper.insert(Tables.files.string, map);
    } else if (overwrite) {
      result = await dbHelper.update(Tables.files.string, map, id);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update(Tables.files.string, map, id);
      } else {
        result = 0;
      }
    }
    return result;
  }

  Future<int> delete({bool pushToSync = true}) async {
    final dbHelper = StorageSqlite.instance;
    int deleteTask = 1;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete(Tables.files.string, id);
    if (pushToSync) {
      map["updated_at"] = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["table"] = Tables.files.string;
      SyncUtils.logChangeToPush(
        map,
        deleteTask: deleteTask,
      );
    }
    return deleted;
  }

  static Future<void> deletedFromServer(String id, int remoteUpdatedAt) async {
    ModelFile? file = await ModelFile.get(id);
    if (file != null) {
      if (file.updatedAt > remoteUpdatedAt) return;
      await file.delete(pushToSync: false);
    }
  }
}
