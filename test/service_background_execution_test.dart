import 'dart:async';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

class _FakeIosBackgroundScheduler implements IosBackgroundScheduler {
  Object? initializeError;
  Object? scheduleError;
  Object? cancelError;
  int initializeCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  bool pending = false;
  Future<void> Function()? onInitialize;
  Future<void> Function()? onSchedule;
  final events = <String>[];

  Future<void> _completeOrThrow(Object? error) async {
    if (error != null) throw error;
  }

  @override
  Future<void> initialize(Function callbackDispatcher) async {
    initializeCalls += 1;
    events.add('initialize');
    await onInitialize?.call();
    await _completeOrThrow(initializeError);
  }

  @override
  Future<void> schedule() async {
    scheduleCalls += 1;
    events.add('schedule');
    await onSchedule?.call();
    await _completeOrThrow(scheduleError);
    pending = true;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    events.add('cancel');
    await _completeOrThrow(cancelError);
    pending = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android selects foreground execution only', () {
    expect(
      selectBackgroundExecutionKind(
        isAndroid: true,
        isIOS: false,
        isDesktop: false,
      ),
      BackgroundExecutionKind.androidForeground,
    );
  });

  test('iOS selects native app refresh execution only', () {
    expect(
      selectBackgroundExecutionKind(
        isAndroid: false,
        isIOS: true,
        isDesktop: false,
      ),
      BackgroundExecutionKind.iosRefresh,
    );
  });

  test('desktop selection remains distinct from mobile execution', () {
    expect(
      selectBackgroundExecutionKind(
        isAndroid: false,
        isIOS: false,
        isDesktop: true,
      ),
      BackgroundExecutionKind.desktopTimer,
    );
  });

  test('iOS scheduler initialization failure is contained', () async {
    final scheduler = _FakeIosBackgroundScheduler()
      ..initializeError = StateError('unavailable');
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
      signedIn: true,
    );

    expect(await service.initialize(iosCallbackDispatcher: () {}), isFalse);
    expect(scheduler.initializeCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('signed-in iOS schedules without opting in to background sync',
      () async {
    final scheduler = _FakeIosBackgroundScheduler();
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
      signedIn: true,
    );
    expect(await service.initialize(iosCallbackDispatcher: () {}), isTrue);
    expect(scheduler.scheduleCalls, 1);
    expect(scheduler.cancelCalls, 0);
  });

  test('iOS scheduling failure is contained after initialization', () async {
    final scheduler = _FakeIosBackgroundScheduler()
      ..scheduleError = StateError('submission rejected');
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
      signedIn: true,
    );

    expect(await service.initialize(iosCallbackDispatcher: () {}), isFalse);
    expect(scheduler.initializeCalls, 1);
    expect(scheduler.scheduleCalls, 1);
  });

  test('signed-out iOS cancels stale work best effort', () async {
    final scheduler = _FakeIosBackgroundScheduler()
      ..cancelError = StateError('cancellation unavailable');
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
    );

    expect(await service.initialize(iosCallbackDispatcher: () {}), isFalse);
    expect(scheduler.initializeCalls, 1);
    expect(scheduler.cancelCalls, 1);
  });

  test('worker failure returns false and still runs every cleanup', () async {
    final cleanupCalls = <String>[];
    final failures = <String>[];

    final result = await runBackgroundWorkerSafely(
      task: () async => throw StateError('worker failed'),
      cleanupActions: [
        BackgroundCleanupAction('first', () => cleanupCalls.add('first')),
        BackgroundCleanupAction('second', () => cleanupCalls.add('second')),
      ],
      onError: (operation, error, stackTrace) => failures.add(operation),
    );

    expect(result, isFalse);
    expect(cleanupCalls, ['first', 'second']);
    expect(failures, ['execution']);
  });

  test('signed-out iOS account cannot schedule enabled background work',
      () async {
    final scheduler = _FakeIosBackgroundScheduler();
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
    );
    expect(await service.initialize(iosCallbackDispatcher: () {}), isTrue);
    expect(await service.setEnabled(true), isTrue);
    expect(scheduler.scheduleCalls, 0);
    expect(scheduler.cancelCalls, 2);
  });

  test('cleanup failure is contained and later cleanup still runs', () async {
    final cleanupCalls = <String>[];
    final failures = <String>[];

    final result = await runBackgroundWorkerSafely(
      task: () async => true,
      cleanupActions: [
        BackgroundCleanupAction('first', () {
          cleanupCalls.add('first');
          throw StateError('cleanup failed');
        }),
        BackgroundCleanupAction('second', () => cleanupCalls.add('second')),
      ],
      onError: (operation, error, stackTrace) => failures.add(operation),
    );

    expect(result, isFalse);
    expect(cleanupCalls, ['first', 'second']);
    expect(failures, ['cleanup:first']);
  });

  test('setup completing during native initialization schedules automatically',
      () async {
    final gate = Completer<void>();
    final scheduler = _FakeIosBackgroundScheduler()
      ..onInitialize = (() => gate.future);
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        signedIn: true);
    final initializing = service.initialize(iosCallbackDispatcher: () {});
    final setup = service.setEnabled(true);
    gate.complete();
    await Future.wait([initializing, setup]);
    expect(scheduler.pending, isTrue);
    expect(scheduler.initializeCalls, 1);
  });

  test('cleanup cancels requests even before this process initializes',
      () async {
    final scheduler = _FakeIosBackgroundScheduler()..pending = true;
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh, iosScheduler: scheduler);
    expect(await service.cancelIosWork(), isTrue);
    expect(scheduler.pending, isFalse);
    expect(scheduler.initializeCalls, 0);
  });

  test('cleanup during initialization cannot be overwritten by startup',
      () async {
    final gate = Completer<void>();
    final scheduler = _FakeIosBackgroundScheduler()
      ..pending = true
      ..onInitialize = (() => gate.future);
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        signedIn: true);
    final initializing = service.initialize(iosCallbackDispatcher: () {});
    final cleanup = service.cancelIosWork();
    gate.complete();
    await Future.wait([initializing, cleanup]);
    expect(scheduler.pending, isFalse);
    expect(scheduler.scheduleCalls, 0);
  });

  test('cleanup after an in-flight submission leaves no pending request',
      () async {
    final started = Completer<void>(), gate = Completer<void>();
    final scheduler = _FakeIosBackgroundScheduler()
      ..onSchedule = (() async {
        started.complete();
        await gate.future;
      });
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        signedIn: true);
    final initializing = service.initialize(iosCallbackDispatcher: () {});
    await started.future;
    final cleanup = service.cancelIosWork();
    gate.complete();
    await Future.wait([initializing, cleanup]);
    expect(scheduler.pending, isFalse);
    expect(scheduler.events.last, 'cancel');
  });

  test('a later completed login can resume after cleanup', () async {
    var ready = true;
    final scheduler = _FakeIosBackgroundScheduler();
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        iosSessionReady: () async => ready);
    await service.initialize(iosCallbackDispatcher: () {});
    ready = false;
    await service.cancelIosWork();
    expect(scheduler.pending, isFalse);
    ready = true;
    expect(await service.setEnabled(true), isTrue);
    expect(scheduler.pending, isTrue);
  });

  group('durable iOS session eligibility', () {
    late SyncFixture fixture;
    setUp(() async {
      fixture = await SyncFixture.create();
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'yes');
    });
    tearDown(() async {
      SessionWork.resetForTesting();
      await fixture.dispose();
    });

    BackgroundExecutionService service(_FakeIosBackgroundScheduler scheduler) =>
        BackgroundExecutionService.test(
            kind: BackgroundExecutionKind.iosRefresh,
            iosScheduler: scheduler,
            iosSessionReady: isIosBackgroundSyncReady);

    for (final legacy in [null, 'no', 'yes', 'invalid']) {
      test(
          'ready account syncs with legacy preference $legacy; App lock stays optional',
          () async {
        if (legacy != null) {
          await ModelSetting.set(AppString.backgroundSync.string, legacy);
        }
        ModelSetting.settingJson[AppString.signedIn.string] = 'no';
        ModelSetting.settingJson[AppString.backgroundSync.string] = 'no';
        final scheduler = _FakeIosBackgroundScheduler();
        expect(
            await service(scheduler).initialize(iosCallbackDispatcher: () {}),
            isTrue);
        expect(scheduler.pending, isTrue);
        expect((await ModelAppLockStore().read()).enabled, isFalse);
        expect((await ModelAppLockStore().read()).minutes, 5);
        expect(await ModelSetting.getRaw(AppString.backgroundSync.string),
            legacy ?? '');
      });
    }

    test('background scheduling preserves an enabled App lock and its timeout',
        () async {
      final store = ModelAppLockStore();
      await store.setEnabled(true);
      await store.setTimeout(25);
      final scheduler = _FakeIosBackgroundScheduler();
      expect(await service(scheduler).initialize(iosCallbackDispatcher: () {}),
          isTrue);
      expect(scheduler.pending, isTrue);
      final policy = await store.read();
      expect(policy.enabled, isTrue);
      expect(policy.minutes, 25);
    });

    for (final missing in [
      'onboarding',
      'signed-in',
      'device',
      'key',
      'empty-key',
      'reset',
      'key-setup'
    ]) {
      test('incomplete $missing state cancels stale native work', () async {
        switch (missing) {
          case 'onboarding':
            await ModelSetting.delete(AppString.onboarding.string);
          case 'signed-in':
            await ModelSetting.set(AppString.signedIn.string, 'no');
          case 'device':
            await ModelSetting.delete(AppString.deviceUuid.string);
          case 'key':
            fixture.secrets.remove(AppString.masterKey.string);
          case 'empty-key':
            fixture.secrets[AppString.masterKey.string] = '';
          case 'reset':
            fixture.secrets[AppString.recoveryResetStage.string] = 'pending';
          case 'key-setup':
            fixture.secrets[AppString.vaultKeySetupStage.string] = 'pending';
        }
        ModelSetting.settingJson[AppString.signedIn.string] = 'yes';
        final scheduler = _FakeIosBackgroundScheduler()..pending = true;
        expect(await isIosBackgroundSyncReady(), isFalse);
        expect(
            await service(scheduler).initialize(iosCallbackDispatcher: () {}),
            isTrue);
        expect(scheduler.pending, isFalse);
      });
    }

    test(
        'key storage failure cancels stale work and returns a contained failure',
        () async {
      fixture.beforeRead =
          (_) async => throw StateError('key storage unavailable');
      final scheduler = _FakeIosBackgroundScheduler()..pending = true;
      expect(await service(scheduler).initialize(iosCallbackDispatcher: () {}),
          isFalse);
      expect(scheduler.pending, isFalse);
    });

    test('revocation while reading keys cannot schedule old-session work',
        () async {
      final started = Completer<void>(), gate = Completer<void>();
      fixture.beforeRead = (key) async {
        if (key == AppString.masterKey.string) {
          started.complete();
          await gate.future;
        }
      };
      final scheduler = _FakeIosBackgroundScheduler()..pending = true;
      final initializing =
          service(scheduler).initialize(iosCallbackDispatcher: () {});
      await started.future;
      SessionWork.invalidate('revoked');
      gate.complete();
      expect(await initializing, isFalse);
      expect(scheduler.pending, isFalse);
    });
  });
}
