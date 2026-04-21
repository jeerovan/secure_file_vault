import '../utils/enums.dart';

import '../utils/common.dart';

import '../storage/storage_sqlite.dart';

// Profile changes will not be synced like others
// username and image will be updated on server with http request

class ModelProfile {
  String id;
  String? email;
  String? username;
  String? image;
  int? updatedAt;

  ModelProfile({
    required this.id,
    this.email,
    this.username,
    this.image,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'image': image,
      'updated_at': updatedAt,
    };
  }

  static Future<ModelProfile> fromMap(Map<String, dynamic> map) async {
    int nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelProfile(
      id: map['id'],
      email: getValueFromMap(map, "email", defaultValue: ""),
      username: getValueFromMap(map, "username", defaultValue: ""),
      image: getValueFromMap(map, "image", defaultValue: ""),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: nowUtc),
    );
  }

  static Future<List<ModelProfile>> all() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    List<Map<String, dynamic>> rows = await db.query(
      Tables.profiles.string,
    );
    return await Future.wait(rows.map((map) => fromMap(map)));
  }

  static Future<ModelProfile?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.profiles.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.profiles.string, map);
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
    int updated = await dbHelper.update(Tables.profiles.string, updatedMap, id);
    return updated;
  }

  static Future<int> upcertFromServer(
      String id, Map<String, dynamic> map) async {
    final dbHelper = StorageSqlite.instance;
    return await dbHelper.update(Tables.profiles.string, map, id);
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.profiles.string, id);
    // delete related content
    return deleted;
  }
}
