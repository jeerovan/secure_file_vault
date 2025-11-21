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
    return ModelPart(
      id: map['id'],
      fileId: map['file_id'],
      partNumber: map["part_number"],
      size: map['size'],
      state: map['state'],
      cipher: map["cipher"],
      nonce: map["nonce"],
      createdAt: getValueFromMap(map, "created_at", defaultValue: 0),
      updatedAt: getValueFromMap(map, "updated_at", defaultValue: 0),
    );
  }

  static Future<ModelPart?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list = await dbHelper.getWithId("part", id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert("part", map);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    Map<String, dynamic> updatedMap = {};
    for (String attr in attrs) {
      updatedMap[attr] = map[attr];
    }
    int updated = await dbHelper.update("part", updatedMap, id);
    return updated;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete("part", id);
    return deleted;
  }
}
