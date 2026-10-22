import 'dart:convert';

import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? sessionProof;
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    sessionProof = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            secure,
            (call) async => call.method == 'read' &&
                    call.arguments['key'] == AppString.sessionCookie.string
                ? sessionProof
                : null);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secure, null));

  test('local authentication proof follows the production bootstrap routes',
      () async {
    sessionProof = 'fife-local.session-proof';
    final api = BackendApi(
      httpClient: MockClient((request) async {
        final bootstrap = [
          '/api/keys',
          '/api/devices',
          '/api/recovery-reset/status'
        ].contains(request.url.path);
        expect(request.headers['x-fife-session'],
            bootstrap ? 'fife-local.session-proof' : isNull);
        return http.Response('{"success":1}', 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api',
      deviceUuidProvider: () async => '',
      localTestingProvider: () => true,
      localTestTokenOverride: 'local-token',
    );
    addTearDown(api.close);
    for (final path in [
      '/keys',
      '/devices',
      '/recovery-reset/status',
      '/storages'
    ]) {
      expect((await api.get(endpoint: path))['success'], 1);
    }
  });

  test('real Neon session cookies are never sent to an HTTP backend', () async {
    sessionProof = 'neon-private-cookie';
    final api = BackendApi(
      httpClient: MockClient((request) async {
        expect(request.headers['x-fife-session'], isNull);
        return http.Response('{"success":1}', 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api',
      deviceUuidProvider: () async => '',
      localTestingProvider: () => false,
      signedEmailIdProvider: () async => 'production@example.test',
      accessTokenProvider: () async => 'neon-jwt',
    );
    addTearDown(api.close);
    expect((await api.get(endpoint: '/keys'))['success'], 1);
  });

  test('switching to local auth never forwards a leftover Neon cookie',
      () async {
    sessionProof = 'real-neon-private-cookie';
    final api = BackendApi(
      httpClient: MockClient((request) async {
        expect(request.headers['x-fife-session'], isNull);
        return http.Response('{"success":1}', 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api',
      deviceUuidProvider: () async => '',
      localTestingProvider: () => true,
      localTestTokenOverride: 'local-token',
    );
    addTearDown(api.close);
    expect((await api.get(endpoint: '/keys'))['success'], 1);
  });

  test('local API address is selected for each emulator platform', () {
    expect(
      AppEnv.resolveApiBaseUrl(
        localBuild: true,
        android: false,
        productionUrl: 'https://production.example',
      ),
      'http://localhost:5173',
    );
    expect(
      AppEnv.resolveApiBaseUrl(
        localBuild: true,
        android: true,
        productionUrl: 'https://production.example',
      ),
      'http://10.0.2.2:5173',
    );
    expect(
      AppEnv.resolveApiBaseUrl(
        localBuild: false,
        android: true,
        productionUrl: 'https://production.example',
      ),
      'https://production.example',
    );
  });

  test('local backend requests use fixed local auth without Neon refresh',
      () async {
    var refreshes = 0;
    final api = BackendApi(
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'http://localhost:5173/api/keys');
        expect(request.headers['service'], 'local-test');
        expect(request.headers['authorization'], 'Bearer local-token');
        return http.Response(jsonEncode({'success': 0, 'message': '1'}), 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api',
      deviceUuidProvider: () async => '',
      localTestingProvider: () => true,
      localTestTokenOverride: 'local-token',
      refreshAuth: () async => refreshes++,
    );

    final response = await api.get(endpoint: '/keys');

    expect(response['message'], '1');
    expect(refreshes, 0);
  });

  test('explicit local API override takes precedence on a physical device', () {
    expect(
      AppEnv.resolveApiBaseUrl(
        localBuild: true,
        android: true,
        productionUrl: 'https://production.example',
        localOverride: ' http://192.0.2.10:5173 ',
      ),
      'http://192.0.2.10:5173',
    );
    expect(
      AppEnv.resolveApiBaseUrl(
        localBuild: false,
        android: true,
        productionUrl: 'https://production.example',
        localOverride: 'http://192.0.2.10:5173',
      ),
      'https://production.example',
    );
  });

  for (final status in [401, 403]) {
    test('local auth rejection $status cannot fall back to Neon or retry',
        () async {
      var requests = 0;
      var refreshes = 0;
      final api = BackendApi(
        httpClient: MockClient((request) async {
          requests++;
          expect(request.headers['service'], 'local-test');
          expect(request.headers['authorization'], 'Bearer local-token');
          return http.Response(
              jsonEncode({'success': 0, 'message': '14'}), status);
        }),
        baseUrlOverride: 'http://localhost:5173/api',
        deviceUuidProvider: () async => '',
        localTestingProvider: () => true,
        localTestTokenOverride: 'local-token',
        refreshAuth: () async => refreshes++,
      );
      addTearDown(api.close);

      expect((await api.get(endpoint: '/keys'))['success'], 0);
      expect(requests, 1);
      expect(refreshes, 0);
    });
  }

  test('missing local token fails before sending any authenticated request',
      () async {
    var requests = 0;
    final api = BackendApi(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api',
      deviceUuidProvider: () async => '',
      localTestingProvider: () => true,
      localTestTokenOverride: '',
    );
    addTearDown(api.close);
    expect((await api.get(endpoint: '/keys'))['success'], -1);
    expect(requests, 0);
  });

  test('upload authorization retains local auth, device identity, and payload',
      () async {
    final api = BackendApi(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/s3/get-upload-url');
        expect(request.method, 'POST');
        expect(request.headers['service'], 'local-test');
        expect(request.headers['authorization'], 'Bearer local-token');
        expect(request.headers['device_uuid'], 'release-test-device');
        expect(
            jsonDecode(request.body), {'storage_id': 6, 'file_id': 'hash_1'});
        return http.Response(
            jsonEncode({'success': 1, 'data': 'signed-url'}), 200);
      }),
      baseUrlOverride: 'http://localhost:5173/api/',
      deviceUuidProvider: () async => 'release-test-device',
      localTestingProvider: () => true,
      localTestTokenOverride: 'local-token',
      refreshAuth: () async => fail('Local auth must not refresh Neon'),
    );
    addTearDown(api.close);
    final response = await api.post(
      endpoint: '/s3/get-upload-url',
      jsonBody: {'storage_id': 6, 'file_id': 'hash_1'},
      retryUnauthorized: true,
    );
    expect(response, {'success': 1, 'data': 'signed-url'});
  });
}
