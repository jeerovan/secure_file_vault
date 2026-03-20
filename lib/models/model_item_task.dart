import '../utils/common.dart';
import '../utils/enums.dart';

import '../storage/storage_sqlite.dart';

class ModelItemTask {
  String id;
  int task;
  int progress;
  int updatedAt;

  ModelItemTask(
      {required this.id,
      required this.task,
      required this.progress,
      required this.updatedAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task': task,
      'progress': progress,
      'updated_at': updatedAt
    };
  }

  static Future<ModelItemTask> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ModelItemTask(
        id: map['id'],
        task: map['task'],
        progress: getValueFromMap(map, "progress", defaultValue: 0),
        updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow));
  }

  static Future<ModelItemTask?> get(String id) async {
    final dbHelper = StorageSqlite.instance;
    List<Map<String, dynamic>> list =
        await dbHelper.getWithId(Tables.itemTasks.string, id);
    if (list.isNotEmpty) {
      Map<String, dynamic> map = list.first;
      return await fromMap(map);
    }
    return null;
  }

  static Future<void> deleteTask(String id) async {
    ModelItemTask? task = await get(id);
    if (task != null) {
      task.delete();
    }
  }

  static Future<String?> fetchPendingTask(Set<String> activeTasks) async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;

    String query = 'SELECT id FROM item_tasks';
    List<dynamic> args = [];

    // Dynamically exclude currently running taskIds (item_id)
    if (activeTasks.isNotEmpty) {
      final String placeholders =
          List.filled(activeTasks.length, '?').join(',');
      query += ' WHERE id NOT IN ($placeholders)';
      args.addAll(activeTasks);
    }

    // Process oldest created/updated task first
    query += ' ORDER BY updated_at ASC LIMIT 1';

    final List<Map<String, dynamic>> results = await db.rawQuery(query, args);

    if (results.isNotEmpty) {
      return results.first['id'] as String;
    }
    return null;
  }

  Future<int> insert() async {
    final dbHelper = StorageSqlite.instance;
    Map<String, dynamic> map = toMap();
    int inserted = await dbHelper.insert(Tables.itemTasks.string, map);
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
    int updated =
        await dbHelper.update(Tables.itemTasks.string, updatedMap, id);
    return updated;
  }

  Future<int> delete() async {
    final dbHelper = StorageSqlite.instance;
    int deleted = await dbHelper.delete(Tables.itemTasks.string, id);
    // delete related categories
    return deleted;
  }

  static Future<void> clear() async {
    final dbHelper = StorageSqlite.instance;
    final db = await dbHelper.database;
    await db.delete(Tables.itemTasks.string);
  }
}
