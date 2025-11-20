import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/models/model_preferences.dart';
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
  ModelFile? file;
  int size;
  int? thumbnail;
  int state;
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
    this.file,
    required this.size,
    this.thumbnail,
    required this.state,
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
      'file_id': file?.id,
      'size': size,
      'thumbnail': thumbnail,
      'state': state,
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
    String? fileId = getValueFromMap(map, "file_id", defaultValue: null);
    ModelFile? file;
    if (fileId != null) {
      file = await ModelFile.get(fileId);
    }
    return ModelItem(
      id: map.containsKey('id') ? map['id'] : uuid.v4(),
      path: getValueFromMap(map, "path", defaultValue: null),
      name: getValueFromMap(map, "name", defaultValue: ""),
      isFolder: getValueFromMap(map, "is_folder", defaultValue: 0) == 1,
      parentId: getValueFromMap(map, "parent_id", defaultValue: null),
      rootId: getValueFromMap(map, "root_id", defaultValue: null),
      scanState: getValueFromMap(map, "scan_state", defaultValue: 0),
      file: file,
      size: getValueFromMap(map, "size", defaultValue: 0),
      thumbnail: getValueFromMap(map, "thumbnail", defaultValue: 0),
      state: getValueFromMap(map, "state", defaultValue: 0),
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
      "item",
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
      "item",
      where: "root_id = ? AND is_folder = ? AND scan_state = ?",
      whereArgs: [itemId, 1, 0],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>>
      getAllUnScannedFilesForRootItemIdMatchingNameAndSize(
          String itemId, String name, int size) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
      where:
          "root_id = ? AND is_folder = ? AND scan_state = ? AND name = ? AND size = ?",
      whereArgs: [itemId, 0, 0, name, size],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getAllUnScannedFilesForRootItemIdMatchingHash(
      String itemId, String hash) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
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
      "item",
      where: "root_id = ? AND scan_state = ?",
      whereArgs: [itemId, 0],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getAllUnScannedForRootItemId(
      String itemId, String hash) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
      where: "root_id = ? AND scan_state = ?",
      whereArgs: [itemId, 0],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getArchived() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
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
    await db.execute(
        'UPDATE item SET scan_state = 0 WHERE root_id = ?', [rootItemId]);
  }

  static Future<void> setScanState(String itemId, int state) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.execute(
        'UPDATE item SET scan_state = ? WHERE id = ?', [state, itemId]);
  }

  static Future<List<ModelItem>> searchItem(String term) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.rawQuery('''
        SELECT * FROM item 
        WHERE rowid IN (
            SELECT docid FROM item_fts WHERE name MATCH '$term'
        );
      ''');
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelItem?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("item", id);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
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
    int deleteTask = 1;
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
    ModelItem? item = await ModelItem.get(id);
    if (item != null) {
      await item.delete();
    }
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
  }
}
