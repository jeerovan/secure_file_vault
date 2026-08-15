import 'dart:async';

import 'package:file_vault_bb/services/service_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth refresh is single-flight for concurrent callers', () async {
    final coordinator = AuthRefreshSingleFlight();
    final gate = Completer<void>();
    var refreshes = 0;

    Future<void> refresh() async {
      refreshes++;
      await gate.future;
    }

    final futures = [
      coordinator.run(refresh),
      coordinator.run(refresh),
      coordinator.run(refresh),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
    gate.complete();
    await Future.wait(futures);
  });
}
