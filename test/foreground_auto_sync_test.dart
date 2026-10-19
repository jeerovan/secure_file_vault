import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/service_foreground_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/temporary_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const foreground = MethodChannel('flutter_foreground_task/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime(2026, 10, 19);
  late Directory directory;
  late List<MethodCall> calls;
  late bool running;
  Completer<void>? idleNotification;
  Future<void> Function(MethodCall)? interceptNotification;
  void Function(Object)? taskReceiver;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fife-foreground-sync-');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    await ModelSetting.set(AppString.locale.string, 'en');
    calls = [];
    running = true;
    idleNotification = null;
    interceptNotification = null;
    taskReceiver = null;
    messenger.setMockMethodCallHandler(foreground, (call) async {
      calls.add(call);
      if (call.method == 'isRunningService') return running;
      if (call.method == 'startService') running = true;
      if (call.method == 'stopService') running = false;
      if (call.method == 'sendData') taskReceiver?.call(call.arguments);
      if (call.method == 'updateService') {
        await interceptNotification?.call(call);
        final text = call.arguments['notificationContentText'];
        if (text is String &&
            text.startsWith('Run every ') &&
            idleNotification?.isCompleted == false) {
          idleNotification!.complete();
        }
      }
      return null;
    });
    ServiceForeground.instance.init();
    FlutterForegroundTask.skipServiceResponseCheck = true;
  });

  tearDown(() async {
    FlutterForegroundTask.resetStatic();
    await StorageSqlite.instance.close();
    ModelSetting.clear();
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(foreground, null);
    await deleteTestDirectory(directory);
  });

  test('a missing or invalid interval defaults to 15 and bounds are enforced',
      () {
    expect(ModelSetting.foregroundSyncIntervalMinutes, 15);
    for (final invalid in ['', 'invalid', '1.5']) {
      expect(ModelSetting.parseForegroundSyncIntervalMinutes(invalid), 15);
    }
    expect(ModelSetting.parseForegroundSyncIntervalMinutes('-1'), 1);
    expect(ModelSetting.parseForegroundSyncIntervalMinutes('0'), 1);
    expect(ModelSetting.parseForegroundSyncIntervalMinutes('31'), 30);
    expect(ModelSetting.parseForegroundSyncIntervalMinutes('1'), 1);
    expect(ModelSetting.parseForegroundSyncIntervalMinutes('30'), 30);
  });

  test('service schedules the default 15-minute native repeat', () async {
    expect(await ServiceForeground.instance.updateSyncInterval(), isTrue);
    final update = calls.singleWhere((c) => c.method == 'updateService');
    expect(update.arguments['taskEventAction'], {
      'taskEventType': 3,
      'taskEventInterval': const Duration(minutes: 15).inMilliseconds,
    });
  });

  for (final minutes in [1, 15, 30]) {
    test('service starts with a $minutes-minute subtitle and no buttons',
        () async {
      running = false;
      await ModelSetting.set(
          AppString.foregroundSyncIntervalMinutes.string, '$minutes');
      await ServiceForeground.instance.start();
      final start = calls.singleWhere((c) => c.method == 'startService');
      expect(start.arguments['notificationContentText'],
          'Run every $minutes ${minutes == 1 ? 'minute' : 'minutes'}');
      expect(start.arguments['buttons'], isEmpty);
    });
  }

  test('saved intervals survive reopening and override a stale isolate cache',
      () async {
    await ModelSetting.set(
        AppString.foregroundSyncIntervalMinutes.string, '30');
    await StorageSqlite.instance.close();
    ModelSetting.clear();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(ModelSetting.foregroundSyncIntervalMinutes, 30);
    // Another isolate may still hold an old cached value.
    ModelSetting.settingJson[AppString.foregroundSyncIntervalMinutes.string] =
        '1';
    await ServiceForeground.instance.start();
    final update = calls.singleWhere((c) => c.method == 'updateService');
    expect(update.arguments['taskEventAction']['taskEventInterval'], 1800000);
    expect(calls.where((c) => c.method == 'restartService'), isEmpty);
  });

  test('changing a running interval updates scheduling without restarting',
      () async {
    for (final minutes in [1, 30, 15]) {
      await ModelSetting.set(
          AppString.foregroundSyncIntervalMinutes.string, '$minutes');
      expect(await ServiceForeground.instance.updateSyncInterval(), isTrue);
    }
    final updates = calls.where((c) => c.method == 'updateService').toList();
    expect(
      updates.map((c) => c.arguments['taskEventAction']['taskEventInterval']),
      [60000, 1800000, 900000],
    );
    expect(calls.where((c) => c.method == 'restartService'), isEmpty);
    expect(calls.where((c) => c.method == 'startService'), isEmpty);
    expect(updates.every((c) => c.arguments['callbackHandle'] == null), isTrue);
    expect(updates.every((c) => c.arguments['buttons'].isEmpty), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'sendData').map((c) => c.arguments),
        everyElement(foregroundSyncIntervalChangedMessage));
    expect(calls.where((c) => c.method == 'sendData'), hasLength(3));
  });

  test('disabled service stays stopped; re-enabling uses the saved interval',
      () async {
    await ServiceForeground.instance.stop();
    await ModelSetting.set(AppString.foregroundSyncIntervalMinutes.string, '1');
    calls.clear();
    await ServiceForeground.instance.updateSyncInterval();
    expect(calls.where((c) => c.method == 'updateService'), isEmpty);
    expect(calls.where((c) => c.method == 'startService'), isEmpty);
    await ServiceForeground.instance.start();
    final start = calls.singleWhere((c) => c.method == 'startService');
    expect(start.arguments['taskEventAction']['taskEventInterval'], 60000);
    expect(start.arguments['notificationContentText'], 'Run every 1 minute');
    expect(start.arguments['buttons'], isEmpty);
  });

  test('native interval update failure is reported and preserves the setting',
      () async {
    await ModelSetting.set(AppString.foregroundSyncIntervalMinutes.string, '2');
    messenger.setMockMethodCallHandler(foreground, (call) async {
      if (call.method == 'isRunningService') return true;
      throw PlatformException(code: 'unavailable');
    });
    expect(await ServiceForeground.instance.updateSyncInterval(), isFalse);
    expect(
        await ModelSetting.getRaw(
            AppString.foregroundSyncIntervalMinutes.string),
        '2');
  });

  Future<ForegroundTaskHandler> readyHandler(Future<bool> Function() sync,
      {bool clearCalls = true}) async {
    final handler = ForegroundTaskHandler.test(
      initialize: () async {},
      sync: sync,
    );
    addTearDown(() => handler.onDestroy(now, false));
    await handler.onStart(now, TaskStarter.developer);
    if (clearCalls) calls.clear();
    return handler;
  }

  Future<void> expectNotification(String text, void Function() notify) async {
    final refreshed = Completer<void>();
    interceptNotification = (call) async {
      if (call.arguments['notificationContentText'] == text &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    };
    notify();
    await refreshed.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    final update = calls.lastWhere((call) => call.method == 'updateService');
    expect(update.arguments['notificationContentText'], text);
    expect(update.arguments['buttons'], isEmpty);
    interceptNotification = null;
  }

  test('app activity reaches the task and restores the latest idle subtitle',
      () async {
    var runs = 0;
    final handler = await readyHandler(() async {
      runs++;
      return true;
    });
    taskReceiver = handler.onReceiveData;
    final lease = (await ExclusiveOperationCoordinator.tryAcquire('metadata'))!;
    addTearDown(() async {
      if (lease.isValid) await lease.release();
    });
    await expectNotification('In progress...', () {
      EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'metadata',
        key: EventKey.running,
      ));
    });
    expect(
        calls.where((call) =>
            call.method == 'sendData' &&
            call.arguments == foregroundSyncActivityChangedMessage),
        hasLength(1));
    await ModelSetting.set(
        AppString.foregroundSyncIntervalMinutes.string, '30');
    await lease.release();
    await expectNotification('Run every 30 minutes', () {
      EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'metadata',
        key: EventKey.stopped,
      ));
    });
    expect(runs, 0);
  });

  test('enabling the task during app sync immediately shows progress',
      () async {
    final lease = (await ExclusiveOperationCoordinator.tryAcquire('metadata'))!;
    addTearDown(lease.release);
    await readyHandler(() async => true, clearCalls: false);
    final update = calls.lastWhere((call) => call.method == 'updateService');
    expect(update.arguments['notificationContentText'], 'In progress...');
    expect(update.arguments['buttons'], isEmpty);
  });

  test('one finished operation cannot hide another active sync', () async {
    final handler = await readyHandler(() async => true);
    final metadata =
        (await ExclusiveOperationCoordinator.tryAcquire('metadata'))!;
    final reconciliation =
        (await ReconciliationCoordinator.tryAcquire('root'))!;
    for (final lease in [metadata, reconciliation]) {
      addTearDown(() async {
        if (lease.isValid) await lease.release();
      });
    }
    await expectNotification('In progress...',
        () => handler.onReceiveData(foregroundSyncActivityChangedMessage));
    await metadata.release();
    await expectNotification('In progress...',
        () => handler.onReceiveData(foregroundSyncActivityChangedMessage));
    await reconciliation.release();
    await expectNotification('Run every 15 minutes',
        () => handler.onReceiveData(foregroundSyncActivityChangedMessage));
  });

  test('task-local retry activity refreshes progress until destruction',
      () async {
    final handler = await readyHandler(() async => true);
    final lease = (await ExclusiveOperationCoordinator.tryAcquire('metadata'))!;
    addTearDown(lease.release);
    await expectNotification('In progress...', () {
      EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'metadata',
        key: EventKey.running,
      ));
    });
    await handler.onDestroy(now, false);
    calls.clear();
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'metadata',
      key: EventKey.stopped,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'updateService'), isEmpty);
  });

  test('initialization is idempotent and service echoes are not forwarded',
      () async {
    ServiceForeground.instance.init();
    for (final id in ['foregroundSync', 'metadata']) {
      EventStream().publish(AppEvent(
        type: EventType.system,
        id: id,
        key: id == 'foregroundSync' ? EventKey.running : EventKey.object,
      ));
    }
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'sendData'), isEmpty);
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'root',
      key: EventKey.running,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'sendData'), hasLength(1));
  });

  test('app activity cannot start or update a disabled service', () async {
    running = false;
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'metadata',
      key: EventKey.running,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.where((call) =>
            call.method == 'sendData' ||
            call.method == 'updateService' ||
            call.method == 'startService'),
        isEmpty);
  });

  test('repeated scheduled requests share one guarded sync operation',
      () async {
    var runs = 0;
    final entered = Completer<void>();
    final gate = Completer<bool>();
    final handler = await readyHandler(() async {
      runs++;
      if (runs == 1) {
        entered.complete();
        return gate.future;
      }
      return true;
    });
    idleNotification = Completer<void>();
    handler.onRepeatEvent(now);
    await entered.future;
    handler.onRepeatEvent(now);
    await handler.startSyncTask();
    expect(runs, 1);
    gate.complete(true);
    await idleNotification!.future;
    await Future<void>.delayed(Duration.zero);
    await handler.startSyncTask();
    expect(runs, 2);
    final updates = calls.where((c) => c.method == 'updateService').toList();
    expect(updates.first.arguments['buttons'], isEmpty);
    expect(updates.every((c) => c.arguments['buttons'].isEmpty), isTrue);
    expect(
        updates.first.arguments['notificationContentText'], 'In progress...');
    expect(updates.last.arguments['notificationContentText'],
        'Run every 15 minutes');
  });

  test(
      'failed and unsuccessful runs restore the interval and allow another run',
      () async {
    var runs = 0;
    final handler = await readyHandler(() async {
      runs++;
      if (runs == 1) throw StateError('Controlled sync failure');
      return runs > 2;
    });
    for (var i = 0; i < 3; i++) {
      await handler.startSyncTask();
      final update = calls.lastWhere((c) => c.method == 'updateService');
      expect(update.arguments['buttons'], isEmpty);
      expect(
          update.arguments['notificationContentText'], 'Run every 15 minutes');
    }
    expect(runs, 3);
  });

  test('requests wait until initialization and are ignored after destruction',
      () async {
    var runs = 0;
    final initialized = Completer<void>();
    final handler = ForegroundTaskHandler.test(
      initialize: () => initialized.future,
      sync: () async {
        runs++;
        return true;
      },
    );
    final start = handler.onStart(now, TaskStarter.developer);
    handler.onRepeatEvent(now);
    handler.onNotificationButtonPressed('sync');
    await handler.startSyncTask();
    expect(runs, 0);
    initialized.complete();
    await start;
    await handler.startSyncTask();
    expect(runs, 1);
    await handler.onDestroy(now, false);
    handler.onRepeatEvent(now);
    handler.onNotificationButtonPressed('sync');
    await handler.startSyncTask();
    expect(runs, 1);
  });

  test('destroying the service during initialization cannot enable sync',
      () async {
    var runs = 0;
    final initialized = Completer<void>();
    final handler = ForegroundTaskHandler.test(
      initialize: () => initialized.future,
      sync: () async {
        runs++;
        return true;
      },
    );
    final start = handler.onStart(now, TaskStarter.developer);
    await handler.onDestroy(now, true);
    initialized.complete();
    await start;
    await handler.startSyncTask();
    expect(runs, 0);
  });

  test('destruction during sync does not restore a stopped notification',
      () async {
    final gate = Completer<bool>();
    final entered = Completer<void>();
    final handler = await readyHandler(() {
      entered.complete();
      return gate.future;
    });
    final work = handler.startSyncTask();
    await entered.future;
    await handler.onDestroy(now, false);
    gate.complete(true);
    await work;
    final updates = calls.where((c) => c.method == 'updateService').toList();
    expect(updates, hasLength(1));
    expect(updates.single.arguments['buttons'], isEmpty);
  });

  test('notification actions cannot initiate manual sync', () async {
    var runs = 0;
    final handler = await readyHandler(() async {
      runs++;
      return true;
    });
    handler.onNotificationButtonPressed('other');
    handler.onNotificationButtonPressed('sync');
    await Future<void>.delayed(Duration.zero);
    expect(runs, 0);
  });

  test('task startup publishes the interval without any notification actions',
      () async {
    final handler = ForegroundTaskHandler.test(
      initialize: () async {},
      sync: () async => true,
    );
    addTearDown(() => handler.onDestroy(now, false));
    await handler.onStart(now, TaskStarter.system);
    final update = calls.singleWhere((c) => c.method == 'updateService');
    expect(update.arguments['notificationContentText'], 'Run every 15 minutes');
    expect(update.arguments['buttons'], isEmpty);
  });

  test(
      'idle interval changes refresh the subtitle from current SQLite settings',
      () async {
    final handler = await readyHandler(() async => true);
    await ModelSetting.set(
        AppString.foregroundSyncIntervalMinutes.string, '30');
    ModelSetting.settingJson[AppString.foregroundSyncIntervalMinutes.string] =
        '1';
    final refreshed = Completer<void>();
    interceptNotification = (call) async {
      if (call.arguments['notificationContentText'] == 'Run every 30 minutes') {
        refreshed.complete();
      }
    };
    handler.onReceiveData(foregroundSyncIntervalChangedMessage);
    await refreshed.future;
    await Future<void>.delayed(Duration.zero);
    final update = calls.lastWhere((c) => c.method == 'updateService');
    expect(update.arguments['buttons'], isEmpty);
  });

  for (final fails in [false, true]) {
    test(
        'interval changes preserve progress and restore the latest value after ${fails ? 'failure' : 'success'}',
        () async {
      final entered = Completer<void>();
      final gate = Completer<bool>();
      final handler = await readyHandler(() {
        entered.complete();
        return gate.future;
      });
      final work = handler.startSyncTask();
      await entered.future;
      await ModelSetting.set(
          AppString.foregroundSyncIntervalMinutes.string, '30');
      ModelSetting.settingJson[AppString.foregroundSyncIntervalMinutes.string] =
          '1';
      final refreshed = Completer<void>();
      interceptNotification = (call) async {
        if (!refreshed.isCompleted) refreshed.complete();
      };
      handler.onReceiveData(foregroundSyncIntervalChangedMessage);
      await refreshed.future;
      final update = calls.lastWhere((c) => c.method == 'updateService');
      expect(update.arguments['notificationContentText'], 'In progress...');
      expect(update.arguments['buttons'], isEmpty);
      if (fails) {
        gate.completeError(StateError('Controlled sync failure'));
      } else {
        gate.complete(true);
      }
      await work;
      final idle = calls.lastWhere((c) => c.method == 'updateService');
      expect(idle.arguments['notificationContentText'], 'Run every 30 minutes');
      expect(idle.arguments['buttons'], isEmpty);
    });
  }

  test('an idle update in flight cannot replace a new sync progress update',
      () async {
    final entered = Completer<void>();
    final syncGate = Completer<bool>();
    final handler = await readyHandler(() {
      entered.complete();
      return syncGate.future;
    });
    await ModelSetting.set(
        AppString.foregroundSyncIntervalMinutes.string, '30');
    final idleStarted = Completer<void>();
    final idleGate = Completer<void>();
    interceptNotification = (call) async {
      if (call.arguments['notificationContentText'] == 'Run every 30 minutes' &&
          !idleStarted.isCompleted) {
        idleStarted.complete();
        await idleGate.future;
      }
    };
    handler.onReceiveData(foregroundSyncIntervalChangedMessage);
    await idleStarted.future;
    final work = handler.startSyncTask();
    expect(entered.isCompleted, isFalse);
    idleGate.complete();
    await entered.future;
    final active = calls.lastWhere((c) => c.method == 'updateService');
    expect(active.arguments['notificationContentText'], 'In progress...');
    syncGate.complete(true);
    await work;
    final idle = calls.lastWhere((c) => c.method == 'updateService');
    expect(idle.arguments['notificationContentText'], 'Run every 30 minutes');
    expect(idle.arguments['buttons'], isEmpty);
  });
}
