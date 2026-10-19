import 'dart:async';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/model_setting.dart';
import '../services/service_logger.dart';
import '../services/service_events.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../utils/utils_sync.dart';

class ForegroundTaskHandler extends TaskHandler {
  ForegroundTaskHandler()
      : _initialize = _initializeService,
        _sync = _syncFolders;

  @visibleForTesting
  ForegroundTaskHandler.test({
    required Future<void> Function() initialize,
    required Future<bool> Function() sync,
  })  : _initialize = initialize,
        _sync = sync;

  final Future<void> Function() _initialize;
  final Future<bool> Function() _sync;
  final AppLogger logger = AppLogger(prefixes: ["Foreground Handler"]);
  bool _ready = false;
  bool _destroyed = false;
  bool _syncRunning = false;
  Future<void> _notificationUpdates = Future<void>.value();
  StreamSubscription<AppEvent>? _activitySubscription;

  static Future<void> _initializeService() async {
    WidgetsFlutterBinding.ensureInitialized();
    await StorageSqlite.initialize(ExecutionMode.foregroundService);
    await initializeDependencies(ExecutionMode.foregroundService);
  }

  static Future<bool> _syncFolders() =>
      SyncUtils().reconFolders(caller: 'ForegroundService');

  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initialize();
    _ready = !_destroyed;
    if (_ready) {
      _activitySubscription ??= EventStream().events.listen((event) {
        if (isSyncActivityEvent(event)) unawaited(_refreshNotification());
      });
    }
    await _refreshNotification();
    logger.info(
      "OnStart: $starter",
    );
  }

  // Called based on the eventAction set in ForegroundTaskOptions.
  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(startSyncTask());
  }

  // Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _destroyed = true;
    _ready = false;
    await _activitySubscription?.cancel();
    _activitySubscription = null;
    logger.info('onDestroy(isTimeout: $isTimeout)');
  }

  // Called when data is sent using `FlutterForegroundTask.sendDataToTask`.
  @override
  void onReceiveData(Object data) {
    if (data == foregroundSyncIntervalChangedMessage ||
        data == foregroundSyncActivityChangedMessage) {
      unawaited(_refreshNotification());
    }
  }

  // Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    logger.info('onNotificationPressed');
  }

  // Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    logger.info('onNotificationDismissed');
  }

  Future<void> _refreshNotification() {
    // Serialize writes so an older idle update cannot replace sync progress.
    final update = _notificationUpdates.then((_) async {
      if (!_ready || _destroyed) return;
      final locale = Locale(await getAppLocale());
      final localizations = lookupAppLocalizations(locale);
      final minutes = await ModelSetting.getForegroundSyncIntervalMinutes();
      // Leases include work owned by the app's isolate and transfer retries.
      final activeSync = _syncRunning || await isRecordOrSyncInProgress();
      if (!_ready || _destroyed) return;
      final result = await FlutterForegroundTask.updateService(
        notificationText: activeSync
            ? localizations.quickSyncNotificationInProgress
            : localizations.quickSyncNotificationText(minutes),
        notificationButtons: [],
      );
      if (result is ServiceRequestFailure) {
        logger.error('Failed to update sync notification', error: result.error);
      }
    });
    _notificationUpdates = update.catchError((Object error, StackTrace stack) {
      logger.error('Failed to update sync notification',
          error: error, stackTrace: stack);
    });
    return _notificationUpdates;
  }

  Future<void> startSyncTask() async {
    if (!_ready || _destroyed || _syncRunning) return;
    _syncRunning = true;
    logger.info("Starting Sync Task");
    FlutterForegroundTask.sendDataToMain(
      ForegroundSyncStateMessage.encode(isRunning: true),
    );
    try {
      await _refreshNotification();
      if (!_destroyed) await _sync();
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
    } finally {
      _syncRunning = false;
      FlutterForegroundTask.sendDataToMain(
        ForegroundSyncStateMessage.encode(isRunning: false),
      );
      await _refreshNotification();
    }
  }
}
