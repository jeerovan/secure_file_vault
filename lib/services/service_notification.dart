import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_vault_bb/services/service_logger.dart';

class ServiceNotification {
  ServiceNotification._();
  static final ServiceNotification instance = ServiceNotification._();
  static final AppLogger logger =
      AppLogger(prefixes: ["Firebase Notification Service"]);

  /// Initialize Firebase Messaging and Local Notifications
  static Future<void> initialize() async {
    logger.info("Initializing Notification Service...");

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: false,
      badge: false,
      sound: false,
      provisional: true, // Silent permission on iOS
    ); // Minimal permission request for background messages
    logger.info("FCM Permission status: ${settings.authorizationStatus}");

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      logger.info("Received on foreground: ${message.data.toString()}");
      if (message.data['type'] == 'Sync') {
        SyncUtils().reconFolders(caller: "FCM");
      }
    });

    // Get FCM token
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await _saveFcmToken(token);
      }
    } catch (e) {
      logger.error("FCM Fetch Failed", error: e);
    }

    // Listen for token refreshes
    messaging.onTokenRefresh.listen(_saveFcmToken);
  }

  static Future<void> _saveFcmToken(String token) async {
    logger.info("Received FCM Token:$token");
    String oldToken = await ModelSetting.getRaw(AppString.fcmId.string);
    bool updateToken = false;
    if (oldToken.isEmpty) {
      updateToken = true;
    } else if (oldToken != token && token.isNotEmpty) {
      updateToken = true;
    }
    if (updateToken) {
      await ModelSetting.set(AppString.fcmId.string, token);
      String deviceUuid = await getDeviceUuid();
      if (!simulateTesting() && deviceUuid.isNotEmpty) {
        final api = BackendApi();
        String deviceName = await getDeviceName();
        int deviceType = await getDeviceType();
        try {
          final result = await api.post(endpoint: '/devices', jsonBody: {
            "device_uuid": deviceUuid,
            "title": deviceName,
            "type": deviceType,
            "notificationId": token,
          });
          final status = result["success"];
          if (status <= 0) {
            String errorMessage = result["message"].toString();
            logger.error("Update FCM to Server", error: errorMessage);
          }
        } catch (e, s) {
          logger.error("Update FCM to Server", error: e, stackTrace: s);
        }
      }
    }
  }
}
