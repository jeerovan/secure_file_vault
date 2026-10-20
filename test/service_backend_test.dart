import 'dart:convert';

import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unauthorized request refreshes once and retries with new token',
      () async {
    var token = 'expired';
    var requests = 0;
    var refreshes = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) {
        expect(request.headers['authorization'], 'Bearer expired');
        return http.Response(jsonEncode({'success': 0, 'message': '14'}), 200);
      }
      expect(request.headers['authorization'], 'Bearer fresh');
      return http.Response(jsonEncode({'success': 1, 'data': 'ok'}), 200);
    });
    final api = BackendApi(
      httpClient: client,
      baseUrlOverride: 'https://example.test/api',
      accessTokenProvider: () async => token,
      signedEmailIdProvider: () async => 'signed-in@example.test',
      deviceUuidProvider: () async => 'device',
      refreshAuth: () async {
        refreshes++;
        token = 'fresh';
      },
    );

    final response = await api.get(endpoint: '/sync');

    expect(response['success'], 1);
    expect(requests, 2);
    expect(refreshes, 1);
  });

  test('non-idempotent post is not automatically retried', () async {
    var requests = 0;
    var refreshes = 0;
    final api = BackendApi(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'success': 0, 'message': '14'}), 200);
      }),
      baseUrlOverride: 'https://example.test/api',
      accessTokenProvider: () async => 'token',
      signedEmailIdProvider: () async => 'signed-in@example.test',
      deviceUuidProvider: () async => 'device',
      refreshAuth: () async => refreshes++,
    );

    final response = await api.post(endpoint: '/sync', jsonBody: const {});

    expect(response['success'], 0);
    expect(requests, 1);
    expect(refreshes, 0);
  });

  test('idempotent request is not retried when refresh produced no token',
      () async {
    var requests = 0;
    var refreshes = 0;
    final api = BackendApi(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 401);
      }),
      baseUrlOverride: 'https://example.test/api',
      accessTokenProvider: () async => 'unchanged',
      signedEmailIdProvider: () async => 'signed-in@example.test',
      deviceUuidProvider: () async => 'device',
      refreshAuth: () async => refreshes++,
    );

    final response = await api.get(endpoint: '/sync');

    expect(response['success'], 0);
    expect(requests, 1);
    expect(refreshes, 1);
  });

  test(
      'session proof stays scoped to authenticated HTTPS vault bootstrap requests',
      () async {
    final fixture = await SyncFixture.create();
    addTearDown(fixture.dispose);
    fixture.secrets[AppString.sessionCookie.string] = 'fixture-cookie';
    await ModelSetting.set(
        AppString.vaultGeneration.string, 'fixture-generation');
    final seen = <http.Request>[];
    BackendApi api(String base, {String? email = 'fixture@example.test'}) =>
        BackendApi(
          httpClient: MockClient((request) async {
            seen.add(request);
            return http.Response(jsonEncode({'success': 1}), 200);
          }),
          baseUrlOverride: base,
          accessTokenProvider: () async => 'fixture-token',
          signedEmailIdProvider: () async => email,
          deviceUuidProvider: () async => 'fixture-device',
        );
    final https = api('https://api.example.test/api');
    for (final endpoint in [
      '/keys',
      '/devices',
      '/recovery-reset/status',
      '/recovery-reset/prepare',
      '/recovery-reset/confirm'
    ]) {
      await https.get(endpoint: endpoint);
      expect(seen.last.headers['x-fife-session'], 'fixture-cookie');
      expect(seen.last.headers['x-fife-vault-protocol'], '1');
      expect(
          seen.last.headers['x-fife-vault-generation'], 'fixture-generation');
    }
    for (final endpoint in [
      '/sync',
      '/storages',
      '/b2/get-upload-url',
      '/recovery-reset-unrelated'
    ]) {
      await https.get(endpoint: endpoint);
      expect(seen.last.headers.containsKey('x-fife-session'), isFalse);
    }
    await api('https://api.example.test/api', email: null)
        .get(endpoint: '/keys');
    expect(seen.last.headers.containsKey('x-fife-session'), isFalse);
    expect(seen.last.headers.containsKey('authorization'), isFalse);
    await api('http://api.example.test/api').get(endpoint: '/keys');
    expect(seen.last.headers.containsKey('x-fife-session'), isFalse);
  });
}
