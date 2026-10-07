import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIosBackgroundScheduler implements IosBackgroundScheduler {
  Object? initializeError;
  Object? scheduleError;
  Object? cancelError;
  int initializeCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;

  Future<void> _completeOrThrow(Object? error) async {
    if (error != null) throw error;
  }

  @override
  Future<void> initialize(Function callbackDispatcher) async {
    initializeCalls += 1;
    await _completeOrThrow(initializeError);
  }

  @override
  Future<void> schedule() async {
    scheduleCalls += 1;
    await _completeOrThrow(scheduleError);
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    await _completeOrThrow(cancelError);
  }
}

void main() {
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
      backgroundSyncEnabled: true,
      signedIn: true,
    );

    expect(await service.initialize(iosCallbackDispatcher: () {}), isFalse);
    expect(scheduler.initializeCalls, 1);
    expect(scheduler.scheduleCalls, 0);
  });

  test('iOS scheduling failure is contained after initialization', () async {
    final scheduler = _FakeIosBackgroundScheduler()
      ..scheduleError = StateError('submission rejected');
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
      backgroundSyncEnabled: true,
      signedIn: true,
    );

    expect(await service.initialize(iosCallbackDispatcher: () {}), isFalse);
    expect(scheduler.initializeCalls, 1);
    expect(scheduler.scheduleCalls, 1);
  });

  test('disabled iOS background sync cancels stale work best effort', () async {
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

  test('signed-out iOS account cannot schedule enabled background work', () async {
    final scheduler = _FakeIosBackgroundScheduler();
    final service = BackgroundExecutionService.test(
      kind: BackgroundExecutionKind.iosRefresh,
      iosScheduler: scheduler,
      backgroundSyncEnabled: true,
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
}
