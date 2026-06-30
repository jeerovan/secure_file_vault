import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
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
      alert: false, // No notifications
      badge: false, // No badges
      sound: false, // No sounds
      provisional: true, // Silent permission on iOS
    ); // Minimal permission request for background messages
    logger.info("FCM Permission status: ${settings.authorizationStatus}");

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'Sync') {
        SyncUtils().reconFolders();
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
    SecureStorage storage = SecureStorage();
    String? oldToken = await storage.read(key: AppString.fcmId.string);
    bool updateToken = false;
    if (oldToken == null) {
      updateToken = true;
    } else if (oldToken != token) {
      updateToken = true;
    }
    if (updateToken) {
      await storage.write(key: AppString.fcmId.string, value: token);
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
