import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/models/model_preferences.dart';
import '../storage/storage_sqlite.dart';

class ModelFile {
  String id;
  FileType type;
  int size;
  Uint8List? thumbnail;
  int? duration;
  int state;
  int referenceCount;
  int chunkCount;
  int modifiedAt;
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
    required this.referenceCount,
    required this.chunkCount,
    required this.modifiedAt,
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
      'reference_count': referenceCount,
      'chunk_count': chunkCount,
      'archived_at': archivedAt,
      'modified_at': modifiedAt,
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
      thumbnail: thumbnail,
      duration: getValueFromMap(map, "duration", defaultValue: 0),
      size: getValueFromMap(map, "size", defaultValue: 0),
      type: fileType,
      state: getValueFromMap(map, "state", defaultValue: 0),
      referenceCount: getValueFromMap(map, "reference_count", defaultValue: 0),
      chunkCount: getValueFromMap(map, "chunk_count", defaultValue: 0),
      modifiedAt: getValueFromMap(map, "modified_at", defaultValue: 0),
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<void> updateReferenceCount(ModelFile file, bool added) async {
    if (added) {
      file.referenceCount = file.referenceCount + 1;
    } else {
      file.referenceCount = file.referenceCount - 1;
    }
    await file.update(["reference_count"]);
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
