import 'dart:convert';

import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
}
