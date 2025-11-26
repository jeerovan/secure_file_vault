import 'dart:convert';
import '../utils/common.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';

import '../utils/enums.dart';
import '../storage/storage_sqlite.dart';

class ModelChange {
  static AppLogger logger = AppLogger(prefixes: ["ModelChange"]);

  String id;
  String table;
  String data;
  int type;
  Map<String, dynamic>? map;

  ModelChange({
    required this.id,
    required this.table,
    required this.data,
    required this.type,
    this.map,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table': table,
      'data': data,
      'type': type,
      'map': map == null
          ? null
          : map is String
              ? map
              : jsonEncode(map),
    };
  }

  static Future<ModelChange> fromMap(Map<String, dynamic> map) async {
    Map<String, dynamic>? dataMap;
    if (map.containsKey('map') && map['map'] != null) {
      if (map['map'] is String) {
        dataMap = jsonDecode(map['map']);
      } else {
        dataMap = map['map'];
      }
    }
    return ModelChange(
      id: map['id'],
      table: map['table'],
      data: map['data'],
      type: getValueFromMap(map, 'type'),
      map: dataMap,
    );
  }

  static Future<void> addUpdate(
      String changeId, String table, String changeData, int changeType,
      {Map<String, dynamic>? dataMap}) async {
    ModelChange change = await ModelChange.fromMap({
      'id': changeId,
      'table': table,
      'data': changeData,
      'type': changeType,
      'map': jsonEncode(dataMap),
    });
    await change.upcert();
  }

  static Future<List<ModelChange>> all() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "change",
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresMapPushForTable(String table) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<dynamic> changeTypes = [
      SyncChangeTask.pushMap.value,
      SyncChangeTask.pushMapFile.value,
      SyncChangeTask.pushMapDeleteFile.value
    ];
    // Generate placeholders (?, ?, ?) for the number of IDs
    final placeholders = List.filled(changeTypes.length, '?').join(',');
    changeTypes.insert(0, table);
    int? limitOnItemsOnly = table == "item" ? 100 : null;
    List<Map<String, dynamic>> rows = await db.query("change",
        where: "name = ? AND type IN ($placeholders)",
        whereArgs: changeTypes,
        limit: limitOnItemsOnly);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFilePush() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.pushFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      "change",
      where: "type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFileDelete() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.deleteFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      "change",
      where: "type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFileFetch() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.fetchFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      "change",
      where: "type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<void> upgradeTypeForIds(List<String> ids) async {
    for (String id in ids) {
      await upgradeSyncTask(id);
    }
  }

  static Future<void> upgradeSyncTask(String changeId,
      {bool updateState = true}) async {
    ModelChange? change = await get(changeId);
    if (change != null) {
      SyncChangeTask? currentType =
          SyncChangeTaskExtension.fromValue(change.type);
      SyncChangeTask nextTaskType = getNextTaskType(currentType!);
      SyncState newState = getNextSyncState(currentType);
      if (updateState) await updateTypeState(changeId, newState);
      if (nextTaskType == SyncChangeTask.delete) {
        await change.delete();
      } else {
        change.type = nextTaskType.value;
        await change.update(["type"]);
        logger.info(
            "upgradeType|${change.id}|${currentType.value}->${nextTaskType.value}");
      }
    }
  }

  static Future<void> updateTypeState(
      String changeId, SyncState newState) async {
    ModelChange? change = await get(changeId);
    if (change != null) {
      String table = change.table;
      List<String> userIdRowId = changeId.split("|");
      String rowId = userIdRowId[1];
      switch (table) {}
    }
  }

  static Future<ModelChange?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list = await dbHelper.getWithId("change", id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert("change", map);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    Map<String, dynamic> updateMap = {};
    for (String attr in attrs) {
      updateMap[attr] = map[attr];
    }
    int updated = await dbHelper.update("change", updateMap, id);
    return updated;
  }

  Future<int> upcert() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("change", id);
    if (rows.isEmpty) {
      result = await dbHelper.insert("change", map);
    } else {
      result = await dbHelper.update("change", map, id);
    }
    return result;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete("change", id);
    return deleted;
  }

  Future<int> deleteWithItem() async {
    List<String> userIdRowId = id.split("|");
    String rowId = userIdRowId.last;
    ModelItem? item = await ModelItem.get(rowId);
    if (item != null) {
      await item.delete(withServerSync: true);
    }
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete("change", id);
    return deleted;
  }

  static SyncChangeTask getPushChangeTaskType(
      String table, Map<String, dynamic> map) {
    switch (table) {
      case "part":
        return SyncChangeTask.pushMapFile;
      default:
        return SyncChangeTask.pushMap;
    }
  }

  static SyncState getNextSyncState(SyncChangeTask current) {
    switch (current) {
      case SyncChangeTask.pushMap:
      case SyncChangeTask.pushFile:
        return SyncState.uploaded;
      case SyncChangeTask.pushMapFile:
        return SyncState.uploading;
      // download types
      case SyncChangeTask.fetchFile:
        return SyncState.downloaded;
      default:
        return SyncState.initial;
    }
  }

  static SyncChangeTask getNextTaskType(SyncChangeTask current) {
    switch (current) {
      //upload types
      case SyncChangeTask.delete:
      case SyncChangeTask.pushMap:
      case SyncChangeTask.pushFile:
        return SyncChangeTask.delete;
      case SyncChangeTask.pushMapFile:
        return SyncChangeTask.pushFile;
      // download types
      case SyncChangeTask.fetchFile:
        return SyncChangeTask.delete;
      // delete types
      case SyncChangeTask.pushMapDeleteFile:
        return SyncChangeTask.deleteFile;
      case SyncChangeTask.deleteFile:
        return SyncChangeTask.delete;
    }
  }
}
