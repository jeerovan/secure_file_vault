// Explicit, read-only checks of actual client validation using host environment inputs.
// The launcher reads backend/.env; no credentials are compiled into an app build.
import 'dart:io';

import 'package:file_vault_bb/services/service_storage_validation.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProviderHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionTimeout = const Duration(seconds: 15);
}

void main() {
  final inputs = Platform.environment;
  final enabled = inputs['FIFE_RUN_PROVIDER_READ_CHECKS'] == '1';
  final providers = [
    (name: 'b2', fields: ['B2_KEY_ID', 'B2_APPLICATION_KEY']),
    (
      name: 'e2',
      fields: [
        'E2_REGION',
        'E2_BUCKET_NAME',
        'E2_ACCESS_KEY_ID',
        'E2_SECRET_ACCESS_KEY'
      ]
    ),
    (
      name: 'r2',
      fields: [
        'R2_ACCOUNT_ID',
        'R2_BUCKET_NAME',
        'R2_ACCESS_KEY_ID',
        'R2_SECRET_ACCESS_KEY'
      ]
    ),
    (
      name: 'oci',
      fields: [
        'OCI_NAMESPACE',
        'OCI_REGION',
        'OCI_BUCKET_NAME',
        'OCI_ACCESS_KEY_ID',
        'OCI_SECRET_ACCESS_KEY'
      ]
    ),
    (
      name: 's3',
      fields: [
        'S3_ENDPOINT',
        'S3_REGION',
        'S3_BUCKET_NAME',
        'S3_ACCESS_KEY_ID',
        'S3_SECRET_ACCESS_KEY'
      ]
    ),
  ];
  for (final provider in providers) {
    final missing = provider.fields
        .where((key) => inputs[key]?.trim().isNotEmpty != true)
        .toList();
    test('${provider.name} client accepts configured credentials', () async {
      final result = await HttpOverrides.runWithHttpOverrides(() async {
        if (provider.name == 'b2') {
          return StorageValidationService.validateBackblaze(
              inputs['B2_KEY_ID']!, inputs['B2_APPLICATION_KEY']!);
        }
        final prefix = provider.name.toUpperCase();
        final region =
            provider.name == 'r2' ? 'auto' : inputs['${prefix}_REGION']!;
        final endpoint = switch (provider.name) {
          'e2' => 'https://s3.$region.idrivee2.com',
          'r2' => 'https://${inputs['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com',
          'oci' =>
            'https://${inputs['OCI_NAMESPACE']}.compat.objectstorage.$region.oraclecloud.com',
          _ => inputs['S3_ENDPOINT']!,
        };
        return StorageValidationService.validateS3(
          accessKey: inputs['${prefix}_ACCESS_KEY_ID']!,
          secretKey: inputs['${prefix}_SECRET_ACCESS_KEY']!,
          region: region,
          endpoint: endpoint,
          bucket: inputs['${prefix}_BUCKET_NAME']!,
          forcePathStyle: provider.name == 'r2'
              ? false
              : provider.name == 's3'
                  ? inputs['S3_FORCE_PATH_STYLE'] != 'false'
                  : true,
        );
      }, _ProviderHttpOverrides())
          .timeout(const Duration(seconds: 45));
      expect(result == 'ok', isTrue,
          reason:
              'Client provider verification failed; response details withheld.');
    },
        skip: !enabled
            ? 'Explicit read-only provider checks are disabled'
            : missing.isNotEmpty
                ? 'Configure ${missing.join(', ')}'
                : false);
  }
}
