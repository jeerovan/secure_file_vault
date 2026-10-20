import 'dart:async';
import 'dart:ui';

import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/app_localizations.dart';
import 'service_events.dart';
import 'service_session_cleanup.dart';

class ServiceForeground {
  ServiceForeground._();
  static final ServiceForeground instance = ServiceForeground._();
  AppLogger logger = AppLogger(prefixes: ["Foreground Service"]);
  bool _taskDataCallbackRegistered = false;
  StreamSubscription<AppEvent>? _appEventSubscription;

  void init() {
    FlutterForegroundTask.initCommunicationPort();
    if (!_taskDataCallbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _taskDataCallbackRegistered = true;
    }
    _appEventSubscription ??= EventStream().events.listen((event) {
      if (isSyncActivityEvent(event)) unawaited(_notifySyncActivity());
    });
    _configure(ModelSetting.foregroundSyncIntervalMinutes);
  }

  Future<void> _notifySyncActivity() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask(
            foregroundSyncActivityChangedMessage);
      }
    } catch (error, stackTrace) {
      logger.error('Failed to forward sync activity',
          error: error, stackTrace: stackTrace);
    }
  }

  ForegroundTaskOptions _taskOptions(int minutes) => ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
            Duration(minutes: minutes).inMilliseconds),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      );

  void _configure(int minutes) {
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
      foregroundTaskOptions: _taskOptions(minutes),
    );
  }

  Future<bool> updateSyncInterval() async {
    // Read SQLite because the service and app keep separate settings caches.
    final minutes = await ModelSetting.getForegroundSyncIntervalMinutes();
    _configure(minutes);
    if (!await FlutterForegroundTask.isRunningService) return true;

    final result = await FlutterForegroundTask.updateService(
      foregroundTaskOptions: _taskOptions(minutes),
      notificationButtons: [],
    );
    if (result is ServiceRequestFailure) {
      logger.error('Failed to update auto sync interval', error: result.error);
      return false;
    }
    // The task isolate owns the subtitle so an interval change preserves progress.
    FlutterForegroundTask.sendDataToTask(foregroundSyncIntervalChangedMessage);
    return true;
  }

  void _onTaskData(Object data) {
    if (data == sessionStateChangedMessage) {
      unawaited(SessionCleanup.instance.observeExternalState());
      return;
    }
    final isRunning = ForegroundSyncStateMessage.decode(data);
    if (isRunning == null) return;
    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'foregroundSync',
      key: isRunning ? EventKey.running : EventKey.stopped,
    ));
  }

  Future<void> start() async {
    await updateSyncInterval();
    if (await FlutterForegroundTask.isRunningService) {
      return;
    } else {
      logger.info("Starting");
      try {
        final String appLocale = await getAppLocale();
        final Locale locale = Locale(appLocale);
        final AppLocalizations localizations = lookupAppLocalizations(locale);
        final minutes = await ModelSetting.getForegroundSyncIntervalMinutes();

        final ServiceRequestResult result =
            await FlutterForegroundTask.startService(
                serviceTypes: [ForegroundServiceTypes.dataSync],
                serviceId: 300,
                notificationTitle: localizations.quickSyncNotificationTitle,
                notificationText:
                    localizations.quickSyncNotificationText(minutes),
                callback: startForegroundTask,
                notificationButtons: []);

        if (result is ServiceRequestFailure) {
          logger.error("Failed to start", error: result.error);
        } else {
          logger.info("Started");
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
