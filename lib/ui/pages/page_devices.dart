import 'package:file_vault_bb/services/service_backend.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
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
      if (simulateTesting()) {
        String deviceId = await getDeviceUuid();
        String deviceName = await getDeviceName();
        devices = [
          {
            "id": deviceId,
            "lastAt": DateTime.now().toUtc().millisecondsSinceEpoch,
            "title": deviceName,
            "active": 1
          }
        ];
      } else {
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
      if (simulateTesting()) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          setState(() {
            devices = [];
          });
        }
      } else {
        final response = await api.delete(
          endpoint: '/devices',
          queryParameters: {'device_uuid': deviceUuid},
        );
        final status = response["success"];
        if (status <= 0) {
          logger.error(
            "Error signing out",
            error: response["message"].toString(),
          );
          if (mounted) {
            displaySnackBar(
              context,
              message:
                  AppLocalizations.of(context)!.pleaseTryAgainWithExclamation,
              seconds: 2,
            );
          }
        } else if (status == 1) {
          fetchDevices();
        }
      }
    } catch (e) {
      if (mounted) {
        displaySnackBar(
          context,
          message: AppLocalizations.of(context)!.pleaseTryAgainWithExclamation,
          seconds: 2,
        );
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
    if (thisDeviceUuid.isNotEmpty &&
        deviceUuid == thisDeviceUuid &&
        mounted &&
        !simulateTesting()) {
      displaySnackBar(
        context,
        message: AppLocalizations.of(context)!.notThisDevice,
        seconds: 2,
      );
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmSignoutDeviceTitle),
        content: Text(AppLocalizations.of(context)!.areYouSure),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              signoutDevice(deviceUuid);
            },
            child: Text(
              AppLocalizations.of(context)!.ok,
              style: const TextStyle(color: Colors.red),
            ),
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
                          context: context,
                          message: _errorMessage!,
                          onPressed: fetchDevices,
                        )
                      : devices.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.noDeviceFound,
                              ),
                            )
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
                                  title: Text(
                                    device["title"],
                                    style: const TextStyle(),
                                  ),
                                  subtitle: Text(
                                    lastAt,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: isEnabled
                                      ? IconButton(
                                          icon: const Icon(
                                            LucideIcons.logOut,
                                            color: Colors.red,
                                          ),
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
                tooltip: AppLocalizations.of(context)!.backTooltip,
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: _navigateBack,
              ),
              title: Text(AppLocalizations.of(context)!.devicesTitle),
              actions: [],
            )
          ],
        ),
      ),
    );
  }
}
