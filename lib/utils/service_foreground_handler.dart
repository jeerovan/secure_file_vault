import 'dart:ui';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/model_setting.dart';
import '../services/service_logger.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../utils/utils_sync.dart';

class ForegroundTaskHandler extends TaskHandler {
  AppLogger logger = AppLogger(prefixes: ["Forground Service"]);
  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
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
    logger.info('onReceiveData: $data');
  }

  // Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    logger.info('onNotificationButtonPressed: $id');
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
    try {
      final String appLocale =
          ModelSetting.get(AppString.locale.string, defaultValue: "en");
      final Locale locale = Locale(appLocale);
      final AppLocalizations localizations = lookupAppLocalizations(locale);
      FlutterForegroundTask.updateService(
          notificationButtons: [],
          notificationText: localizations.quickSyncNotificationInProgress);
      await StorageSqlite.initialize(mode: ExecutionMode.appBackground);
      await initializeDependencies(mode: ExecutionMode.appBackground);
      await SyncUtils().reconFolders(caller: "ForegroundService");
      FlutterForegroundTask.updateService(
          notificationText: localizations.quickSyncNotificationText,
          notificationButtons: [
            NotificationButton(
                id: 'sync', text: localizations.quickSyncNotificationButton)
          ]);
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
    }
  }
}
