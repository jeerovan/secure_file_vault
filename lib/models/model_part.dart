import 'dart:convert';

import '../utils/enums.dart';
import '../utils/utils_sync.dart';

import '../utils/common.dart';
import '../storage/storage_sqlite.dart';

class ModelPart {
  String id;
  int size;
  String cipher;
  String nonce;
  Map<String, dynamic> data;
  int updatedAt;

  ModelPart(
      {required this.id,
      required this.size,
      required this.cipher,
      required this.nonce,
      required this.data,
      required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'size': size,
      'cipher': cipher,
      'nonce': nonce,
      'data': data is String ? data : jsonEncode(data),
      'updated_at': updatedAt,
    };
  }

  static Future<ModelPart> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    final data = getValueFromMap(map, "data", defaultValue: "{}");
    return ModelPart(
      id: map['id'],
      size: map['size'],
      cipher: map["cipher"],
      nonce: map["nonce"],
      data: data is String ? jsonDecode(data) : data,
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<List<String>> shasForFileId(String fileId, int parts) async {
    List<String> shas = [];
    int part = 1;
    while (part <= parts) {
      String tableKey = '${fileId}_$part';
      ModelPart? modelPart = await get(tableKey);
      if (modelPart != null) {
        Map<String, dynamic> data = modelPart.data;
        if (data.containsKey("sha1")) {
          shas.add(data["sha1"]);
        }
      }
      part++;
    }
    return shas;
  }

  static Future<ModelPart?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.parts.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.parts.string, map);
    map["table"] = Tables.parts.string;
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
    int updated = await dbHelper.update(Tables.parts.string, updatedMap, id);
    if (pushToSync) {
      map["updated_at"] = utcNow;
      map["table"] = Tables.parts.string;
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
        await dbHelper.getWithId(Tables.parts.string, id);
    if (rows.isEmpty) {
      result = await dbHelper.insert(Tables.parts.string, map);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update(Tables.parts.string, map, id);
      } else {
        result = 0;
      }
    }
    // signal item update
    // EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
    return result;
  }

  Future<int> delete({bool pushToSync = false}) async {
    final dbHelper = StorageSqlite.instance;
    int deleteTask = 1;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete(Tables.parts.string, id);
    if (pushToSync) {
      map["updated_at"] = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["table"] = Tables.parts.string;
      SyncUtils.logChangeToPush(
        map,
        deleteTask: deleteTask,
      );
    }
    return deleted;
  }
}
