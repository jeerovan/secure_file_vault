import 'package:file_vault_bb/utils/utils_sync.dart';

import '../models/model_file.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import 'model_state.dart';
import 'package:uuid/uuid.dart';
import '../storage/storage_sqlite.dart';
import 'package:path/path.dart' as path_lib;

class ModelItem {
  String id;
  String? path;
  String name;
  bool isFolder;
  String? parentId;
  String? rootId;
  int scanState;
  String? fileId;
  int size;
  int archivedAt;
  int createdAt;
  int updatedAt;

  ModelItem({
    required this.id,
    this.path,
    required this.name,
    required this.isFolder,
    this.parentId,
    this.rootId,
    required this.scanState,
    this.fileId,
    required this.size,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'is_folder': isFolder ? 1 : 0,
      'parent_id': parentId,
      'root_id': rootId,
      'scan_state': scanState,
      'file_id': fileId,
      'size': size,
      'archived_at': archivedAt,
      'created_at': createdAt,
      'updated_at': updatedAt
    };
  }

  // -- Examples --
  // DeviceFolder: id:DeviceId,name:DeviceName
  // SyncFolder: itemId:DeviceFolderId,Path:FolderPath,name:path.basename(FolderPath)
  // ChildFolder: itemId:ParentFolderId,name: path.basename(ChildFolderPath)

  static Future<ModelItem> fromMap(Map<String, dynamic> map) async {
    Uuid uuid = const Uuid();
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelItem(
      id: map.containsKey('id') ? map['id'] : uuid.v4(),
      path: getValueFromMap(map, "path", defaultValue: null),
      name: getValueFromMap(map, "name", defaultValue: ""),
      isFolder: getValueFromMap(map, "is_folder", defaultValue: 0) == 1,
      parentId: getValueFromMap(map, "parent_id", defaultValue: null),
      rootId: getValueFromMap(map, "root_id", defaultValue: null),
      scanState: getValueFromMap(map, "scan_state", defaultValue: 0),
      fileId: getValueFromMap(map, "file_id", defaultValue: null),
      size: getValueFromMap(map, "size", defaultValue: 0),
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<List<ModelItem>> getAllInFolder(ModelItem? item) async {
    if (item == null) return [];
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "parent_id = ?",
      whereArgs: [
        item.id,
      ],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelItem?> getParentItem(ModelItem? item) async {
    if (item == null) return null;
    ModelItem? currentItem = await get(item.id);
    ModelItem? parentItem;
    if (currentItem != null) {
      String? parentItemId = currentItem.parentId;
      if (parentItemId != null) {
        parentItem = await get(parentItemId);
      }
    }
    return parentItem;
  }

  static Future<List<ModelItem>> getAllUnScannedFolderForRootItemId(
      String itemId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "root_id = ? AND is_folder = ? AND scan_state = ?",
      whereArgs: [itemId, 1, 0],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getAllUnScannedFilesForRootItemIdMatchingSize(
      String itemId, int size) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "root_id = ? AND is_folder = ? AND scan_state = ? AND size = ?",
      whereArgs: [itemId, 0, 0, size],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getAllUnScannedFilesForRootItemIdMatchingHash(
      String itemId, String hash) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "root_id = ? AND is_folder = ? AND scan_state = ? AND file_id = ?",
      whereArgs: [itemId, 0, 0, hash],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getAllUnScannedItemsForRootItemId(
      String itemId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "root_id = ? AND scan_state = ?",
      whereArgs: [itemId, 0],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getArchived() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "archived_at > ?",
      whereArgs: [0],
      orderBy: 'at DESC',
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<String> getPathForItem(String id) async {
    ModelItem? item = await get(id);
    List<String> pathParts = [];
    while (item?.path == null) {
      pathParts.add(item!.name);
      item = await get(item.parentId!);
    }
    String path = item!.path!;
    String pathItems = path_lib.joinAll(pathParts.reversed);
    return path_lib.join(path, pathItems);
  }

  static Future<void> resetScanState(String rootItemId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.update(Tables.items.string, {"scan_state": 0},
        where: "root_id = ?", whereArgs: [rootItemId]);
  }

  static Future<void> setScanState(String itemId, int state) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.update(Tables.items.string, {"scan_state": state},
        where: "id = ?", whereArgs: [itemId]);
  }

  static Future<void> removeAllSyncedFolders() async {
    final deviceId = await getDeviceId();
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.delete(Tables.items.string,
        where: "path != ? AND parent_id = ?", whereArgs: [null, deviceId]);
  }

  static Future<List<ModelItem>> searchItem(String term) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.rawQuery('''
        SELECT * FROM items 
        WHERE rowid IN (
            SELECT docid FROM items_fts WHERE name MATCH '$term'
        );
      ''');
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelItem?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.items.string, id);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.items.string, map);

    bool syncEnabled = await ModelState.get(AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (syncEnabled) {
      map["table"] = Tables.items.string;
      SyncUtils.logChangeToPush(
        map,
      );
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
    int updated = await dbHelper.update(Tables.items.string, updatedMap, id);
    bool syncEnabled = await ModelState.get(AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (pushToSync && syncEnabled) {
      map["updated_at"] = utcNow;
      map["table"] = Tables.items.string;
      SyncUtils.logChangeToPush(map, mediaChanges: false);
    }
    return updated;
  }

  Future<int> upcertFromServer() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows =
        await dbHelper.getWithId(Tables.items.string, id);
    if (rows.isEmpty) {
      result = await insert();
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        result = await dbHelper.update(Tables.items.string, map, id);
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
    int deleteTask = 1;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete("items", id);

    bool syncEnabled = await ModelState.get(AppString.hasEncryptionKeys.string,
            defaultValue: "no") ==
        "yes";
    if (withServerSync && syncEnabled) {
      map["updated_at"] = DateTime.now().toUtc().millisecondsSinceEpoch;
      map["table"] = Tables.items.string;
      SyncUtils.logChangeToPush(
        map,
        deleteTask: deleteTask,
      );
    }
    return deleted;
  }

  static Future<void> deletedFromServer(String id) async {
    ModelItem? item = await ModelItem.get(id);
    if (item != null) {
      await item.delete();
    }
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
  }
}
