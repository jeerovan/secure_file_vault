import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class StoragePermissionPage extends StatefulWidget {
  const StoragePermissionPage({super.key});

  @override
  State<StoragePermissionPage> createState() => _StoragePermissionPageState();
}

class _StoragePermissionPageState extends State<StoragePermissionPage> {
  bool _isLoading = false;

  Future<void> _requestPermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Request appropriate permissions based on Android version
      PermissionStatus status;

      if (await _isAndroid13OrHigher()) {
        // Android 13+ uses granular media permissions
        status = await Permission.manageExternalStorage.request();
      } else {
        // Android 12 and below
        status = await Permission.storage.request();
      }

      if (status.isGranted) {
        // Permission granted - exit to main app
        if (mounted) {
          await context.read<AppSetupState>().hasStoragePermission();
        }
      } else if (status.isPermanentlyDenied) {
        // Show dialog to open settings
        _showSettingsDialog();
      } else {
        // Permission denied
        setState(() {
          _isLoading = false;
        });
        _showDeniedMessage();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _isAndroid13OrHigher() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt >= 33;
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Storage permission is required to manage files. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showDeniedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Storage permission is required to continue'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withAlpha(80),
              theme.colorScheme.secondaryContainer.withAlpha(50),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withAlpha(50),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: 48),

                // Title
                Text(
                  'Storage Access Required',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Description
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'To manage and organize your files effectively, this app needs permission to access your device storage.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Permission Button or Loading
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isLoading
                      ? Column(
                          key: const ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Verifying permission...',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : FilledButton(
                          key: const ValueKey('button'),
                          onPressed: _requestPermission,
                          style: FilledButton.styleFrom(
                            minimumSize: Size(size.width * 0.7, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded),
                              const SizedBox(width: 12),
                              Text(
                                'Grant Permission',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                const Spacer(),

                // Footer note
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'Your files remain private and secure',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(170),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
