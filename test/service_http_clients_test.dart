import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(AppHttpClients.closeAll);

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
}
