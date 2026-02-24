import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/model_item.dart';
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
    // Reset state for retries
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    String deviceId = await getDeviceId();
    String deviceName = await getDeviceName();
    int deviceType = await getDeviceType();
    final result = await api.post(endpoint: '/user-device', jsonBody: {
      "deviceId": deviceId,
      "title": deviceName,
      "type": deviceType
    });
    final status = result["status"];
    if (status <= 0) {
      _errorMessage = result["error"];
    } else {
      ModelItem deviceItem = await ModelItem.fromMap({
        "id": deviceId,
        "name": deviceName,
        "is_folder": 1,
        "parent_id": "fife",
      });
      await deviceItem.insert();
      await storage.write(key: AppString.deviceId.string, value: deviceId);
      if (mounted) {
        await context.read<AppSetupState>().deviceRegistered();
      }
    }
    // Check mounted before updating state or calling callbacks
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // State 1: Loading
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator.adaptive(),
      );
    }

    // State 2: Error
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _registerDevice,
                icon: const Icon(Icons.refresh),
                label: const Text("Try Again"),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
