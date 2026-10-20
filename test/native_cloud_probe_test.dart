import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../integration_test/support/observed_transfers.dart';

void main() {
  final url = Uri.parse('https://bucket.example.test/generated-part');

  test('a cloud verification probe retries a connection reset', () async {
    var connections = 0;
    final status = await probeCloudStatus(url,
        clientFactory: () => MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.headers['Range'], 'bytes=0-0');
              expect(request.headers.containsKey('Authorization'), isFalse);
              if (++connections == 1) {
                throw http.ClientException('Connection closed before headers');
              }
              return http.Response('', 206);
            }));
    expect(status, 206);
    expect(connections, 2);
  });

  for (final code in [404, 503]) {
    test('a cloud probe returns HTTP $code without retrying it away', () async {
      var connections = 0;
      expect(
          await probeCloudStatus(url, clientFactory: () {
            connections++;
            return MockClient((_) async => http.Response('', code));
          }),
          code);
      expect(connections, 1);
    });
  }

  test('persistent transport failure is bounded and remains a failure',
      () async {
    var connections = 0;
    await expectLater(
        probeCloudStatus(url, clientFactory: () {
          connections++;
          return MockClient(
              (_) async => throw const SocketException('offline'));
        }),
        throwsA(isA<SocketException>()));
    expect(connections, 3);
  });
}
