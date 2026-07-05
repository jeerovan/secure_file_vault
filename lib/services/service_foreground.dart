import 'dart:ui';

import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/app_localizations.dart';

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
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      logger.info("Starting");
      try {
        final String appLocale = await getAppLocale();
        final Locale locale = Locale(appLocale);
        final AppLocalizations localizations = lookupAppLocalizations(locale);

        final ServiceRequestResult result =
            await FlutterForegroundTask.startService(
                serviceTypes: [ForegroundServiceTypes.dataSync],
                serviceId: 300,
                notificationTitle: localizations.quickSyncNotificationTitle,
                notificationText: localizations.quickSyncNotificationText,
                callback: startForegroundTask,
                notificationButtons: [
                  NotificationButton(
                      id: 'sync',
                      text: localizations.quickSyncNotificationButton)
                ]);

        if (result is ServiceRequestFailure) {
          logger.error("Failed to start", error: result.error);
        }
      } catch (e) {
        logger.error("Exception starting foreground service", error: e);
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
