import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../models/model_setting.dart';
import '../utils/enums.dart';
import 'service_foreground.dart';
import 'service_logger.dart';

const String iosBackgroundTaskIdentifier = 'com.jeerovan.fife.data_sync';
const String iosBackgroundTaskName = 'dataSync';

abstract interface class IosBackgroundScheduler {
  Future<void> initialize(Function callbackDispatcher);
  Future<void> schedule();
  Future<void> cancel();
}

class WorkmanagerIosBackgroundScheduler implements IosBackgroundScheduler {
  @override
  Future<void> initialize(Function callbackDispatcher) async {
    await Workmanager().initialize(callbackDispatcher);
  }

  @override
  Future<void> schedule() async {
    await Workmanager().registerPeriodicTask(
      iosBackgroundTaskIdentifier,
      iosBackgroundTaskName,
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(iosBackgroundTaskIdentifier);
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
      onError('cleanup:${cleanup.name}', error, stackTrace);
    }
  }
  return succeeded;
}

enum BackgroundExecutionKind {
  androidForeground,
  iosWorkmanager,
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
  if (isIOS) return BackgroundExecutionKind.iosWorkmanager;
  if (isDesktop) return BackgroundExecutionKind.desktopTimer;
  return BackgroundExecutionKind.none;
}

class BackgroundExecutionService {
  BackgroundExecutionService._()
      : _kindResolver = _platformKind,
        _iosScheduler = WorkmanagerIosBackgroundScheduler(),
        _backgroundSyncEnabled = _storedBackgroundSyncEnabled,
        _signedIn = _storedSignedIn;

  @visibleForTesting
  BackgroundExecutionService.test({
    required BackgroundExecutionKind kind,
    required IosBackgroundScheduler iosScheduler,
    bool backgroundSyncEnabled = false,
    bool signedIn = false,
  })  : _kindResolver = (() => kind),
        _iosScheduler = iosScheduler,
        _backgroundSyncEnabled = (() => backgroundSyncEnabled),
        _signedIn = (() => signedIn);

  static final BackgroundExecutionService instance =
      BackgroundExecutionService._();

  final AppLogger _logger = AppLogger(prefixes: ['Background Execution']);
  final BackgroundExecutionKind Function() _kindResolver;
  final IosBackgroundScheduler _iosScheduler;
  final bool Function() _backgroundSyncEnabled;
  final bool Function() _signedIn;
  bool _workmanagerInitialized = false;

  BackgroundExecutionKind get kind => _kindResolver();

  Future<bool> initialize({required Function iosCallbackDispatcher}) async {
    switch (kind) {
      case BackgroundExecutionKind.androidForeground:
        ServiceForeground.instance.init();
        return true;
      case BackgroundExecutionKind.iosWorkmanager:
        _workmanagerInitialized = await _runIosAction(
          'initialize',
          () => _iosScheduler.initialize(iosCallbackDispatcher),
        );
        if (!_workmanagerInitialized) return false;
        if (_backgroundSyncEnabled() && _signedIn()) {
          return _scheduleIosWork();
        }
        return _cancelIosWork();
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
      case BackgroundExecutionKind.iosWorkmanager:
        if (!_workmanagerInitialized) {
          _logger.warning(
              'Ignored iOS background sync change because Workmanager is unavailable');
          return false;
        }
        if (enabled) {
          return _scheduleIosWork();
        }
        return _cancelIosWork();
      case BackgroundExecutionKind.desktopTimer:
      case BackgroundExecutionKind.none:
        return true;
    }
  }

  Future<bool> cancelIosWork() async {
    if (kind == BackgroundExecutionKind.iosWorkmanager &&
        _workmanagerInitialized) {
      return _cancelIosWork();
    }
    return true;
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

  static bool _storedBackgroundSyncEnabled() =>
      ModelSetting.get(
        AppString.backgroundSync.string,
        defaultValue: 'no',
      ) ==
      'yes';

  static bool _storedSignedIn() =>
      ModelSetting.get(
        AppString.signedIn.string,
        defaultValue: 'no',
      ) ==
      'yes';
}
