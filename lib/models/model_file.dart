import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_preferences.dart';
import '../storage/storage_sqlite.dart';

class ModelFile {
  String id;
  FileType type;
  int size;
  Uint8List? thumbnail;
  int? duration;
  int state;
  int itemCount;
  int parts;
  int partsUploaded;
  int uploadedAt;
  String? b2Id;
  int archivedAt;
  int createdAt;
  int updatedAt;

  ModelFile({
    required this.id,
    required this.type,
    required this.size,
    this.thumbnail,
    required this.duration,
    required this.state,
    required this.itemCount,
    required this.parts,
    required this.partsUploaded,
    required this.uploadedAt,
    this.b2Id,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'size': size,
      'thumbnail': thumbnail == null ? null : base64Encode(thumbnail!),
      'duration': duration,
      'state': state,
      'item_count': itemCount,
      'parts': parts,
      'parts_uploaded': partsUploaded,
      'uploaded_at': uploadedAt,
      'b2_id': b2Id,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt
    };
  }

  static Future<ModelFile> fromMap(Map<String, dynamic> map) async {
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
      id: map["id"],
      type: fileType,
      size: getValueFromMap(map, "size", defaultValue: 0),
      thumbnail: thumbnail,
      duration: getValueFromMap(map, "duration", defaultValue: 0),
      state: getValueFromMap(map, "state", defaultValue: 0),
      itemCount: getValueFromMap(map, "item_count", defaultValue: 0),
      parts: getValueFromMap(map, "parts", defaultValue: 0),
      partsUploaded: getValueFromMap(map, "parts_uploaded", defaultValue: 0),
      uploadedAt: getValueFromMap(map, "uploaded_at", defaultValue: 0),
      b2Id: getValueFromMap(map, "b2_id", defaultValue: ""),
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<void> updateItemCount(ModelFile file, bool added) async {
    if (added) {
      file.itemCount = file.itemCount + 1;
    } else {
      file.itemCount = file.itemCount - 1;
    }
    await file.update(["item_count"]);
    // TODO if count is zero, add for deletion
  }

  static Future<ModelFile?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("file", id);
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
        await db.query("file", where: "type = ?", whereArgs: [itemType.value]);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert("file", map);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (syncEnabled) {
      map["table"] = "file";
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
    int updated = await dbHelper.update("file", updatedMap, id);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (pushToSync && syncEnabled) {
      map["updated_at"] = utcNow;
      map["table"] = "file";
      //SyncUtils.encryptAndPushChange(map, mediaChanges: false);
    }
    return updated;
  }

  Future<int> upcertFromServer() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("file", id);
    if (rows.isEmpty) {
      result = await dbHelper.insert("file", map);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update("file", map, id);
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
    int deleted = await dbHelper.delete("file", id);
    bool syncEnabled = await ModelPreferences.get(
            AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (withServerSync && syncEnabled) {
      map["updated_at"] = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["table"] = "file";
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
