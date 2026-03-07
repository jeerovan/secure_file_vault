import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelSetting {
  static Map<String, dynamic> settingJson = {};

  static Future<void> set(String key, dynamic value) async {
    settingJson[key] = value;
    final dbHelper = StorageSqlite.instance;
    await dbHelper.insert(Tables.settings.string, {'id': key, 'value': value});
  }

  static dynamic get(String key, dynamic defaultValue) {
    return settingJson.containsKey(key) ? settingJson[key] : defaultValue;
  }

  static Future<void> delete(String key) async {
    settingJson.remove(key);
    final dbHelper = StorageSqlite.instance;
    await dbHelper.delete(Tables.settings.string, key);
  }
}
