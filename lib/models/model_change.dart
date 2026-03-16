import 'dart:convert';
import '../utils/common.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';

import '../utils/enums.dart';
import '../storage/storage_sqlite.dart';

class ModelChange {
  static AppLogger logger = AppLogger(prefixes: ["ModelChange"]);

  String id;
  String tableName;
  Map<String, dynamic> changedData;
  int changeType;
  int updatedAt;

  ModelChange(
      {required this.id,
      required this.tableName,
      required this.changedData,
      required this.changeType,
      required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_name': tableName,
      'changed_data':
          changedData is String ? changedData : jsonEncode(changedData),
      'change_type': changeType,
      'updated_at': updatedAt
    };
  }

  static Future<ModelChange> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    final changedData = map['changed_data'];
    return ModelChange(
        id: map['id'],
        tableName: map['table_name'],
        changedData:
            changedData is String ? jsonDecode(changedData) : changedData,
        changeType: getValueFromMap(map, 'change_type'),
        updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow));
  }

  static Future<void> addUpdate(
      String changeId, String table, Object changedData, int changeType) async {
    ModelChange change = await ModelChange.fromMap({
      'id': changeId,
      'table_name': table,
      'changed_data': changedData,
      'change_type': changeType,
    });
    await change.upcert();
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
      {int singlePushLimit = 300}) async {
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
    List<Map<String, dynamic>> rows = await db.query(Tables.changes.string,
        where: "table_name = ? AND change_type IN ($placeholders)",
        whereArgs: changeTypes,
        limit: singlePushLimit);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFilePush() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.pushFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.changes.string,
      where: "change_type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFileDelete() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.deleteFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.changes.string,
      where: "change_type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelChange>> requiresFileFetch() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    int changeType = SyncChangeTask.fetchFile.value;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.changes.string,
      where: "change_type = ?",
      whereArgs: [changeType],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<void> updateChangeState(List<ModelChange> changes) async {
    for (ModelChange change in changes) {
      await upgradeChangeTask(change);
    }
  }

  static Future<void> upgradeChangeTask(ModelChange changeTask,
      {bool updateState = true}) async {
    ModelChange? change = await get(changeTask.id);
    if (change != null && change.updatedAt == changeTask.updatedAt) {
      SyncChangeTask? currentType =
          SyncChangeTaskExtension.fromValue(change.changeType);
      SyncChangeTask nextTaskType = getNextTaskType(currentType!);
      SyncState newState = getNextSyncState(currentType);
      if (updateState) await updateTypeState(change.id, newState);
      if (nextTaskType == SyncChangeTask.delete) {
        await change.delete();
      } else {
        change.changeType = nextTaskType.value;
        await change.update(["change_type"]);
        logger.info(
            "upgradeType|${change.id}|${currentType.value}->${nextTaskType.value}");
      }
    }
  }

  static Future<void> updateTypeState(
      String changeId, SyncState newState) async {
    ModelChange? change = await get(changeId);
    if (change != null) {
      String table = change.tableName;
      List<String> userIdRowId = changeId.split("|");
      String rowId = userIdRowId[1];
      switch (table) {}
    }
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

  Future<int> upcert() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.changes.string, id);
    if (rows.isEmpty) {
      result = await dbHelper.insert(Tables.changes.string, map);
    } else {
      int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["updated_at"] = utcNow;
      result = await dbHelper.update(Tables.changes.string, map, id);
    }
    return result;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.changes.string, id);
    return deleted;
  }

  Future<int> deleteWithItem() async {
    List<String> userIdRowId = id.split("|");
    String rowId = userIdRowId.last;
    ModelItem? item = await ModelItem.get(rowId);
    if (item != null) {
      await item.delete(pushToSync: true);
    }
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.changes.string, id);
    return deleted;
  }

  static SyncChangeTask getPushChangeTaskType(
      String table, Map<String, dynamic> map) {
    if (table == Tables.files.string) {
      return SyncChangeTask.pushMapFile;
    } else {
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
