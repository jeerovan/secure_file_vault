import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../integration_test/support/native_http_overrides.dart';

void main() {
  for (final status in [200, 401]) {
    test('native transport preserves JSON/headers and HTTP $status', () async {
      final override = NativeFixtureHttpOverrides((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/keys');
        expect(request.headers['cookie'], 'fixture-cookie');
        expect(request.body, '{"value":"fixture ✓"}');
        return http.Response('{"success":1}', status,
            headers: {'set-auth-jwt': 'fixture-header'});
      });
      final client = IOClient(override.createHttpClient(null));
      try {
        final response = await client.post(
            Uri.https('backend.example.test', '/api/keys'),
            headers: {'Cookie': 'fixture-cookie'},
            body: '{"value":"fixture ✓"}');
        expect(response.statusCode, status);
        expect(response.body, '{"success":1}');
        expect(response.headers['set-auth-jwt'], 'fixture-header');
      } finally {
        client.close();
      }
    });
  }
  test('native transport never opens an unexpected host', () async {
    var calls = 0;
    final override = NativeFixtureHttpOverrides((_) async {
      calls++;
      return http.Response('', 200);
    });
    final client = IOClient(override.createHttpClient(null));
    try {
      await expectLater(
          client.get(Uri.https('unexpected.invalid')), throwsStateError);
      expect(calls, 0);
    } finally {
      client.close();
    }
  });
}
