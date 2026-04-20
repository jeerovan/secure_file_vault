import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelSetting {
  static Map<String, String> settingJson = {};

  static Future<void> set(String key, String value) async {
    settingJson[key] = value;
    final dbHelper = StorageSqlite.instance;
    await dbHelper.insert(Tables.settings.string, {'id': key, 'value': value});
  }

  static String get(String key, {String defaultValue = ""}) {
    if (settingJson.containsKey(key)) {
      String? value = settingJson[key];
      if (value == null) {
        return defaultValue;
      } else {
        return value;
      }
    } else {
      return defaultValue;
    }
  }

  static Future<void> delete(String key) async {
    settingJson.remove(key);
    final dbHelper = StorageSqlite.instance;
    await dbHelper.delete(Tables.settings.string, key);
  }

  static void clear() {
    settingJson.clear();
  }
}
