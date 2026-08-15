import '../models/model_item_task.dart';
import '../services/service_events.dart';
import '../storage/storage_sqlite.dart';
import '../utils/enums.dart';

class RepositoryItemTask {
  static final RepositoryItemTask instance = RepositoryItemTask._init();
  RepositoryItemTask._init();

  Stream<Map<String, TaskStatus>> getTaskSnapshotStream() {
    return _watchTaskSnapshots().distinct(_snapshotsEqual);
  }

  Stream<Map<String, TaskStatus>> _watchTaskSnapshots() async* {
    yield await fetchTaskSnapshot();
    await for (final event in EventStream().events) {
      if (event.type != EventType.system ||
          !const {
            EventKey.added,
            EventKey.updated,
            EventKey.removed,
            EventKey.uploadProgress,
            EventKey.downloadProgress,
          }.contains(event.key)) {
        continue;
      }
      yield await fetchTaskSnapshot();
    }
  }

  bool _snapshotsEqual(
    Map<String, TaskStatus> previous,
    Map<String, TaskStatus> next,
  ) {
    if (previous.length != next.length) return false;
    for (final entry in previous.entries) {
      final candidate = next[entry.key];
      if (candidate == null ||
          candidate.task != entry.value.task ||
          candidate.progress != entry.value.progress ||
          candidate.state != entry.value.state) {
        return false;
      }
    }
    return true;
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
            state: TransferTaskState.values.firstWhere(
              (value) => value.name == row['state'],
              orElse: () => TransferTaskState.pending,
            ),
          )
      };
    } catch (e) {
      return {}; // Return empty map on error
    }
  }
}
