import 'package:file_vault_bb/services/service_backend.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../utils/common.dart';
import '../../ui/common_widgets.dart';
import '../../services/service_logger.dart';

class PageDevices extends StatefulWidget {
  final bool onStack;
  const PageDevices({
    super.key,
    required this.onStack,
  });

  @override
  State<PageDevices> createState() => _PageDevicesState();
}

class _PageDevicesState extends State<PageDevices> {
  AppLogger logger = AppLogger(prefixes: ["Devices"]);
  List<Map<String, dynamic>> devices = [];
  bool processing = true;
  String? _errorMessage;
  final api = BackendApi();

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> fetchDevices() async {
    _errorMessage = null;
    setState(() {
      processing = true;
    });
    try {
      final response = await api.get(endpoint: '/devices');
      final status = response["success"];
      if (status <= 0) {
        _errorMessage = response["message"].toString();
      } else if (status == 1) {
        if (mounted) {
          setState(() {
            devices = List<Map<String, dynamic>>.from(response["data"]);
            processing = false;
          });
        }
      }
    } catch (e, s) {
      logger.error("fetching Devices", error: e, stackTrace: s);
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> signoutDevice(String deviceUuid) async {
    setState(() {
      processing = true;
    });
    try {
      final response = await api.delete(
          endpoint: '/devices', queryParameters: {'device_uuid': deviceUuid});
      final status = response["success"];
      if (status <= 0) {
        logger.error("Error signing out",
            error: response["message"].toString());
        if (mounted) {
          displaySnackBar(context, message: 'Please try again!', seconds: 2);
        }
      } else if (status == 1) {
        fetchDevices();
      }
    } catch (e) {
      if (mounted) {
        displaySnackBar(context, message: 'Please try again!', seconds: 2);
      }
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> showLogoutDialog(String deviceUuid) async {
    String thisDeviceUuid = await getDeviceUuid();
    if (thisDeviceUuid.isNotEmpty && deviceUuid == thisDeviceUuid && mounted) {
      displaySnackBar(context, message: "Not this device!", seconds: 2);
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm signout device"),
        content: Text("Are you sure?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Cancel
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              signoutDevice(deviceUuid);
            },
            child: Text("OK", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateBack() async {
    if (widget.onStack) {
      Navigator.pop(context);
    } else {
      context.read<AppSetupState>().recheckStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
          body: Column(
        children: [
          Expanded(
            child: processing
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? tryFailedRequestAgain(
                        message: _errorMessage!,
                        style: Theme.of(context).textTheme.bodyLarge,
                        onPressed: fetchDevices)
                    : devices.isEmpty
                        ? Center(child: Text("No device found"))
                        : ListView.builder(
                            reverse: true,
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              final bool isEnabled = device["active"] == 1;
                              String lastAt =
                                  getFormattedDateTime(device["lastAt"]);
                              return ListTile(
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color:
                                        isEnabled ? Colors.green : Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                title:
                                    Text(device["title"], style: TextStyle()),
                                subtitle: Text(
                                  lastAt,
                                  style: TextStyle(fontSize: 12),
                                ),
                                trailing: isEnabled
                                    ? // Show disable button only if enabled
                                    IconButton(
                                        icon: Icon(LucideIcons.logOut,
                                            color: Colors.red),
                                        onPressed: () =>
                                            showLogoutDialog(device["id"]),
                                      )
                                    : null,
                              );
                            },
                          ),
          ),
          buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: _navigateBack),
              title: Text("Devices"),
              actions: [])
        ],
      )),
    );
  }
}
