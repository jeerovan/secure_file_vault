import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/utils_sync.dart';
import 'package:flutter/foundation.dart';

import '../utils/common.dart';
import '../utils/enums.dart';
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
  Map<String, dynamic> data;
  int archivedAt;
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
    required this.data,
    required this.size,
    required this.archivedAt,
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
      'data': data is String ? data : jsonEncode(data),
      'archived_at': archivedAt,
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
    final data = getValueFromMap(map, "data", defaultValue: "{}");
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
      data: data is String ? jsonDecode(data) : data,
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<List<ModelItem>> getAllInFolder(ModelItem? item) async {
    if (item == null) return [];
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(Tables.items.string,
        where: "parent_id = ?",
        whereArgs: [
          item.id,
        ],
        orderBy: "is_folder DESC");
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

  static Future<List<Map<String, dynamic>>> getPathRowsForItem(
      String targetId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;

    // This fetches the target item and all its ancestors in a single query natively in SQLite.
    final List<Map<String, dynamic>> results = await db.rawQuery('''
    WITH RECURSIVE
      ancestors(id, parent_id, name, path, level) AS (
        -- Base Case: Start with the target item
        SELECT id, parent_id, name, path, 0
        FROM items
        WHERE id = ?
        
        UNION ALL
        
        -- Recursive Step: Join with the parent
        SELECT i.id, i.parent_id, i.name, i.path, a.level + 1
        FROM items i
        JOIN ancestors a ON i.id = a.parent_id
        -- Stop recursion if we hit the top or detect a loop (max depth 50 as a safety net)
        WHERE a.parent_id IS NOT NULL AND a.parent_id != '' AND a.level < 50
      )
    -- Order by level DESC to get the top-most parent first, down to the child
    SELECT * FROM ancestors ORDER BY level DESC;
  ''', [targetId]);
    return results;
  }

  static Future<String> getPathForItem(String targetId) async {
    // Instantly handle the cloud root edge case
    if (targetId == 'fife') {
      final Directory dir = await getApplicationDocumentsDirectory();
      return path_lib.join(dir.path, 'FiFe');
    }
    final String deviceHash = await getDeviceHash();
    // 2. Get path rows
    List<Map<String, dynamic>> pathRows = await getPathRowsForItem(targetId);
    if (pathRows.isEmpty) return "";
    // 3. Reconstruct the path from the single query result
    final List<String> pathParts = [];
    String? absoluteBasePath;
    bool isLocalDevice = false;

    for (final row in pathRows) {
      final String id = row['id'] as String;
      final String name = row['name'] as String;
      final String? path = row['path'] as String?;

      if (id == 'fife') continue; // Handled below in cloud branch

      if (id == deviceHash) {
        isLocalDevice = true;
        continue; // Stop capturing ancestors above the local device root
      }

      // Capture the absolute base path if it exists
      if (absoluteBasePath == null && path != null && path.trim().isNotEmpty) {
        absoluteBasePath = path.trim();
        if (!isLocalDevice) {
          pathParts.add(name);
        }
      } else {
        pathParts.add(name);
      }
    }

    // 4. Final Path Assembly
    if (isLocalDevice) {
      if (absoluteBasePath != null) {
        return path_lib.joinAll([absoluteBasePath, ...pathParts]);
      } else {
        return path_lib.joinAll(pathParts);
      }
    } else {
      // Cloud items synced from other devices
      pathParts.insert(0, 'FiFe');
      final Directory directory = await getApplicationDocumentsDirectory();
      return path_lib.join(directory.path, path_lib.joinAll(pathParts));
    }
  }

  static Future<String> getPathForLocalItem(String id) async {
    return getPathForItem(id);
  }

  static Future<bool> isLocalPath(String id) async {
    String deviceRootPathHash = await getDeviceHash();
    if (id == 'fife') return false;
    ModelItem? item = await get(id);
    if (item == null) return false;
    List<Map<String, dynamic>> pathRows = await getPathRowsForItem(id);
    if (pathRows.isEmpty) return false;
    bool isLocalPath = false;

    for (final row in pathRows) {
      final String id = row['id'] as String;

      if (id == 'fife') continue;

      if (id == deviceRootPathHash) {
        isLocalPath = true;
        break;
      }
    }
    return isLocalPath;
  }

  static Future<bool> syncFolderExists(String path) async {
    String deviceRootPathHash = await getDeviceHash();
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.items.string,
      where: "path = ? AND parent_id = ?",
      whereArgs: [path, deviceRootPathHash],
    );
    return rows.isNotEmpty;
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
    final deviceRoot = await getDeviceHash();
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.delete(Tables.items.string,
        where: "path != ? AND parent_id = ?", whereArgs: [null, deviceRoot]);
  }

  static Future<List<ModelItem>> getAllSyncedFolders() async {
    final deviceRoot = await getDeviceHash();
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(Tables.items.string,
        where: "parent_id = ?", whereArgs: [deviceRoot]);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> searchItem(String term) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<String> tokens = term.trim().split(RegExp(r'\s+'));

    String normalizedQuery = tokens.map((token) => '$token*').join(' ');

    List<Map<String, dynamic>> rows = [];
    try {
      List<Map<String, dynamic>> filteredRows = await db.rawQuery(
        '''SELECT item.*
       FROM item
       JOIN item_fts ON item.rowid = item_fts.docid
       WHERE item_fts MATCH ?
       ORDER BY item.at DESC
       ''',
        [
          normalizedQuery,
        ],
      );

      rows.addAll(filteredRows);
    } catch (e) {
      debugPrint(e.toString());
    }
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
    map["table"] = Tables.items.string;
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
    int updated = await dbHelper.update(Tables.items.string, updatedMap, id);
    if (pushToSync) {
      map["updated_at"] = utcNow;
      map["table"] = Tables.items.string;
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
        await dbHelper.getWithId(Tables.items.string, id);
    if (rows.isEmpty) {
      result = await dbHelper.insert(Tables.items.string, map);
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

  Future<int> delete({bool pushToSync = true}) async {
    final dbHelper = StorageSqlite.instance;
    int deleteTask = 1;
    Map<String, dynamic> map = toMap();
    int deleted = await dbHelper.delete("items", id);
    if (pushToSync) {
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
      await item.delete(pushToSync: false);
    }
    //EventStream().publish(AppEvent(type: EventType.changedItemId, value: id));
  }
}
