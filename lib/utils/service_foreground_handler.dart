import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/task_handler.dart';

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
      FlutterForegroundTask.updateService(
          notificationButtons: [], notificationText: "In Progress...");
      await StorageSqlite.initialize(mode: ExecutionMode.appBackground);
      await initializeDependencies(mode: ExecutionMode.appBackground);
      await SyncUtils().reconFolders(caller: "ForegroundService");
      FlutterForegroundTask.updateService(
          notificationText: 'Tap the button below to sync',
          notificationButtons: [
            const NotificationButton(id: 'sync', text: 'Sync Now')
          ]);
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
    }
  }
}
