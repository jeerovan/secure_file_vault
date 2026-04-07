import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/model_storage_providers.dart';
import '../../services/service_storage_validation.dart';
import '../../utils/enums.dart';
import '../common_widgets.dart';

class AddProviderScreen extends StatefulWidget {
  final StorageProvider storageProvider;

  const AddProviderScreen({super.key, required this.storageProvider});

  @override
  State<AddProviderScreen> createState() => _AddProviderScreenState();
}

class _AddProviderScreenState extends State<AddProviderScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _formData = {};
  bool _isLoading = false;
  String? _errorMessage;

  late final StorageProviderConfig config;

  @override
  void initState() {
    super.initState();
    config = providerConfigurations[widget.storageProvider]!;
  }

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool isValid = false;

    try {
      if (widget.storageProvider == StorageProvider.backblaze) {
        isValid = await StorageValidationService.validateBackblaze(
          _formData['app_id']!,
          _formData['app_key']!,
        );
      } else if (widget.storageProvider == StorageProvider.oracle) {
        final namespace = _formData['namespace']!;
        final region = _formData['region']!;
        isValid = await StorageValidationService.validateS3(
          accessKey: _formData['app_id']!,
          secretKey: _formData['app_key']!,
          region: region,
          endpoint:
              'https://$namespace.compat.objectstorage.$region.oraclecloud.com',
          bucket: _formData['bucket']!,
        );
      }

      if (isValid) {
        // TODO: Send _formData to your backend Node.js/Svelte endpoint to finalize
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _errorMessage =
            'Validation failed. Check credentials and permissions.');
      }
    } catch (e) {
      setState(
          () => _errorMessage = 'Network error occurred during validation.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateBack() async {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(24.0),
                    children: [
                      FilledButton(
                        onPressed: _isLoading ? null : _handleConnect,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54.0),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Verify & Connect',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 32),
                      ...config.fields.reversed.map((field) => Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: field.label,
                                helperText: field.helperText,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withAlpha(30),
                              ),
                              obscureText: field.isObscured,
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Required'
                                      : null,
                              onSaved: (value) =>
                                  _formData[field.key] = value!.trim(),
                            ),
                          )),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: theme.colorScheme.onErrorContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                      color:
                                          theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Text(
                        'Your keys are verified locally and encrypted before transmission.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your credentials',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            buildBottomAppBar(
                color: surfaceColor,
                leading: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: _navigateBack),
                title: Text('Connect ${config.title}'),
                actions: [])
          ],
        ),
      ),
    );
  }
}
