import '../utils/common.dart';

import '../repositories/repository_entity.dart';
import '../services/service_events.dart';

enum TransferTaskState {
  pending,
  running,
  retryWaiting,
  blocked,
  failed,
  cancelled,
}

class TaskStatus {
  final int task;
  final int progress;
  final TransferTaskState state;

  TaskStatus({
    required this.task,
    required this.progress,
    required this.state,
  });
}

class ModelItemTask {
  static const int maxRetryAttempts = 10;
  static final RepositoryTask<ModelItemTask> _repository =
      RepositoryTask<ModelItemTask>(decoder: fromMap);
  String id;
  int task;
  int progress;
  int updatedAt;
  TransferTaskState state;
  int attemptCount;
  int nextAttemptAt;
  String? lastError;

  ModelItemTask(
      {required this.id,
      required this.task,
      required this.progress,
      required this.updatedAt,
      required this.state,
      required this.attemptCount,
      required this.nextAttemptAt,
      this.lastError});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task': task,
      'progress': progress,
      'updated_at': updatedAt,
      'state': state.name,
      'attempt_count': attemptCount,
      'next_attempt_at': nextAttemptAt,
      'last_error': lastError,
    };
  }

  static Future<ModelItemTask> fromMap(Map<String, dynamic> map) async {
    int utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;
    final stateName =
        getValueFromMap(map, "state", defaultValue: "pending").toString();
    return ModelItemTask(
        id: map['id'],
        task: map['task'],
        progress: getValueFromMap(map, "progress", defaultValue: 0),
        updatedAt: getValueFromMap(map, "updated_at", defaultValue: utcNow),
        state: TransferTaskState.values.firstWhere(
          (value) => value.name == stateName,
          orElse: () => TransferTaskState.pending,
        ),
        attemptCount: getValueFromMap(map, "attempt_count", defaultValue: 0),
        nextAttemptAt: getValueFromMap(map, "next_attempt_at", defaultValue: 0),
        lastError: getValueFromMap(map, "last_error", defaultValue: null));
  }

  static Future<ModelItemTask?> get(String id) async {
    return _repository.get(id);
  }

  static Future<void> addTask(String id, int taskType) async {
    ModelItemTask? task = await get(id);
    if (task == null) {
      ModelItemTask newTask = await fromMap({"id": id, "task": taskType});
      await newTask.insert();
    } else if (task.task != taskType ||
        task.state == TransferTaskState.blocked ||
        task.state == TransferTaskState.failed ||
        task.state == TransferTaskState.cancelled) {
      task.task = taskType;
      task.state = TransferTaskState.pending;
      task.attemptCount = 0;
      task.nextAttemptAt = 0;
      task.lastError = null;
      await task.update(
          ["task", "state", "attempt_count", "next_attempt_at", "last_error"]);
    }
  }

  static Future<void> completeTask(String id) async {
    ModelItemTask? task = await get(id);
    if (task != null) {
      await task.delete();
    }
  }

  static Future<void> recoverInterruptedTasks() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _repository.recoverInterrupted(now: now);
  }

  static Future<String?> fetchPendingTask(Set<String> activeTasks) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return _repository.fetchPendingId(activeTasks, now: now);
  }

  static Future<int?> fetchNextWakeAt() => _repository.fetchNextWakeAt();

  Future<int> insert() async {
    Map<String, dynamic> map = toMap();
    int inserted = await _repository.insert(map);
    _publishChange(EventKey.added);
    return inserted;
  }

  Future<int> update(List<String> attrs) async {
    Map<String, dynamic> map = toMap();
    updatedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    Map<String, dynamic> updatedMap = {"updated_at": updatedAt};
    for (String attr in attrs) {
      updatedMap[attr] = map[attr];
    }
    int updated = await _repository.update(id, updatedMap);
    _publishChange(EventKey.updated);
    return updated;
  }

  Future<int> markRunning() async {
    state = TransferTaskState.running;
    lastError = null;
    nextAttemptAt = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 2))
        .millisecondsSinceEpoch;
    return update(["state", "next_attempt_at", "last_error"]);
  }

  Future<int> markPending() async {
    state = TransferTaskState.pending;
    attemptCount = 0;
    nextAttemptAt = 0;
    lastError = null;
    return update(["state", "attempt_count", "next_attempt_at", "last_error"]);
  }

  static Duration retryDelayForAttempt(int attempt) {
    final exponent = (attempt - 1).clamp(0, 8);
    final seconds = 5 * (1 << exponent);
    return Duration(seconds: seconds.clamp(5, 900));
  }

  static Duration retryDelayWithJitter(int attempt, String seed) {
    final base = retryDelayForAttempt(attempt);
    final stableValue =
        seed.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final jitterMilliseconds = base.inMilliseconds * (stableValue % 21) ~/ 100;
    return Duration(
      milliseconds:
          (base.inMilliseconds + jitterMilliseconds).clamp(5000, 900000),
    );
  }

  Future<int> scheduleRetry(String error, {DateTime? now}) async {
    attemptCount += 1;
    lastError = error;
    if (attemptCount >= maxRetryAttempts) {
      state = TransferTaskState.failed;
      nextAttemptAt = 0;
      return update(
          ["state", "attempt_count", "next_attempt_at", "last_error"]);
    }
    state = TransferTaskState.retryWaiting;
    final base = now ?? DateTime.now().toUtc();
    nextAttemptAt =
        base.add(retryDelayWithJitter(attemptCount, id)).millisecondsSinceEpoch;
    return update(["state", "attempt_count", "next_attempt_at", "last_error"]);
  }

  Future<int> markBlocked(String error) async {
    state = TransferTaskState.blocked;
    lastError = error;
    nextAttemptAt = 0;
    return update(["state", "next_attempt_at", "last_error"]);
  }

  Future<int> cancel() async {
    state = TransferTaskState.cancelled;
    lastError = null;
    nextAttemptAt = 0;
    return update(["state", "next_attempt_at", "last_error"]);
  }

  static Future<void> cancelTask(String id) async {
    final task = await get(id);
    await task?.cancel();
  }

  Future<int> delete() async {
    int deleted = await _repository.delete(id);
    _publishChange(EventKey.removed);
    return deleted;
  }

  static Future<void> clear() async {
    await _repository.clear();
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'all',
      key: EventKey.removed,
    ));
  }

  void _publishChange(EventKey key) {
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: id,
      key: key,
      value: {'task': task, 'progress': progress, 'state': state.name},
    ));
  }
}
