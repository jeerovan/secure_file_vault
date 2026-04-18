import 'dart:math';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_add_storage.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String? _errorMessage;
  final api = BackendApi();

  @override
  void initState() {
    super.initState();
    fetchStorage();
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

  void openHowToConnect() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      final accessToken = session.accessToken;
      final refreshToken = session.refreshToken;
      // Construct the URL to your SvelteKit endpoint
      final url = '${AppEnv.apiBaseUrl}/connect/session'
          '?access_token=$accessToken'
          '&refresh_token=$refreshToken';

      // Launch this URL in the browser or WebView
      openURL(url);
    }
  }

  // Helper to format bytes into readable strings (KB, MB, GB, etc.)
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
        .push(AnimatedPageRoute(
            child: AddProviderScreen(
      storageProvider: storageProvider,
    )))
        .then((value) {
      fetchStorage();
    });
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
                          onPressed: fetchStorage)
                      : storages.isEmpty
                          ? Center(child: Text("No device found"))
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 24.0),
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
              label: const Text(
                "How to connect",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              iconAlignment:
                  IconAlignment.end, // Natively places icon on the right
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12), // Sleek, modern corners
                ),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            buildBottomAppBar(
                color: surfaceColor,
                leading: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: _navigateBack),
                title: Text("Storage"),
                actions: []),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(
      BuildContext context, Map<String, dynamic> provider) {
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
      // Using InkWell for a subtle tap effect if the user interacts with added providers
      child: InkWell(
        onTap: isAdded
            ? () {
                // TODO: Navigate to provider details/files
              }
            : null,
        borderRadius: BorderRadius.circular(16),
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
                  if (isAdded)
                    Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 20,
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
      ),
    );
  }

  Widget _buildUsageIndicator(BuildContext context, int used, int total) {
    final theme = Theme.of(context);
    final double usagePercent =
        total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;

    // Change progress color to red/orange if storage is almost full (>90%)
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
              '${_formatBytes(used, 1)} / ${_formatBytes(total, 0)} Used',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(usagePercent * 100).toStringAsFixed(1)}%',
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
          borderRadius: BorderRadius.circular(8), // Modern rounded progress bar
        ),
      ],
    );
  }

  Widget _buildUnaddedState(
      BuildContext context, int providerId, int totalBytes) {
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
              'Up to ${_formatBytes(totalBytes, 0)} free',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Not connected',
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
          label: const Text('Connect'),
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

  // Helper to return a stylized icon based on provider ID
  Widget _buildProviderIcon(int id, ThemeData theme) {
    Widget iconData;
    switch (id) {
      case 1:
        iconData = Image.asset(
          'assets/logo.png', // Replace with your actual asset path
          width: 30,
          height: 30,
          color: theme.colorScheme.primary, // Applies the theme color tint
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
