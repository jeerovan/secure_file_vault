import '../utils/enums.dart';
import '../utils/utils_sync.dart';

import '../utils/common.dart';
import '../storage/storage_sqlite.dart';

class ModelPart {
  String id;
  String fileId;
  int partNumber;
  int size;
  int state;
  String cipher;
  String nonce;
  int createdAt;
  int updatedAt;

  ModelPart(
      {required this.id,
      required this.fileId,
      required this.partNumber,
      required this.size,
      required this.state,
      required this.cipher,
      required this.nonce,
      required this.updatedAt,
      required this.createdAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_id': fileId,
      'part_number': partNumber,
      'size': size,
      'state': state,
      'cipher': cipher,
      'nonce': nonce,
      'updated_at': updatedAt,
      'created_at': createdAt,
    };
  }

  static Future<ModelPart> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelPart(
      id: map['id'],
      fileId: map['file_id'],
      partNumber: map["part_number"],
      size: map['size'],
      state: map['state'],
      cipher: map["cipher"],
      nonce: map["nonce"],
      createdAt: getValueFromMap(map, "created_at", defaultValue: utcNow),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
    );
  }

  static Future<List<String>> shasForFileId(String fileId) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(Tables.parts.string,
        columns: ["id"],
        where: "file_id = ?",
        whereArgs: [fileId],
        orderBy: 'part_number ASC');
    List<String> shas = [];
    for (Map<String, dynamic> row in rows) {
      shas.add(row["id"]);
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
