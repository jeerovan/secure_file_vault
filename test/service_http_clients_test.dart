import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    AppHttpClients.closeAll();
    SessionWork.resetForTesting();
  });

  test('clients are reused until application shutdown', () {
    final backend = AppHttpClients.backend;
    final auth = AppHttpClients.auth;
    final transfer = AppHttpClients.transfer;

    expect(AppHttpClients.backend, same(backend));
    expect(AppHttpClients.auth, same(auth));
    expect(AppHttpClients.transfer, same(transfer));

    AppHttpClients.closeAll();

    expect(AppHttpClients.backend, isNot(same(backend)));
    expect(AppHttpClients.auth, isNot(same(auth)));
    expect(AppHttpClients.transfer, isNot(same(transfer)));
  });

  test('default backend permits sign-in while the retained vault stays locked',
      () async {
    SessionWork.complete('expired', authenticationRequired: true);
    var clients = 0, requests = 0;
    await http.runWithClient(() async {
      final api = BackendApi(
          baseUrlOverride: 'https://backend.example.test/api',
          localTestingProvider: () => true,
          accessTokenProvider: () async => 'local-test-token',
          signedEmailIdProvider: () async => 'fixture@example.test',
          deviceUuidProvider: () async => '',
          vaultGenerationOverride: '',
          sessionCookieProvider: () async => null);
      try {
        expect(clients, 0);
        await expectLater(
            api.get(endpoint: '/items'), throwsA(isA<SessionInvalidated>()));
        expect(requests, 0);
        final response = await SessionWork.authenticate(
            () => api.post(endpoint: '/local-test/session', jsonBody: {}));
        expect(response['success'], 1);
        expect(clients, 1);
        expect(requests, 1);
        expect(SessionWork.authenticationRequired, isTrue);
        await expectLater(
            api.get(endpoint: '/items'), throwsA(isA<SessionInvalidated>()));
        expect(requests, 1);
      } finally {
        api.close();
      }
    }, () {
      clients++;
      return MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/local-test/session');
        expect(request.headers['authorization'], 'Bearer local-test-token');
        return http.Response('{"success":1,"data":{}}', 200);
      });
    });
  });
}
