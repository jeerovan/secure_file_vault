import 'package:file_vault_bb/services/service_foreground.dart';
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
    try {
      await StorageSqlite.initialize(mode: ExecutionMode.appBackground);
      await initializeDependencies(mode: ExecutionMode.appBackground);
      await SyncUtils().reconFolders(
          inBackground: false, awaited: true, caller: "ForegroundService");
      ServiceForeground.instance.stop();
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
    }
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
}
