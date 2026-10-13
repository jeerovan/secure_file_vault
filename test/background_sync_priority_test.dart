import 'dart:io';

import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SyncBudget budget({Duration Function()? elapsed}) {
    final value = SyncBudget(
      deadline: DateTime.now().add(const Duration(seconds: 20)),
      elapsed: elapsed,
    );
    addTearDown(value.dispose);
    return value;
  }

  test('queued background transfer gets the budget before another folder scan',
      () async {
    var elapsed = Duration.zero;
    var pendingBytes = 64;
    var scans = 0;
    final value = budget(elapsed: () => elapsed);
    final succeeded = await value.run(() => runSyncPass(
          hasPendingTransfers: () async => pendingBytes > 0,
          reconcile: () async {
            scans++;
            elapsed += const Duration(seconds: 4);
            return true;
          },
          sync: () async {
            // Authentication and metadata requests consume most of the window.
            elapsed += const Duration(seconds: 14);
            SyncBudget.check(reserve: const Duration(seconds: 5));
            pendingBytes = 0;
            return true;
          },
        ));
    expect(succeeded, isTrue);
    expect(pendingBytes, 0);
    expect(scans, 0);
    expect(value.interrupted, isFalse);
  });

  test('background discovery resumes when there is no eligible transfer',
      () async {
    final events = <String>[];
    final succeeded = await budget().run(() => runSyncPass(
          hasPendingTransfers: () async => false,
          reconcile: () async {
            events.add('discover');
            return true;
          },
          sync: () async {
            events.add('sync discovered changes');
            return true;
          },
        ));
    expect(succeeded, isTrue);
    expect(events, ['discover', 'sync discovered changes']);
  });

  test('foreground still discovers edits before syncing even with queued work',
      () async {
    final events = <String>[];
    final succeeded = await runSyncPass(
      hasPendingTransfers: () async {
        fail('Foreground must not select the background priority path');
      },
      reconcile: () async {
        events.add('discover new edit');
        return true;
      },
      sync: () async {
        events.add('sync latest edit');
        return true;
      },
    );
    expect(succeeded, isTrue);
    expect(events, ['discover new edit', 'sync latest edit']);
  });

  test('failed priority work preserves its queue and reports failure',
      () async {
    var pending = true;
    final succeeded = await budget().run(() => runSyncPass(
          hasPendingTransfers: () async => pending,
          reconcile: () async {
            pending = false;
            return true;
          },
          sync: () async => false,
        ));
    expect(succeeded, isFalse);
    expect(pending, isTrue);
  });

  test(
      'partial discovery still syncs its committed changes and reports failure',
      () async {
    var published = false;
    final succeeded = await budget().run(() => runSyncPass(
          hasPendingTransfers: () async => false,
          reconcile: () async => false,
          sync: () async {
            published = true;
            return true;
          },
        ));
    expect(succeeded, isFalse);
    expect(published, isTrue);
  });

  test('expired background work does not start discovery or queue inspection',
      () async {
    final value = budget()..cancel('expiration');
    var entered = false;
    Future<bool> action() async {
      entered = true;
      return true;
    }

    await expectLater(
      value.run(() => runSyncPass(
            hasPendingTransfers: action,
            reconcile: action,
            sync: action,
          )),
      throwsA(isA<BackgroundSyncInterrupted>()),
    );
    expect(entered, isFalse);
  });

  group('idle transfer dispatcher', () {
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('fife-idle-queue-');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      await StorageSqlite.initialize(ExecutionMode.backgroundWorker);
    });

    tearDown(() async {
      await TaskManager.stopBackgroundWakes();
      await StorageSqlite.instance.close();
      messenger.setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    });

    for (final blocked in [false, true]) {
      test(
          '${blocked ? 'blocked' : 'empty'} queue needs no connectivity probe or transfer reserve',
          () async {
        final db = await StorageSqlite.instance.database;
        if (blocked) {
          await db.insert('item_tasks', {
            'id': 'blocked-fixture',
            'task': ItemTask.upload.value,
            'state': 'blocked',
            'attempt_count': 3,
            'last_error': 'upload_source_changed',
          });
        }
        final before = await db.query('item_tasks');
        var probes = 0;
        final value = budget(elapsed: () => const Duration(seconds: 17));
        await HttpOverrides.runZoned(
          () => value.run(TaskManager.init),
          createHttpClient: (_) {
            probes++;
            throw StateError('No eligible transfer needs a network probe');
          },
        );
        expect(probes, 0);
        expect(value.interrupted, isFalse);
        expect(await db.query('item_tasks'), before);
        expect(await db.query('states'), isEmpty);
      });
    }

    test('offline eligible work stays pending without consuming retries',
        () async {
      final db = await StorageSqlite.instance.database;
      await db.insert('item_tasks', {
        'id': 'offline-fixture',
        'task': ItemTask.upload.value,
        'state': 'pending',
        'attempt_count': 2,
      });
      final before = await db.query('item_tasks');
      var probes = 0;
      await HttpOverrides.runZoned(
        () => budget().run(TaskManager.init),
        createHttpClient: (_) {
          probes++;
          throw const SocketException('Controlled offline connection');
        },
      );
      expect(probes, greaterThan(0));
      expect(await db.query('item_tasks'), before);
      expect(await db.query('states'), isEmpty);
    });
  });
}
