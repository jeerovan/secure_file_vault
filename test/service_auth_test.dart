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

  test('all refresh waiters receive failure and the next request can recover',
      () async {
    final coordinator = AuthRefreshSingleFlight();
    final gate = Completer<void>();
    var calls = 0;
    Future<void> refresh() {
      calls++;
      return gate.future;
    }
    final first = expectLater(coordinator.run(refresh), throwsStateError);
    final second = expectLater(coordinator.run(refresh), throwsStateError);
    gate.completeError(StateError('temporary authentication outage'));
    await Future.wait([first, second]);
    expect(calls, 1);
    await coordinator.run(() async => calls++);
    expect(calls, 2);
  });

  test('synchronously rejected refresh cannot leave authentication stuck',
      () async {
    final coordinator = AuthRefreshSingleFlight();
    await expectLater(
        coordinator.run(() => throw StateError('configuration unavailable')),
        throwsStateError);
    var recovered = false;
    await coordinator.run(() async => recovered = true);
    expect(recovered, isTrue);
  });
}
