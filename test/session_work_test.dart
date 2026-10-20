import 'dart:async';

import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SessionWork.resetForTesting);
  tearDown(SessionWork.resetForTesting);

  test('a delayed revision read cannot reopen an invalidated session',
      () async {
    SessionWork.complete('old');
    final entered = Completer<void>();
    final release = Completer<SessionRevision>();
    SessionWork.readRevision = () {
      entered.complete();
      return release.future;
    };
    var ran = false;
    final action = SessionWork.run(() async => ran = true);
    await entered.future;
    SessionWork.invalidate('new');
    final rejected = expectLater(action, throwsA(isA<SessionInvalidated>()));
    release.complete(const SessionRevision('old'));
    await rejected;
    expect(ran, isFalse);
    expect(SessionWork.revision, 'new');
    expect(SessionWork.active, isFalse);
  });

  test('work awaiting its first probe cannot join a later login', () async {
    SessionWork.complete('old');
    final entered = Completer<void>();
    final release = Completer<SessionRevision>();
    SessionWork.readRevision = () {
      entered.complete();
      return release.future;
    };
    var ran = false;
    final action = SessionWork.run(() async => ran = true);
    await entered.future;
    SessionWork.invalidate('new');
    SessionWork.complete('new');
    final rejected = expectLater(action, throwsA(isA<SessionInvalidated>()));
    release.complete(const SessionRevision('new'));
    await rejected;
    expect(ran, isFalse);
    expect(SessionWork.revision, 'new');
    expect(SessionWork.active, isTrue);
  });

  test('pending cleanup rejects work before probing completed state', () async {
    SessionWork.invalidate('new');
    var probed = false;
    SessionWork.readRevision = () async {
      probed = true;
      return const SessionRevision('new');
    };
    await expectLater(SessionWork.run(() async => fail('retired work ran')),
        throwsA(isA<SessionInvalidated>()));
    expect(probed, isFalse);
  });

  test('ordinary concurrent probes retain valid work in the same revision',
      () async {
    SessionWork.complete('active');
    final probes = <Completer<SessionRevision>>[];
    SessionWork.readRevision = () {
      final probe = Completer<SessionRevision>();
      probes.add(probe);
      return probe.future;
    };
    var ran = 0;
    final first = SessionWork.run(() async => ran++);
    final second = SessionWork.run(() async => ran++);
    expect(probes.length, 2);
    probes.last.complete(const SessionRevision('active'));
    probes.first.complete(const SessionRevision('active'));
    await Future.wait([first, second]);
    expect(ran, 2);
    expect(SessionWork.active, isTrue);
  });
}
