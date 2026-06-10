import 'dart:math';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_add_storage.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../models/model_profile.dart';
import '../../services/service_backend.dart';
import '../../services/service_logger.dart';
import '../../utils/enums.dart';

class StorageProvidersScreen extends StatefulWidget {
  const StorageProvidersScreen({super.key});

  @override
  State<StorageProvidersScreen> createState() => _StorageProvidersScreenState();
}

class _StorageProvidersScreenState extends State<StorageProvidersScreen> {
  AppLogger logger = AppLogger(prefixes: ["Storage"]);
  List<Map<String, dynamic>> storages = [];
  bool processing = true;
  bool _isActive = false;
  String? _errorMessage;
  static const String entitlementId = 'pro';
  final api = BackendApi();

  @override
  void initState() {
    super.initState();
    fetchStorage();
    if (revenueCatSupported) {
      _initializeData();
    } else {
      loadFromLocal();
    }
  }

  Future<void> loadFromLocal() async {
    ModelProfile? profile = await ModelProfile.get();
    if (profile != null) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (profile.planExpiresAt! > now) {
        if (mounted) {
          setState(() {
            _isActive = true;
          });
        }
      }
    }
  }

  Future<void> _initializeData() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      bool isActive =
          customerInfo.entitlements.all[entitlementId]?.isActive ?? false;
      if (mounted) {
        setState(() {
          _isActive = isActive;
        });
      }
    } catch (e) {
      debugPrint("Error initializing purchases: $e");
    }
  }

  Future<void> fetchStorage() async {
    _errorMessage = null;
    if (!mounted) return;
    setState(() {
      processing = true;
    });
    try {
      final response = await api.get(endpoint: '/storages');
      final status = response["success"];
      if (status <= 0) {
        _errorMessage = response["message"].toString();
      } else if (status == 1) {
        if (mounted) {
          setState(() {
            storages = List<Map<String, dynamic>>.from(response["data"])
                .reversed
                .toList();
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

  Future<void> openHowToConnect() async {
    final url = '${AppEnv.apiBaseUrl}/connect';
    openURL(url);
  }

  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  Future<void> connectStorageProvider(StorageProvider storageProvider) async {
    Navigator.of(context)
        .push(
      AnimatedPageRoute(
        child: AddProviderScreen(
          storageProvider: storageProvider,
        ),
      ),
    )
        .then((value) {
      fetchStorage();
    });
  }

  Future<void> modifyStorage(int providerId, int sizeGb) async {
    setState(() {
      processing = true;
    });
    int sizeBytes = sizeGb * 1024 * 1024 * 1024;
    try {
      final response = await api.post(
        endpoint: '/storages/modify',
        jsonBody: {'provider_id': providerId, 'bytes': sizeBytes},
      );
      final status = response["success"];
      if (status == 1) {
        fetchStorage();
        if (mounted) {
          setState(() {
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

  void _checkAndModify(BuildContext context, int providerId) async {
    if (!_isActive) {
      displaySnackBar(
        context,
        message: AppLocalizations.of(context)!
            .requiresAppPro(AppString.appName.string),
        seconds: 2,
      );
      return;
    }
    final int? newSize = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _SizeInputDialog(),
    );

    if (newSize != null && newSize > 1 && mounted) {
      modifyStorage(providerId, newSize);
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
                          onPressed: fetchStorage,
                        )
                      : storages.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.noStorageFound,
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 24.0,
                              ),
                              itemCount: storages.length,
                              itemBuilder: (context, index) {
                                final provider = storages[index];
                                return _buildProviderCard(context, provider);
                              },
                            ),
            ),
            FilledButton.tonalIcon(
              onPressed: openHowToConnect,
              icon: const Icon(LucideIcons.arrowRight, size: 18),
              label: Text(
                AppLocalizations.of(context)!.howToConnect,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              iconAlignment: IconAlignment.end,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: _navigateBack,
              ),
              title: Text(AppLocalizations.of(context)!.storage),
              actions: [],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    Map<String, dynamic> provider,
  ) {
    final int providerId = provider['id'];
    final bool isAdded = provider['added'] == 1;
    final int totalBytes = provider['bytes'] ?? 0;
    final int usedBytes = provider['used'] ?? 0;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildProviderIcon(provider['id'], theme),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    provider['title'],
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isAdded && providerId > 1)
                  OutlinedButton.icon(
                    onPressed: () {
                      _checkAndModify(context, providerId);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(AppLocalizations.of(context)!.modify),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isAdded)
              _buildUsageIndicator(context, usedBytes, totalBytes)
            else
              _buildUnaddedState(context, providerId, totalBytes),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageIndicator(BuildContext context, int used, int total) {
    final theme = Theme.of(context);
    final double usagePercent =
        total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;

    final Color progressColor = usagePercent > 0.9
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context)!.storageUsed(
                _formatBytes(used, 1),
                _formatBytes(total, 0),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              AppLocalizations.of(context)!
                  .percentageLabel((usagePercent * 100).toStringAsFixed(1)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: usagePercent,
          minHeight: 6,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: progressColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ],
    );
  }

  Widget _buildUnaddedState(
    BuildContext context,
    int providerId,
    int totalBytes,
  ) {
    final theme = Theme.of(context);
    StorageProvider storageProvider =
        StorageProviderExtension.fromValue(providerId);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.upToFree(
                _formatBytes(totalBytes, 0),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context)!.notConnected,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () {
            connectStorageProvider(storageProvider);
          },
          icon: const Icon(Icons.add_link, size: 18),
          label: Text(AppLocalizations.of(context)!.connect),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderIcon(int id, ThemeData theme) {
    Widget iconData;
    switch (id) {
      case 1:
        iconData = Image.asset(
          'assets/logo.png',
          width: 30,
          height: 30,
          color: theme.colorScheme.primary,
        );
        break;
      case 2:
        iconData = Icon(
          LucideIcons.package,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        );
        break;
      case 3:
        iconData = Icon(
          LucideIcons.cloudLightning,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        );
        break;
      case 4:
        iconData = Icon(
          LucideIcons.tableProperties,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        );
        break;
      case 5:
        iconData = Icon(
          LucideIcons.hardDrive,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        );
        break;
      default:
        iconData = Icon(
          LucideIcons.hardDrive,
          color: theme.colorScheme.onSecondaryContainer,
          size: 24,
        );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
      ),
      child: iconData,
    );
  }
}

class _SizeInputDialog extends StatefulWidget {
  const _SizeInputDialog();

  @override
  State<_SizeInputDialog> createState() => _SizeInputDialogState();
}

class _SizeInputDialogState extends State<_SizeInputDialog> {
  late final TextEditingController _sizeController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _sizeController = TextEditingController();
  }

  @override
  void dispose() {
    _sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.modifyStorageCapacityTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.enterNewStorageLimitForProvider,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sizeController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: InputDecoration(
                prefixText: AppLocalizations.of(context)!.sizePrefix,
                suffixText: AppLocalizations.of(context)!.gbSuffix,
                border: const OutlineInputBorder(),
                filled: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return AppLocalizations.of(context)!.pleaseEnterSize;
                }
                if (int.tryParse(value) == null || int.parse(value) <= 1) {
                  return AppLocalizations.of(context)!
                      .enterValidNumberGreaterThanOne;
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(AppLocalizations.of(context)!.submit),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final size = int.parse(_sizeController.text);
      Navigator.of(context).pop(size);
    }
  }
}
