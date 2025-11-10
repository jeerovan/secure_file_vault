import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/models/model_preferences.dart';
import 'package:uuid/uuid.dart';
import '../storage/storage_sqlite.dart';

class ModelFile {
  String? id;
  FileType type;
  int size;
  Uint8List? thumbnail;
  int? duration;
  int? state;
  int? archivedAt;
  int? createdAt;
  int? updatedAt;

  ModelFile({
    this.id,
    required this.type,
    required this.size,
    this.thumbnail,
    this.duration,
    this.state,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'size': size,
      'thumbnail': thumbnail == null ? null : base64Encode(thumbnail!),
      'duration': duration,
      'state': state,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt
    };
  }

  static Future<ModelFile> fromMap(Map<String, dynamic> map) async {
    Uuid uuid = const Uuid();
    Uint8List? thumbnail;
    if (map.containsKey("thumbnail")) {
      if (map["thumbnail"] is String) {
        thumbnail = base64Decode(map["thumbnail"]);
      } else {
        thumbnail = map["thumbnail"];
      }
    }
    FileType fileType = FileType.document;
    if (map.containsKey('type')) {
      if (map['type'] is FileType) {
        fileType = map['type'];
      } else {
        fileType = ItemTypeExtension.fromValue(map['type'])!;
      }
    }
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelFile(
      id: map.containsKey('id') ? map['id'] : uuid.v4(),
      thumbnail: thumbnail,
      duration: getValueFromMap(map, "duration", defaultValue: 0),
      size: getValueFromMap(map, "size", defaultValue: 0),
      type: fileType,
      state: getValueFromMap(map, "state", defaultValue: 0),
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<ModelFile?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("item", id);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
  }

  static Future<List<ModelFile>> getForType(FileType itemType) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows =
        await db.query("item", where: "type = ?", whereArgs: [itemType.value]);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert("item", map);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (syncEnabled) {
      map["table"] = "item";
      /* SyncUtils.encryptAndPushChange(
        map,
      ); */
    }
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
    int updated = await dbHelper.update("item", updatedMap, id);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (pushToSync && syncEnabled) {
      map["updated_at"] = utcNow;
      map["table"] = "item";
      //SyncUtils.encryptAndPushChange(map, mediaChanges: false);
    }
    return updated;
  }

  Future<int> upcertFromServer() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("item", id);
    if (rows.isEmpty) {
      result = await dbHelper.insert("item", map);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update("item", map, id);
      } else {
        result = 0;
      }
    }
    // signal item update
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
    return result;
  }

  Future<int> delete({bool withServerSync = false}) async {
    final dbHelper = StorageSqlite.instance;
    int deleteTask = 2;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete("item", id);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (withServerSync && syncEnabled) {
      map["updated_at"] = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["table"] = "item";
      /* SyncUtils.encryptAndPushChange(
        map,
        deleteTask: deleteTask,
      ); */
    }
    return deleted;
  }

  static Future<void> deletedFromServer(String id) async {
    ModelFile? item = await ModelFile.get(id);
    if (item != null) {
      await item.delete();
    }
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
  }
}
