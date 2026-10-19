import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_storage_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const capabilities = [
    'deleteFiles',
    'writeBuckets',
    'readBuckets',
    'readFiles',
    'shareFiles',
    'writeFiles',
    'listFiles',
  ];
  Map<String, dynamic> authorization({
    List<Map<String, String>> buckets = const [
      {'id': 'bucket-id', 'name': 'vault'}
    ],
    List<String> caps = capabilities,
    String? prefix,
  }) =>
      {
        'apiInfo': {
          'storageApi': {
            'allowed': {
              'buckets': buckets,
              'capabilities': caps,
              'namePrefix': prefix,
            }
          }
        }
      };

  Future<String> validateB2(http.Response response) => http.runWithClient(
      () => StorageValidationService.validateBackblaze('test-id', 'test-key'),
      () => MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.headers['authorization'],
                'Basic ${base64Encode(utf8.encode('test-id:test-key'))}');
            return response;
          }));

  test('Backblaze accepts one bucket with every required permission', () async {
    expect(await validateB2(http.Response(jsonEncode(authorization()), 200)),
        'ok');
  });
  for (final status in [401, 429, 503]) {
    test('Backblaze HTTP $status provides an actionable validation failure',
        () async {
      final message = await validateB2(
          http.Response('{"message":"provider unavailable"}', status));
      expect(message, isNot('ok'));
      expect(
          message,
          status == 401
              ? contains('Invalid Application')
              : 'provider unavailable');
    });
  }
  for (final invalid in [
    (data: <String, dynamic>{}, reason: 'Invalid response structure'),
    (data: authorization(buckets: []), reason: 'No buckets'),
    (
      data: authorization(buckets: [
        {'id': 'a', 'name': 'a'},
        {'id': 'b', 'name': 'b'}
      ]),
      reason: 'Multiple buckets'
    ),
    (
      data: authorization(buckets: [
        {'id': 'a'}
      ]),
      reason: 'Invalid bucket information'
    ),
    (data: authorization(prefix: 'restricted/'), reason: 'name prefix'),
  ]) {
    test('Backblaze rejects ${invalid.reason}', () async {
      expect(await validateB2(http.Response(jsonEncode(invalid.data), 200)),
          contains(invalid.reason));
    });
  }
  for (final missing in capabilities) {
    test('Backblaze identifies missing $missing permission', () async {
      final data =
          authorization(caps: capabilities.where((c) => c != missing).toList());
      expect(await validateB2(http.Response(jsonEncode(data), 200)),
          contains(missing));
    });
  }
  test(
      'Backblaze malformed provider error and network failure remain recoverable',
      () async {
    expect(
        await validateB2(http.Response('not json', 502)), contains('HTTP 502'));
    final message = await http.runWithClient(
        () => StorageValidationService.validateBackblaze('test-id', 'test-key'),
        () => MockClient((_) async => throw const SocketException('offline')));
    expect(message, contains('Network error'));
  });

  for (final style in [true, false]) {
    for (final result in [
      (status: 200, message: 'ok'),
      (status: 400, message: 'Bad request'),
      (status: 403, message: 'Access denied'),
      (status: 404, message: 'not found'),
      (status: 503, message: 'HTTP status 503'),
    ]) {
      test('S3 validation handles ${result.status} with path style $style',
          () async {
        final message = await http.runWithClient(
            () => StorageValidationService.validateS3(
                  accessKey: 'test-access',
                  secretKey: 'test-secret',
                  region: 'test-region',
                  endpoint: 'https://objects.example.test',
                  bucket: 'vault',
                  forcePathStyle: style,
                ),
            () => MockClient((request) async {
                  expect(request.method, 'HEAD');
                  expect(
                      request.url.host,
                      style
                          ? 'objects.example.test'
                          : 'vault.objects.example.test');
                  expect(request.url.path, style ? '/vault' : '');
                  expect(request.headers['authorization'],
                      startsWith('AWS4-HMAC-SHA256 '));
                  expect(request.headers['x-amz-date'], isNotEmpty);
                  return http.Response('', result.status);
                }));
        expect(message, contains(result.message));
      });
    }
  }
  test('invalid S3 endpoint never sends credentials to the endpoint', () async {
    var sends = 0;
    final message = await http.runWithClient(
        () => StorageValidationService.validateS3(
              accessKey: 'test-access',
              secretKey: 'test-secret',
              region: 'test',
              endpoint: 'http://127.0.0.1',
              bucket: 'vault',
            ),
        () => MockClient((_) async {
              sends++;
              return http.Response('', 200);
            }));
    expect(message, contains('invalid endpoint'));
    expect(sends, 0);
  });
}
