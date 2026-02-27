import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/service_backend.dart';
import '../../services/service_logger.dart';
import '../common_widgets.dart';

class PageAccessKeyCheck extends StatefulWidget {
  const PageAccessKeyCheck({
    super.key,
  });

  @override
  State<PageAccessKeyCheck> createState() => _PageAccessKeyCheckState();
}

class _PageAccessKeyCheckState extends State<PageAccessKeyCheck> {
  final logger = AppLogger(prefixes: ["KeyCheck"]);
  bool _isLoading = true;
  String? _errorMessage;
  final api = BackendApi();
  SecureStorage storage = SecureStorage();

  @override
  void initState() {
    super.initState();
    _performCheck();
  }

  Future<void> _performCheck() async {
    logger.info("Checking..");
    // Reset state for retries
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await api.get(endpoint: '/keys');
    final status = response["status"];
    if (status == -1) {
      _errorMessage = response["error"];
    } else if (status == 1) {
      final data = response["data"];
      if (data.containsKey("cipher") && data.containsKey("nonce")) {
        await storage.write(
            key: AppString.keyCipher.string, value: data["cipher"]);
        await storage.write(
            key: AppString.keyNonce.string, value: data["nonce"]);
        if (mounted) {
          await context.read<AppSetupState>().decodeAccessKey();
        }
      }
    } else {
      if (mounted) {
        await context.read<AppSetupState>().generateAccessKey();
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
                onPressed: _performCheck,
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
