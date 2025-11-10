import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/models/model_preferences.dart';
import 'package:uuid/uuid.dart';
import '../storage/storage_sqlite.dart';

class ModelItem {
  String? id;
  String? path;
  String name;
  bool isFolder;
  String? itemId;
  int? fileId;
  int? size;
  int? thumbnail;
  int? state;
  int? archivedAt;
  int? createdAt;
  int? updatedAt;

  ModelItem({
    this.id,
    this.path,
    required this.name,
    required this.isFolder,
    this.itemId,
    this.fileId,
    this.size,
    this.thumbnail,
    this.state,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'is_folder': isFolder ? 1 : 0,
      'item_id': itemId,
      'file_id': fileId,
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
    return ModelItem(
      id: map.containsKey('id') ? map['id'] : uuid.v4(),
      path: getValueFromMap(map, "path", defaultValue: ""),
      name: getValueFromMap(map, "name", defaultValue: ""),
      isFolder: getValueFromMap(map, "is_folder", defaultValue: 0) == 0
          ? false
          : true,
      itemId: getValueFromMap(map, "item_id", defaultValue: null),
      fileId: getValueFromMap(map, "file_id", defaultValue: null),
      size: getValueFromMap(map, "size", defaultValue: 0),
      thumbnail: getValueFromMap(map, "thumbnail", defaultValue: 0),
      state: getValueFromMap(map, "state", defaultValue: 0),
      archivedAt: getValueFromMap(map, "archived_at", defaultValue: 0),
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<int> mediaCountInGroup(String groupId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    String sql = '''
      SELECT count(*) as count
      FROM item
      WHERE type > 100000 AND type < 130000
        AND group_id = ? AND archived_at = 0
    ''';
    final rows = await db.rawQuery(sql, [groupId]);
    return rows.isNotEmpty ? rows[0]['count'] as int : 0;
  }

  static Future<int> mediaIndexInGroup(String groupId, String currentId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    String sql = '''
      SELECT count(*) as count
      FROM item
      WHERE type > 100000 AND type < 130000
        AND group_id = ? AND archived_at = 0
        AND at < (SELECT at FROM item WHERE id = ?)
      ORDER BY at ASC
    ''';
    final rows = await db.rawQuery(sql, [groupId, currentId]);
    return rows.isNotEmpty ? rows[0]['count'] as int : 0;
  }

  static Future<ModelItem?> getPreviousMediaItemInGroup(
      String groupId, String currentId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    String sql = '''
      SELECT * FROM item
      WHERE type > 100000 AND type < 130000 AND group_id = ? AND archived_at = 0
        AND at < (SELECT at FROM item WHERE id = ?)
      ORDER BY at DESC
      LIMIT 1
      ''';
    final rows = await db.rawQuery(sql, [groupId, currentId]);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
  }

  static Future<ModelItem?> getNextMediaItemInGroup(
      String groupId, String currentId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    String sql = '''
      SELECT * FROM item
      WHERE type > 100000 AND type < 130000 AND group_id = ? AND archived_at = 0
        AND at > (SELECT at FROM item WHERE id = ?)
      ORDER BY at ASC
      LIMIT 1
      ''';
    final rows = await db.rawQuery(sql, [groupId, currentId]);
    if (rows.isNotEmpty) {
      Map<String, dynamic> map = rows.first;
      return await fromMap(map);
    }
    return null;
  }

  static Future<List<ModelItem>> getInFolder(ModelItem? item) async {
    if (item == null) return [];
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
      where: "item_id = ?",
      whereArgs: [
        item.id,
      ],
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelItem?> getParentItem(ModelItem? item) async {
    if (item == null) return null;
    ModelItem? currentItem = await get(item.id!);
    ModelItem? parentItem;
    if (currentItem != null) {
      String? parentItemId = currentItem.itemId;
      if (parentItemId != null) {
        parentItem = await get(parentItemId);
      }
    }
    return parentItem;
  }

  static Future<List<ModelItem>> getStarred(int offset, int limit) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "item",
      where: "starred = ? AND archived_at = 0",
      whereArgs: [1],
      orderBy: 'at DESC',
      offset: offset,
      limit: limit,
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

  static Future<int> pinnedCountInGroup(String groupId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    String sql = '''
      SELECT count(*) as count
      FROM item
      WHERE pinned = 1 AND
        AND group_id = ? AND archived_at = 0
    ''';
    final rows = await db.rawQuery(sql, [groupId]);
    return rows.isNotEmpty ? rows[0]['count'] as int : 0;
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

  static Future<List<Map<String, dynamic>>> getAllRawRowsMap() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    return await db.query("item");
  }

  static Future<List<ModelItem>> getImageAudio() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query("item",
        where: "type = ? OR type = ?",
        whereArgs: [FileType.image.value, FileType.audio.value]);
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<List<ModelItem>> getForType(FileType itemType) async {
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
