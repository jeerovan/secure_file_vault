import 'dart:async';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() => fixture.dispose());

  Future<String> waitingUpload() async {
    await fixture.text('retry.txt', 'Synthetic retry wake fixture.');
    await fixture.scan();
    final item = await fixture.item('retry.txt');
    final task = (await ModelItemTask.get(item.id))!;
    task.state = TransferTaskState.retryWaiting;
    task.attemptCount = 1;
    task.nextAttemptAt = DateTime.now().millisecondsSinceEpoch +
        const Duration(seconds: 1).inMilliseconds;
    await task.update(['state', 'attempt_count', 'next_attempt_at']);
    return item.id;
  }

  Future<T> withTransport<T>(
      TransferApi api, Future<T> Function() action) async {
    return api.run(() => http.runWithClient(
        action,
        () => MockClient((request) async => request.method == 'HEAD'
            ? http.Response('', 200)
            : api.handle(request))));
  }

  test('a retry wake during metadata sync is retried after that sync releases',
      () async {
    final id = await waitingUpload();
    final lease = await ExclusiveOperationCoordinator.tryAcquire('metadata');
    expect(lease, isNotNull);
    var wakes = 0;
    final firstAttempt = Completer<void>();
    final times = <DateTime>[];
    final api = TransferApi(managed: true);
    var released = false;
    try {
      await withTransport(api, () async {
        Future<void> wake() async {
          wakes++;
          times.add(DateTime.now());
          if (wakes == 1) {
            // The production sync guard consumes the first retry while an
            // earlier pass owns the real persisted metadata lease.
            await SyncUtils().triggerSync(caller: 'TransferRetry');
            await lease!.release();
            released = true;
            firstAttempt.complete();
          } else {
            await TaskManager.init(retryWakeHandler: wake);
          }
        }

        await TaskManager.init(retryWakeHandler: wake);
        await firstAttempt.future.timeout(const Duration(seconds: 4));
        final clock = Stopwatch()..start();
        while (await ModelItemTask.get(id) != null &&
            clock.elapsed < const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(await ModelItemTask.get(id), isNull,
            reason: 'A consumed busy-sync wake must not strand the upload');
        final item = await fixture.item('retry.txt');
        expect(
            (await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
        expect(api.objects, isNotEmpty);
        expect(wakes, 2);
        expect(times[1].difference(times[0]),
            greaterThanOrEqualTo(const Duration(seconds: 5)));
      });
    } finally {
      if (!released) await lease!.release();
    }
  });

  test('cleanup during a retry handler does not resurrect another wake',
      () async {
    await waitingUpload();
    final api = TransferApi(managed: true);
    final cleaned = Completer<void>();
    var wakes = 0;
    await withTransport(api, () async {
      await TaskManager.init(retryWakeHandler: () async {
        wakes++;
        expect(await SessionCleanup.instance.request(), isTrue);
        cleaned.complete();
      });
      await cleaned.future.timeout(const Duration(seconds: 4));
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(wakes, 1);
      expect(await ModelItemTask.fetchNextWakeAt(), isNull);
      expect(fixture.secrets, isEmpty);
      expect(api.objects, isEmpty);
    });
  });
}
