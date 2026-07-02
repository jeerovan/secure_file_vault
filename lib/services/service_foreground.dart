import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class ServiceForeground {
  ServiceForeground._();
  static final ServiceForeground instance = ServiceForeground._();
  AppLogger logger = AppLogger(prefixes: ["Foreground Service"]);
  void init() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'data_sync_channel',
        channelName: 'Data Sync',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> start() async {
    if (!await FlutterForegroundTask.isRunningService) {
      logger.info("Starting");
      final ServiceRequestResult result =
          await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        serviceId: 300,
        notificationTitle: 'File Sync Service',
        notificationText: 'Checks and uploads remaining files to cloud',
        callback: startForegroundTask,
      );

      if (result is ServiceRequestFailure) {
        logger.error("Failed to start", error: result.error);
      }
    }
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      logger.info("Stopping");
      final ServiceRequestResult result =
          await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) {
        logger.error("Failed to stop", error: result.error);
      }
    }
  }
}
