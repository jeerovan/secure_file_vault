import '../utils/enums.dart';

class StorageProviderField {
  final String key;
  final String label;
  final bool isObscured;
  final String? helperText;

  StorageProviderField({
    required this.key,
    required this.label,
    this.isObscured = false,
    this.helperText,
  });
}

class StorageProviderConfig {
  final StorageProvider type;
  final String title;
  final List<StorageProviderField> fields;

  StorageProviderConfig(
      {required this.type, required this.title, required this.fields});
}

// Global configuration map
final Map<StorageProvider, StorageProviderConfig> providerConfigurations = {
  StorageProvider.oracle: StorageProviderConfig(
    type: StorageProvider.oracle,
    title: 'Oracle Object Storage',
    fields: [
      StorageProviderField(
          key: 'namespace',
          label: 'Namespace',
          helperText: 'Tenancy Object Storage namespace'),
      StorageProviderField(
          key: 'region', label: 'Region', helperText: 'e.g., us-ashburn-1'),
      StorageProviderField(key: 'bucket', label: 'Bucket Name'),
      StorageProviderField(key: 'app_id', label: 'Access Key ID'),
      StorageProviderField(
          key: 'app_key', label: 'Secret Access Key', isObscured: true),
    ],
  ),
  StorageProvider.backblaze: StorageProviderConfig(
    type: StorageProvider.backblaze,
    title: 'Backblaze B2',
    fields: [
      StorageProviderField(key: 'app_id', label: 'Application Key ID'),
      StorageProviderField(
          key: 'app_key', label: 'Application Key', isObscured: true),
    ],
  ),
  StorageProvider.idrive: StorageProviderConfig(
    type: StorageProvider.idrive,
    title: 'IDrive E2',
    fields: [
      StorageProviderField(
          key: 'region', label: 'Region', helperText: 'e.g., us-ashburn-1'),
      StorageProviderField(key: 'bucket', label: 'Bucket Name'),
      StorageProviderField(key: 'app_id', label: 'Access Key ID'),
      StorageProviderField(
          key: 'app_key', label: 'Secret Access Key', isObscured: true),
    ],
  ),
  StorageProvider.cloudflare: StorageProviderConfig(
    type: StorageProvider.cloudflare,
    title: 'Cloudflare R2',
    fields: [
      StorageProviderField(
          key: 'accountId', label: 'AccountId', helperText: 'e.g., Account Id'),
      StorageProviderField(key: 'bucket', label: 'Bucket Name'),
      StorageProviderField(key: 'app_id', label: 'Access Key ID'),
      StorageProviderField(
          key: 'app_key', label: 'Secret Access Key', isObscured: true),
    ],
  ),
};
