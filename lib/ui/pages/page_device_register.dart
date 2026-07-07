import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/model_item.dart';
import '../../models/model_setting.dart';
import '../../services/service_backend.dart';
import '../../services/service_logger.dart';
import '../../utils/common.dart';
import '../common_widgets.dart';

class PageRegisterDevice extends StatefulWidget {
  const PageRegisterDevice({
    super.key,
  });

  @override
  State<PageRegisterDevice> createState() => _PageRegisterDeviceState();
}

class _PageRegisterDeviceState extends State<PageRegisterDevice> {
  final logger = AppLogger(prefixes: ["RegisterDevice"]);
  bool _isLoading = true;
  String? _errorMessage;
  final api = BackendApi();
  SecureStorage storage = SecureStorage();

  @override
  void initState() {
    super.initState();
    _registerDevice();
  }

  Future<void> _registerDevice() async {
    logger.info("Registering..");
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    Uuid uuid = Uuid();
    String deviceUuid = uuid.v4();
    String deviceName = await getDeviceName();
    int deviceType = await getDeviceType();
    bool deviceRegistered = false;
    if (!simulateTesting()) {
      String? fcmToken = await storage.read(key: AppString.fcmId.string);
      final result = await api.post(endpoint: '/devices', jsonBody: {
        "device_uuid": deviceUuid,
        "title": deviceName,
        "type": deviceType,
        "notificationId": fcmToken,
      });
      final status = result["success"];
      if (status <= 0) {
        _errorMessage = result["message"].toString();
        deviceRegistered = false;
        if (_errorMessage == "7" && mounted) {
          displaySnackBar(
            context,
            message: AppLocalizations.of(context)!.deviceLimitReached,
            seconds: 2,
          );
          await context.read<AppSetupState>().manageDevices();
        }
      } else {
        deviceRegistered = true;
      }
    } else {
      deviceRegistered = true;
    }

    if (deviceRegistered) {
      await ModelSetting.set(AppString.deviceUuid.string, deviceUuid);
      String deviceRoot = await getDeviceHash();
      ModelItem deviceItem = await ModelItem.fromMap({
        "id": deviceRoot,
        "name": deviceName,
        "is_folder": 1,
        "parent_id": "fife",
      });
      await deviceItem.insert();
      if (mounted) {
        await context.read<AppSetupState>().recheckStatus();
      }
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _errorMessage != null
              ? tryFailedRequestAgain(
                  context: context,
                  message: _errorMessage!,
                  onPressed: _registerDevice,
                )
              : const SizedBox.shrink(),
    );
  }
}
