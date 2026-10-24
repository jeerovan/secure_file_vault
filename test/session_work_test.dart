import 'dart:async';

import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SessionWork.resetForTesting);
  tearDown(SessionWork.resetForTesting);

  test('authentication hold allows only authentication work', () async {
    SessionWork.complete('held', authenticationRequired: true);
    expect(SessionWork.active, isFalse);
    await expectLater(SessionWork.run(() async => fail('private work ran')),
        throwsA(isA<SessionInvalidated>()));
    expect(await SessionWork.authenticate(() async => 'signin'), 'signin');
    SessionWork.invalidate('pending');
    await expectLater(SessionWork.authenticate(() async {}),
        throwsA(isA<SessionInvalidated>()));
  });

  test('old authentication cannot join a newer activated account', () async {
    SessionWork.complete('held', authenticationRequired: true);
    final gate = Completer<void>();
    final entered = Completer<void>();
    final old = SessionWork.authenticate(() async {
      entered.complete();
      await gate.future;
      await SessionWork.authenticate(SessionWork.checkpoint);
    });
    await entered.future;
    SessionWork.complete('new');
    final rejected = expectLater(old, throwsA(isA<SessionInvalidated>()));
    gate.complete();
    await rejected;
    expect(SessionWork.revision, 'new');
  });

  test('delayed probe cannot remove a newly applied authentication hold',
      () async {
    SessionWork.complete('same');
    final gate = Completer<SessionRevision>();
    SessionWork.readRevision = () => gate.future;
    final old = SessionWork.run(() async => fail('vault reopened'));
    SessionWork.complete('same', authenticationRequired: true);
    final rejected = expectLater(old, throwsA(isA<SessionInvalidated>()));
    gate.complete(const SessionRevision('same'));
    await rejected;
    expect(SessionWork.authenticationRequired, isTrue);
  });

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
