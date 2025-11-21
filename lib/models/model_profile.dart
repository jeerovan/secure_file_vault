import '../utils/common.dart';

import '../storage/storage_sqlite.dart';

class ModelProfile {
  String id;
  String? email;
  String? username;
  int? updatedAt;
  int? createdAt;

  ModelProfile({
    required this.id,
    this.email,
    this.username,
    this.updatedAt,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'updated_at': updatedAt,
      'created_at': createdAt,
    };
  }

  static Future<ModelProfile> fromMap(Map<String, dynamic> map) async {
    int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelProfile(
      id: map['id'],
      email: getValueFromMap(map, "email", defaultValue: ""),
      username: getValueFromMap(map, "username", defaultValue: ""),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: nowUtc),
      createdAt: getValueFromMap(map, "created_at", defaultValue: nowUtc),
    );
  }

  static Future<List<ModelProfile>> all() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      "profile",
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelProfile?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list = await dbHelper.getWithId("profile", id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert("profile", map);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    Map<String, dynamic> updatedMap = {"updated_at": utcNow};
    for (String attr in attrs) {
      updatedMap[attr] = map[attr];
    }
    //SyncUtils.pushProfileChange(updatedMap);
    int updated = await dbHelper.update("profile", updatedMap, id);
    return updated;
  }

  Future<int> upcertChangeFromServer() async {
    int result;
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    List<Map<String, dynamic>> rows = await dbHelper.getWithId("profile", id);
    if (rows.isEmpty) {
      result = await dbHelper.insert("profile", map);
    } else {
      int existingUpdatedAt = rows[0]["updated_at"];
      int incomingUpdatedAt = map["updated_at"];
      if (incomingUpdatedAt > existingUpdatedAt) {
        map.remove("email");
        result = await dbHelper.update("profile", map, id);
      } else {
        result = 0;
      }
    }
    return result;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete("profile", id);
    // delete related categories
    return deleted;
  }
}
