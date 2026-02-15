import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelState {
  static Future<void> set(String key, dynamic value) async {
    final dbHelper = StorageSqlite.instance;
    await dbHelper.insert(Tables.states.string, {'id': key, 'value': value});
  }

  static Future<dynamic> get(String key, {dynamic defaultValue}) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.states.string, key);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return map["value"];
    }
    return defaultValue;
  }

  static Future<void> delete(String key) async {
    final dbHelper = StorageSqlite.instance;
    int _ = await dbHelper.delete(Tables.states.string, key);
  }
}
