import 'package:file_vault_bb/models/model_storage_providers.dart';
import 'package:file_vault_bb/services/service_storage_validation.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S3 provider has a stable ID, title, and API route', () {
    expect(StorageProvider.s3.value, 6);
    expect(StorageProviderExtension.fromValue(6), StorageProvider.s3);
    expect(StorageProviderExtension.stringFromInt(6), 'S3 Compatible');
    expect(StorageProvider.s3.apiPath, 's3');
    expect(StorageProvider.s3.usesPresignedS3Url, isTrue);
  });

  test('S3 provider configuration includes path-style addressing by default',
      () {
    final config = providerConfigurations[StorageProvider.s3]!;
    expect(config.title, 'S3 Compatible');
    expect(
      config.fields.map((field) => field.key),
      containsAll(<String>[
        'endpoint',
        'region',
        'bucket',
        'app_id',
        'app_key',
        'force_path_style',
      ]),
    );
    final addressing =
        config.fields.singleWhere((field) => field.key == 'force_path_style');
    expect(addressing.type, StorageProviderFieldType.toggle);
    expect(addressing.defaultBool, isTrue);
  });

  test('builds path-style and virtual-hosted S3 bucket URIs', () {
    expect(
      buildS3BucketUri(
        endpoint: 'https://objects.example.com/api/',
        bucket: 'vault',
        forcePathStyle: true,
      ).toString(),
      'https://objects.example.com/api/vault',
    );
    expect(
      buildS3BucketUri(
        endpoint: 'https://objects.example.com',
        bucket: 'vault',
        forcePathStyle: false,
      ).toString(),
      'https://vault.objects.example.com',
    );
  });

  test('accepts public S3 hostnames containing exactly four labels', () {
    expect(
      normalizePublicS3Endpoint('https://s3.eu-central-2.idrivee2.com'),
      'https://s3.eu-central-2.idrivee2.com',
    );
  });

  test('rejects non-public S3 endpoints', () {
    for (final endpoint in <String>[
      'http://objects.example.com',
      'https://localhost:9000',
      'https://10.0.0.1',
      'https://[::ffff:127.0.0.1]',
      'https://user:secret@objects.example.com',
    ]) {
      expect(() => normalizePublicS3Endpoint(endpoint), throwsFormatException);
    }
  });

  test('reserved address ranges, URL credentials and parameters are rejected',
      () {
    for (final host in [
      '0.0.0.0',
      '100.64.0.1',
      '100.127.255.254',
      '169.254.1.1',
      '172.16.0.1',
      '172.31.255.254',
      '198.18.0.1',
      '198.19.255.254',
      '224.0.0.1',
      '255.255.255.255',
      '[::]',
      '[::1]',
      '[fc00::1]',
      '[fd00::1]',
      '[fe80::1]',
      '[febf::1]',
      'vault.localhost',
    ]) {
      expect(() => normalizePublicS3Endpoint('https://$host'),
          throwsFormatException,
          reason: host);
    }
    for (final endpoint in [
      'https://objects.example.com?token=x',
      'https://objects.example.com/#fragment',
      'https://id:key@objects.example.com'
    ]) {
      expect(() => normalizePublicS3Endpoint(endpoint), throwsFormatException);
    }
    expect(normalizePublicS3Endpoint('https://8.8.8.8'), 'https://8.8.8.8');
  });
}
