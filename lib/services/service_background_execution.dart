import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

import '../models/model_setting.dart';
import '../storage/storage_secure.dart';
import '../utils/enums.dart';
import 'service_foreground.dart';
import 'service_logger.dart';
import 'service_session_work.dart';

const String iosBackgroundTaskIdentifier = 'com.jeerovan.fife.data_sync';

/// Scheduling and delivered workers use durable session state, never the old
/// background_sync opt-in or a possibly stale foreground settings cache.
Future<bool> isIosBackgroundSyncReady() => isVaultSyncReady();

/// Shared readiness for sync entry points outside Explorer (including macOS's
/// menu bar). A signed-in flag alone does not mean onboarding/keys are ready.
Future<bool> isVaultSyncReady() => SessionWork.run(() async {
      if (await ModelSetting.getRaw(AppString.onboarding.string) != 'yes' ||
          await ModelSetting.getRaw(AppString.signedIn.string) != 'yes' ||
          (await ModelSetting.getRaw(AppString.deviceUuid.string)).isEmpty) {
        return false;
      }
      final storage = SecureStorage();
      if (await storage.containsKey(key: AppString.recoveryResetStage.string) ||
          await storage.containsKey(key: AppString.vaultKeySetupStage.string)) {
        return false;
      }
      final key = await storage.read(key: AppString.masterKey.string);
      await SessionWork.checkpoint();
      return key?.isNotEmpty == true;
    });

abstract interface class IosBackgroundScheduler {
  Future<void> initialize(Function callbackDispatcher);
  Future<void> schedule();
  Future<void> cancel();
}

class NativeIosBackgroundScheduler implements IosBackgroundScheduler {
  static const channel =
      MethodChannel('com.jeerovan.fife/background_scheduler');
  @override
  Future<void> initialize(Function callbackDispatcher) async {
    final handle = PluginUtilities.getCallbackHandle(callbackDispatcher);
    if (handle == null) {
      throw StateError('Background entrypoint is not top-level');
    }
    await channel.invokeMethod<void>('initialize', {
      'callbackHandle': handle.toRawHandle(),
      'testDiagnostics': !kReleaseMode &&
          const bool.fromEnvironment('FIFE_BACKGROUND_TEST_DIAGNOSTICS'),
    });
  }

  @override
  Future<void> schedule() async {
    await channel.invokeMethod<void>('schedule');
  }

  @override
  Future<void> cancel() async {
    await channel.invokeMethod<void>('cancel');
  }
}

class BackgroundCleanupAction {
  const BackgroundCleanupAction(this.name, this.action);

  final String name;
  final FutureOr<void> Function() action;
}

Future<bool> runBackgroundWorkerSafely({
  required Future<bool> Function() task,
  required Iterable<BackgroundCleanupAction> cleanupActions,
  required void Function(String operation, Object error, StackTrace stackTrace)
      onError,
}) async {
  var succeeded = false;
  try {
    succeeded = await task();
  } catch (error, stackTrace) {
    onError('execution', error, stackTrace);
  }

  for (final cleanup in cleanupActions) {
    try {
      await cleanup.action();
    } catch (error, stackTrace) {
      succeeded = false;
      onError('cleanup:${cleanup.name}', error, stackTrace);
    }
  }
  return succeeded;
}

enum BackgroundExecutionKind {
  androidForeground,
  iosRefresh,
  desktopTimer,
  none,
}

@visibleForTesting
BackgroundExecutionKind selectBackgroundExecutionKind({
  required bool isAndroid,
  required bool isIOS,
  required bool isDesktop,
}) {
  if (isAndroid) return BackgroundExecutionKind.androidForeground;
  if (isIOS) return BackgroundExecutionKind.iosRefresh;
  if (isDesktop) return BackgroundExecutionKind.desktopTimer;
  return BackgroundExecutionKind.none;
}

class BackgroundExecutionService {
  BackgroundExecutionService._()
      : _kindResolver = _platformKind,
        _iosScheduler = NativeIosBackgroundScheduler(),
        _iosSessionReady = isIosBackgroundSyncReady;

  @visibleForTesting
  BackgroundExecutionService.test({
    required BackgroundExecutionKind kind,
    required IosBackgroundScheduler iosScheduler,
    bool signedIn = false,
    Future<bool> Function()? iosSessionReady,
  })  : _kindResolver = (() => kind),
        _iosScheduler = iosScheduler,
        _iosSessionReady = iosSessionReady ?? (() async => signedIn);

  static final BackgroundExecutionService instance =
      BackgroundExecutionService._();

  final AppLogger _logger = AppLogger(prefixes: ['Background Execution']);
  final BackgroundExecutionKind Function() _kindResolver;
  final IosBackgroundScheduler _iosScheduler;
  final Future<bool> Function() _iosSessionReady;
  bool _iosInitialized = false;
  bool _iosWantsScheduling = true;
  int _iosRequest = 0;
  Future<bool>? _iosInitializing;
  Future<void> _iosWork = Future.value();

  BackgroundExecutionKind get kind => _kindResolver();

  Future<bool> initialize({required Function iosCallbackDispatcher}) async {
    switch (kind) {
      case BackgroundExecutionKind.androidForeground:
        ServiceForeground.instance.init();
        return true;
      case BackgroundExecutionKind.iosRefresh:
        final initializing = _iosInitializing ??= _runIosAction('initialize',
                () => _iosScheduler.initialize(iosCallbackDispatcher))
            .then((ready) => _iosInitialized = ready);
        final initialized = await initializing;
        if (identical(_iosInitializing, initializing)) _iosInitializing = null;
        if (!initialized) {
          await _reconcileIosWork();
          return false;
        }
        return _reconcileIosWork();
      case BackgroundExecutionKind.desktopTimer:
      case BackgroundExecutionKind.none:
        return true;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    switch (kind) {
      case BackgroundExecutionKind.androidForeground:
        if (enabled) {
          await ServiceForeground.instance.start();
        } else {
          await ServiceForeground.instance.stop();
        }
        return true;
      case BackgroundExecutionKind.iosRefresh:
        _iosWantsScheduling = enabled;
        return _reconcileIosWork();
      case BackgroundExecutionKind.desktopTimer:
      case BackgroundExecutionKind.none:
        return true;
    }
  }

  Future<bool> cancelIosWork() async {
    if (kind == BackgroundExecutionKind.iosRefresh) {
      _iosWantsScheduling = false;
      return _reconcileIosWork();
    }
    return true;
  }

  Future<bool> _reconcileIosWork() {
    final request = ++_iosRequest;
    final work = _iosWork.then((_) async {
      if (_iosInitializing case final initializing?) await initializing;
      if (request != _iosRequest) return false;
      // Native cancellation needs no Dart callback registration. Cleanup on a
      // cold start must also cancel requests left by an earlier app process.
      if (!_iosWantsScheduling) return _cancelIosWork();
      if (!_iosInitialized) {
        await _cancelIosWork();
        return false;
      }
      var ready = false;
      final readable = await _runIosAction('check session', () async {
        ready = await _iosSessionReady();
      });
      if (request != _iosRequest) return false;
      if (!readable) {
        await _cancelIosWork();
        return false;
      }
      return ready ? _scheduleIosWork() : _cancelIosWork();
    });
    // Serialize native requests: cancellation queued during an in-flight
    // submission runs after it, so that submission cannot resurrect work.
    _iosWork = work.then<void>((_) {});
    return work;
  }

  Future<bool> _scheduleIosWork() async {
    final scheduled = await _runIosAction(
      'schedule',
      _iosScheduler.schedule,
    );
    if (scheduled) _logger.info('Scheduled iOS background sync');
    return scheduled;
  }

  Future<bool> _cancelIosWork() async {
    final cancelled = await _runIosAction(
      'cancel',
      _iosScheduler.cancel,
    );
    if (cancelled) _logger.info('Cancelled iOS background sync');
    return cancelled;
  }

  Future<bool> _runIosAction(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      _logger.error(
        'iOS background sync $operation failed; foreground app will continue',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static BackgroundExecutionKind _platformKind() =>
      selectBackgroundExecutionKind(
        isAndroid: Platform.isAndroid,
        isIOS: Platform.isIOS,
        isDesktop: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
      );
}
