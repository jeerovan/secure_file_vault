import '../models/model_item_task.dart';
import '../storage/storage_sqlite.dart';
import '../utils/enums.dart';

class RepositoryItemTask {
  static final RepositoryItemTask instance = RepositoryItemTask._init();
  RepositoryItemTask._init();

  // Create a broadcast stream so multiple widgets can listen simultaneously
  Stream<Map<String, TaskStatus>>? _taskStream;

  Stream<Map<String, TaskStatus>> getTaskSnapshotStream() {
    _taskStream ??= Stream.periodic(const Duration(seconds: 2), (_) => _)
        .asyncMap((_) => fetchTaskSnapshot())
        .distinct() // Do not emit if the data is identical to the previous fetch
        .asBroadcastStream();

    return _taskStream!;
  }

  Future<Map<String, TaskStatus>> fetchTaskSnapshot() async {
    try {
      final List<Map<String, dynamic>> tasks =
          await StorageSqlite.instance.getAll(Tables.itemTasks.string);

      // Convert the List to a Map for O(1) lookup performance
      return {
        for (var row in tasks)
          row['id'] as String: TaskStatus(
            task: row['task'] as int,
            progress: row['progress'] as int,
          )
      };
    } catch (e) {
      return {}; // Return empty map on error
    }
  }
}
