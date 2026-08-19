import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('retry delay grows exponentially and caps at fifteen minutes', () {
    expect(ModelItemTask.retryDelayForAttempt(1), const Duration(seconds: 5));
    expect(ModelItemTask.retryDelayForAttempt(2), const Duration(seconds: 10));
    expect(ModelItemTask.retryDelayForAttempt(9), const Duration(seconds: 900));
    expect(
        ModelItemTask.retryDelayForAttempt(100), const Duration(seconds: 900));
  });

  test('retry jitter is stable and remains capped', () {
    expect(
      ModelItemTask.retryDelayWithJitter(2, 'item'),
      ModelItemTask.retryDelayWithJitter(2, 'item'),
    );
    expect(
      ModelItemTask.retryDelayWithJitter(100, 'item'),
      const Duration(minutes: 15),
    );
  });

  test('retry attempts are bounded', () {
    expect(ModelItemTask.maxRetryAttempts, 10);
  });

  test('retry wake delay waits until due and is capped', () {
    final now = DateTime.utc(2026, 1, 1);
    expect(
      TaskManager.retryWakeDelay(
          now.add(const Duration(seconds: 12)).millisecondsSinceEpoch,
          now: now),
      const Duration(seconds: 12),
    );
    expect(
      TaskManager.retryWakeDelay(
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          now: now),
      const Duration(minutes: 15),
    );
    expect(
      TaskManager.retryWakeDelay(
          now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
          now: now),
      const Duration(milliseconds: 1),
    );
  });

  test('successful part continuation is immediately eligible', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE item_tasks ('
      'id TEXT PRIMARY KEY, task INTEGER NOT NULL, progress INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, state TEXT NOT NULL, '
      'attempt_count INTEGER NOT NULL, next_attempt_at INTEGER NOT NULL, '
      'last_error TEXT)',
    );

    await StorageSqlite.runInDatabaseTransaction(db, () async {
      final task = await ModelItemTask.fromMap({
        'id': 'retry-upload',
        'task': ItemTask.upload.value,
        'progress': 50,
        'state': TransferTaskState.running.name,
        'attempt_count': 3,
        'next_attempt_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        'last_error': 'transport',
      });
      await task.insert();

      await task.markPending();

      final stored = await ModelItemTask.get(task.id);
      expect(stored?.state, TransferTaskState.pending);
      expect(stored?.attemptCount, 0);
      expect(stored?.nextAttemptAt, 0);
      expect(stored?.lastError, isNull);
      expect(await ModelItemTask.fetchPendingTask({}), task.id);
    });
  });
}
