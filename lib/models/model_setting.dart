import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelSetting {
  static Map<String, String> settingJson = {};

  static const minForegroundSyncIntervalMinutes = 1;
  static const maxForegroundSyncIntervalMinutes = 30;
  static const defaultForegroundSyncIntervalMinutes = 15;

  static int parseForegroundSyncIntervalMinutes(String value) =>
      (int.tryParse(value) ?? defaultForegroundSyncIntervalMinutes).clamp(
        minForegroundSyncIntervalMinutes,
        maxForegroundSyncIntervalMinutes,
      );

  static int get foregroundSyncIntervalMinutes =>
      parseForegroundSyncIntervalMinutes(
          get(AppString.foregroundSyncIntervalMinutes.string));

  static Future<int> getForegroundSyncIntervalMinutes() async =>
      parseForegroundSyncIntervalMinutes(
          await getRaw(AppString.foregroundSyncIntervalMinutes.string));

  static Future<void> set(String key, String value) async {
    settingJson[key] = value;
    final dbHelper = StorageSqlite.instance;
    await dbHelper.insert(Tables.settings.string, {'id': key, 'value': value});
  }

  static Future<String> getRaw(String key, {String defaultValue = ""}) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.settings.string, key);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return map["value"];
    }
    return defaultValue;
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
