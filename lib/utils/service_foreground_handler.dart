import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/service_logger.dart';
import '../services/service_events.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../utils/utils_sync.dart';

class ForegroundTaskHandler extends TaskHandler {
  AppLogger logger = AppLogger(prefixes: ["Forground Handler"]);
  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    // Initialize database in this isolate
    await StorageSqlite.initialize(ExecutionMode.foregroundService);
    await initializeDependencies(ExecutionMode.foregroundService);
    logger.info(
      "OnStart: $starter",
    );
  }

  // Called based on the eventAction set in ForegroundTaskOptions.
  @override
  void onRepeatEvent(DateTime timestamp) {
    logger.info('onRepeatEvent(timestamp: $timestamp)');
  }

  // Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    logger.info('onDestroy(isTimeout: $isTimeout)');
  }

  // Called when data is sent using `FlutterForegroundTask.sendDataToTask`.
  @override
  void onReceiveData(Object data) {
    logger.info('Foreground service data received');
  }

  // Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    logger.info('Foreground notification button pressed');
    startSyncTask();
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

  Future<void> startSyncTask() async {
    logger.info("Starting Sync Task");
    AppLocalizations? localizations;
    try {
      final String appLocale = await getAppLocale();
      final Locale locale = Locale(appLocale);
      localizations = lookupAppLocalizations(locale);
      FlutterForegroundTask.sendDataToMain(
        ForegroundSyncStateMessage.encode(isRunning: true),
      );
      await FlutterForegroundTask.updateService(
          notificationButtons: [],
          notificationText: localizations.quickSyncNotificationInProgress);
      await SyncUtils().reconFolders(caller: "ForegroundService");
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
    } finally {
      if (localizations != null) {
        await FlutterForegroundTask.updateService(
            notificationText: localizations.quickSyncNotificationText,
            notificationButtons: [
              NotificationButton(
                  id: 'sync', text: localizations.quickSyncNotificationButton)
            ]);
      }
      FlutterForegroundTask.sendDataToMain(
        ForegroundSyncStateMessage.encode(isRunning: false),
      );
    }
  }
}
