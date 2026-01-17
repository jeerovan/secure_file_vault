import 'package:file_vault_bb/utils/utils_sync.dart';

import '../utils/common.dart';
import '../utils/enums.dart';
import '../storage/storage_sqlite.dart';

class ModelFile {
  String id;
  int itemCount;
  int parts;
  int partsUploaded;
  int uploadedAt;
  String? remoteId;
  String? accessToken;
  int tokenExpiry;
  int createdAt;
  int updatedAt;

  ModelFile({
    required this.id,
    required this.itemCount,
    required this.parts,
    required this.partsUploaded,
    required this.uploadedAt,
    this.remoteId,
    this.accessToken,
    required this.tokenExpiry,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_count': itemCount,
      'parts': parts,
      'parts_uploaded': partsUploaded,
      'uploaded_at': uploadedAt,
      'remote_id': remoteId,
      'access_token': accessToken,
      'token_expiry': tokenExpiry,
      'created_at': createdAt,
      'updated_at': updatedAt
    };
  }

  static Future<ModelFile> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelFile(
      id: map["id"],
      itemCount: getValueFromMap(map, "item_count", defaultValue: 1),
      parts: getValueFromMap(map, "parts", defaultValue: 0),
      partsUploaded: getValueFromMap(map, "parts_uploaded", defaultValue: 0),
      uploadedAt: getValueFromMap(map, "uploaded_at", defaultValue: 0),
      remoteId: getValueFromMap(map, "remote_id", defaultValue: null),
      accessToken: getValueFromMap(map, "access_token", defaultValue: null),
      tokenExpiry: getValueFromMap(map, "token_expiry", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<void> updateItemCount(String fileId, bool added) async {
    ModelFile? file = await get(fileId);
    if (file == null) return;
    if (added) {
      file.itemCount = file.itemCount + 1;
    } else {
      file.itemCount = file.itemCount - 1;
    }
    await file.update(["item_count"]);
    // TODO if count is zero, add for deletion
  }

  static Future<List<ModelFile>> pendingForPush() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db
        .query(Tables.files.string, where: "uploaded_at  > ?", whereArgs: [0]);
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

  Future<int> upcertFromServer() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.files.string, id);
    if (rows.isEmpty) {
      result = await dbHelper.insert(Tables.files.string, map);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update(Tables.files.string, map, id);
      } else {
        result = 0;
      }
    }
    // signal item update
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
    return result;
  }

  Future<int> delete({bool pushToSync = false}) async {
    final dbHelper = StorageSqlite.instance;
    int deleteTask = 2;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete(Tables.files.string, id);
    //TODO parts should be deleted also
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

  static Future<void> deletedFromServer(String id) async {
    ModelFile? item = await ModelFile.get(id);
    if (item != null) {
      await item.delete();
    }
    // TODO delete parts also
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
  }
}
