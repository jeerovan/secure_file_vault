import 'dart:io';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async {
    SyncUtils().stopAutoSync();
    await fixture.dispose();
  });

  Future<void> abandonedLease(String operation) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Persist the previous process's lease without registering a live owner in
    // this process. No retry handler or task dispatcher is initialized here.
    expect(
        await StorageSqlite.instance.tryAcquireLease(
            key: 'operation_lease:$operation',
            owner: 'previous-process',
            now: now,
            expiresAt: now + 500),
        isTrue);
  }

  Future<T> withTransport<T>(
      TransferApi api, Future<T> Function() action) async {
    return api.run(() => http.runWithClient(
        action,
        () => MockClient((r) {
              if (r.method == 'HEAD') {
                return Future.value(http.Response('', 200));
              }
              if (r.url.path.endsWith('/devices')) {
                return Future.value(api.json({
                  'success': 1,
                  'data': {'active': 1}
                }));
              }
              if (r.url.path.endsWith('/sync')) {
                return Future.value(api.json({'success': 1, 'data': {}}));
              }
              return api.handle(r);
            })));
  }

  Future<void> expectUploaded(TransferApi api, String originalText) async {
    final clock = Stopwatch()..start();
    var complete = false;
    while (clock.elapsed < const Duration(seconds: 6)) {
      final items = (await fixture.items()).where((i) => !i.isFolder).toList();
      if (items.length == 1 && items.single.fileHash != null) {
        final file = await ModelFile.get(items.single.fileHash!);
        complete = file != null &&
            file.uploadedAt > 0 &&
            await ModelItemTask.get(items.single.id) == null;
        if (complete && !await isRecordOrSyncInProgress()) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(complete, isTrue,
        reason:
            'The normal startup path must retry after the old lease expires');
    expect(await isRecordOrSyncInProgress(), isFalse);
    expect(api.objects, isNotEmpty);
    expect(await File('${fixture.source.path}/pending.txt').readAsString(),
        originalText);
  }

  test('startup retries a persisted metadata lease without task initialization',
      () async {
    await fixture.text('pending.txt', 'Generated pending upload.');
    await fixture.scan();
    await abandonedLease('metadata');
    final api = TransferApi(managed: true);
    await withTransport(api, () async {
      await SyncUtils().reconFolders(caller: 'AppStart');
      await expectUploaded(api, 'Generated pending upload.');
    });
  });

  test(
      'startup rescans a root skipped because its previous process held a lease',
      () async {
    await fixture.text('pending.txt', 'Generated unscanned upload.');
    await abandonedLease('reconciliation:${SyncFixture.rootId}');
    final api = TransferApi(managed: true);
    await withTransport(api, () async {
      await SyncUtils().reconFolders(caller: 'AppStart');
      await expectUploaded(api, 'Generated unscanned upload.');
    });
  });

  test('a renewed foreign lease is respected and repeated startup is coalesced',
      () async {
    await fixture.text('pending.txt', 'Generated pending upload.');
    await fixture.scan();
    await abandonedLease('metadata');
    final api = TransferApi(managed: true);
    await withTransport(api, () async {
      await SyncUtils().reconFolders(caller: 'AppStart');
      await SyncUtils().triggerSync(caller: 'AnotherWindow');
      expect(
          await StorageSqlite.instance.renewLease(
              key: 'operation_lease:metadata',
              owner: 'previous-process',
              expiresAt: DateTime.now().millisecondsSinceEpoch + 2000),
          isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(api.objects, isEmpty,
          reason: 'A retry must not steal a renewed lease');
      expect(await isRecordOrSyncInProgress(), isTrue);
      await expectUploaded(api, 'Generated pending upload.');
      expect(api.managedRecords.length, 1);
    });
  });

  test('deferred work does not run in a replacement session', () async {
    await fixture.text('pending.txt', 'Generated pending upload.');
    await fixture.scan();
    await abandonedLease('metadata');
    final api = TransferApi(managed: true);
    await withTransport(api, () async {
      await SyncUtils().reconFolders(caller: 'AppStart');
      SessionWork.invalidate('replacement');
      SessionWork.complete('replacement');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(api.objects, isEmpty);
      expect(api.requests, isEmpty);
      expect(await ModelItemTask.get((await fixture.item('pending.txt')).id),
          isNotNull);
    });
  });

  test('budgeted callbacks do not leave a foreground deferred timer', () async {
    await fixture.text('pending.txt', 'Generated pending upload.');
    await fixture.scan();
    await abandonedLease('metadata');
    final api = TransferApi(managed: true);
    final budget =
        SyncBudget(deadline: DateTime.now().add(const Duration(seconds: 20)));
    addTearDown(budget.dispose);
    await withTransport(api, () async {
      expect(
          await budget
              .run(() => SyncUtils().reconFolders(caller: 'Background')),
          isFalse);
      budget.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(api.objects, isEmpty);
      expect(api.requests, isEmpty);
    });
  });

  test('a live operation in this isolate keeps its own completion path',
      () async {
    await fixture.text('pending.txt', 'Generated pending upload.');
    await fixture.scan();
    final lease = await ExclusiveOperationCoordinator.tryAcquire('metadata');
    expect(lease, isNotNull);
    final api = TransferApi(managed: true);
    try {
      await withTransport(api, () async {
        await SyncUtils().triggerSync(caller: 'DuplicateRequest');
        await lease!.release();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(api.objects, isEmpty);
        expect(api.requests, isEmpty);
      });
    } finally {
      if (lease!.isValid) await lease.release();
    }
  });
}
