import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late SessionAuthentication sessions;
  late File original, download, part;
  late String master;
  late Map<String, List<Map<String, Object?>>> snapshot;
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];
  const account = AuthenticatedAccount(
      id: 'fixture-user',
      email: 'FIXTURE@example.test',
      service: 'neon',
      cookie: 'new-cookie');
  Map<String, dynamic> keys = {};
  http.Response json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);

  setUp(() async {
    fixture = await SyncFixture.create();
    await ModelItem.ensureVaultRoot();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.locale.string, 'de');
    await ModelSetting.set(AppString.vaultGeneration.string, 'vault-1');
    await ModelSetting.set(AppString.foregroundSyncIntervalMinutes.string, '7');
    fixture.secrets[AppString.sessionCookie.string] = 'old-cookie';
    fixture.secrets[AppString.keyCipher.string] = 'cipher-1';
    fixture.secrets[AppString.keyNonce.string] = 'nonce-1';
    original = await fixture.text('pending.txt', 'external original');
    await fixture.scan();
    download = File('${fixture.directory.path}/FiFe/download.txt');
    await download.parent.create(recursive: true);
    await download.writeAsString('private download');
    part = File('${fixture.directory.path}/${'A' * 43}_1.crypt.ready');
    await part.writeAsString('encrypted part');
    master = fixture.secrets[AppString.masterKey.string]!;
    snapshot = await fixture.snapshot();
    requests.clear();
    keys = {
      'cipher': 'cipher-1',
      'nonce': 'nonce-1',
      'key_state': 'present',
      'vault_generation': 'vault-1'
    };
    respond = (request) async {
      if (request.url.path.endsWith('/keys')) {
        expect(request.headers['device_uuid'], isNull);
        expect(request.headers['x-fife-vault-generation'], isNull);
        return json({'success': 1, 'data': keys});
      }
      expect(request.url.path, endsWith('/devices'));
      expect(request.headers['device_uuid'], 'fixture-device-uuid');
      expect(request.headers['x-fife-vault-generation'], 'vault-1');
      return json({
        'success': 1,
        'data': {'id': 'fixture-device-uuid', 'active': 1}
      });
    };
    sessions = SessionAuthentication.test(
        apiFactory: (candidate, device, generation) => BackendApi(
            baseUrlOverride: 'https://backend.example.test/api',
            httpClient: MockClient((request) async {
              requests.add(request);
              expect(request.headers['authorization'], 'Bearer fresh-jwt');
              expect(request.headers['x-fife-session'], candidate.cookie);
              return respond(request);
            }),
            accessTokenProvider: () async => candidate.jwt,
            signedEmailIdProvider: () async => candidate.email,
            deviceUuidProvider: () async => device,
            sessionCookieProvider: () async => candidate.cookie,
            vaultGenerationOverride: generation,
            localTestingProvider: () => false,
            enforceDeviceRevocation: false,
            requireFreshAuthentication: true,
            refreshAuth: () async {}));
    expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
  });
  tearDown(() async => fixture.dispose());

  Future<void> stage([AuthenticatedAccount value = account]) async {
    final nonce = await sessions.beginAttempt();
    await sessions.stageVerified(nonce, value);
  }

  Future<void> complete() =>
      sessions.completeSignin(refreshNeon: (value) async {
        expect(value.cookie, isNot('old-cookie'));
        return 'fresh-jwt';
      });
  Future<void> retained() async {
    expect(SessionWork.authenticationRequired, isTrue);
    expect(SessionWork.active, isFalse);
    expect(fixture.secrets[AppString.masterKey.string], master);
    await SessionWork.authenticate(() async {
      expect(await fixture.snapshot(), snapshot);
      expect((await ModelProfile.get())?.id, 'fixture-user');
    });
    expect(await download.exists(), isTrue);
    expect(await part.exists(), isTrue);
    expect(await original.readAsString(), 'external original');
  }

  Future<void> cleared(String id) async {
    expect(SessionWork.active, isTrue);
    expect(SessionWork.authenticationRequired, isFalse);
    expect(fixture.secrets[AppString.masterKey.string], isNull);
    expect((await ModelProfile.get())?.id, id);
    expect(await getDeviceUuid(), isEmpty);
    expect(await ModelSetting.getRaw(AppString.locale.string), 'de');
    expect((await fixture.snapshot())['item_tasks'], isEmpty);
    expect((await fixture.snapshot())['files'], isEmpty);
    expect(await download.exists(), isFalse);
    expect(await part.exists(), isFalse);
    expect(await original.readAsString(), 'external original');
    expect(fixture.secrets[AppString.sessionCookie.string], 'new-cookie');
    expect(fixture.secrets[AppString.jwtToken.string], 'fresh-jwt');
  }

  test(
      'verified same account resumes keys, registration, files, queues and preferences',
      () async {
    await retained();
    expect(await SyncUtils.canSync(), isFalse);
    await stage();
    await complete();
    expect(SessionWork.active, isTrue);
    expect(fixture.secrets[AppString.masterKey.string], master);
    expect(await fixture.snapshot(), snapshot);
    expect(await getDeviceUuid(), 'fixture-device-uuid');
    expect(ModelSetting.foregroundSyncIntervalMinutes, 7);
    expect(await download.readAsString(), 'private download');
    expect(await part.exists(), isTrue);
    expect(await sessions.pendingAccount(), isNull);
    expect(requests.length, 2);
    final setup = AppSetupState(SecureStorage());
    try {
      await setup.recheckStatus();
      expect(setup.currentStep, SetupStep.explorer);
    } finally {
      setup.dispose();
    }
  });

  for (final value in [
    const AuthenticatedAccount(
        id: 'other-user',
        email: 'other@example.test',
        service: 'neon',
        cookie: 'new-cookie'),
    const AuthenticatedAccount(
        id: 'changed-subject',
        email: 'fixture@example.test',
        service: 'neon',
        cookie: 'new-cookie'),
    const AuthenticatedAccount(
        id: 'fixture-user',
        email: 'changed@example.test',
        service: 'neon',
        cookie: 'new-cookie'),
  ]) {
    test(
        'verified changed owner ${value.id} ${value.email} clears before activation',
        () async {
      fixture.beforeWrite = (key, _) async {
        if (key == AppString.jwtToken.string ||
            key == AppString.sessionCookie.string) {
          expect(fixture.secrets[AppString.masterKey.string], isNull);
          expect(
              await (await StorageSqlite.instance.executor).query('item_tasks'),
              isEmpty);
          expect(await download.exists(), isFalse);
          expect(SessionWork.active, isTrue); // Cleanup maintenance zone only.
          expect(SessionWork.authenticationRequired, isTrue);
        }
      };
      await stage(value);
      await complete();
      await cleared(value.id);
    });
  }

  test('unverified, superseded and discarded attempts cannot clear a vault',
      () async {
    final stale = await sessions.beginAttempt();
    await sessions.beginAttempt();
    await expectLater(sessions.stageVerified(stale, account),
        throwsA(isA<SessionInvalidated>()));
    await expectLater(complete(), throwsStateError);
    await sessions.discardCandidate();
    await retained();
    expect(requests, isEmpty);
  });

  for (final response in [
    json({'success': 0}, 503),
    json({'success': 1, 'data': {}}),
    http.Response('broken', 200)
  ]) {
    test(
        'temporary or incomplete vault validation preserves hold and allows retry: ${response.body}',
        () async {
      final normal = respond;
      respond = (_) async => response;
      await stage();
      await expectLater(complete(), throwsStateError);
      await retained();
      expect((await sessions.pendingAccount())?.id, account.id);
      respond = normal;
      await complete();
      expect(fixture.secrets[AppString.masterKey.string], master);
      expect(SessionWork.active, isTrue);
    });
  }

  for (final status in [401, 403]) {
    test('fresh backend authentication $status expires only the candidate',
        () async {
      respond = (_) async => json({'success': 0, 'message': '14'}, status);
      await stage();
      await expectLater(complete(), throwsA(isA<VerifiedSigninExpired>()));
      expect(await sessions.pendingAccount(), isNull);
      await retained();
    });
  }

  for (final reason in [
    'device_revoked',
    'vault_replaced',
    'account_removed'
  ]) {
    test(
        'authoritative $reason clears retained vault while using fresh sign-in',
        () async {
      final normal = respond;
      respond = (request) async => request.url.path.endsWith('/devices')
          ? json({
              'success': 0,
              'message': reason == 'account_removed' ? '1' : '8',
              'reason': reason
            })
          : normal(request);
      await stage();
      await complete();
      await cleared(account.id);
    });
  }

  test('temporary membership failure does not become a revocation', () async {
    final normal = respond;
    respond = (request) async => request.url.path.endsWith('/devices')
        ? throw const SocketException('offline')
        : normal(request);
    await stage();
    await expectLater(complete(), throwsStateError);
    await retained();
    respond = normal;
    await complete();
    expect(fixture.secrets[AppString.masterKey.string], master);
  });

  for (final data in [
    null,
    <String, dynamic>{},
    {'id': 'fixture-device-uuid', 'active': 0}
  ]) {
    test(
        'legacy absent or inactive own-device status clears retained registration: $data',
        () async {
      final normal = respond;
      respond = (request) async => request.url.path.endsWith('/devices')
          ? json({'success': 1, 'data': data})
          : normal(request);
      await stage();
      await complete();
      await cleared(account.id);
    });
  }

  for (final key in [
    AppString.recoveryResetStage,
    AppString.vaultKeySetupStage
  ]) {
    for (final same in [true, false]) {
      test('${key.name} retains staging only for its verified owner: $same',
          () async {
        final raw = jsonEncode({
          'userId': same ? account.id : 'foreign-user',
          'email': same ? account.email : 'foreign@example.test',
          'phase': 'fixture'
        });
        fixture.secrets[key.string] = raw;
        await stage();
        await complete();
        if (same) {
          expect(fixture.secrets[key.string], raw);
          expect(fixture.secrets[AppString.masterKey.string], master);
        } else {
          expect(fixture.secrets[key.string], isNull);
          await cleared(account.id);
        }
      });
    }
  }

  for (final changed in ['generation', 'envelope', 'missing']) {
    test('same email with $changed vault does not reuse old keys', () async {
      if (changed == 'generation') keys['vault_generation'] = 'vault-2';
      if (changed == 'envelope') keys['cipher'] = 'different-cipher';
      if (changed == 'missing') {
        keys = {
          'cipher': null,
          'nonce': null,
          'key_state': 'missing',
          'vault_generation': 'vault-2'
        };
      }
      await stage();
      await complete();
      await cleared(account.id);
    });
  }

  test('hold and verified candidate survive a process-state restart', () async {
    await stage();
    await StorageSqlite.instance.close();
    SessionCleanup.instance.resetForTesting();
    ModelSetting.clear();
    expect(await SessionCleanup.instance.resume(), isTrue);
    await retained();
    await complete();
    expect(SessionWork.active, isTrue);
    expect(fixture.secrets[AppString.masterKey.string], master);
    expect(await fixture.snapshot(), snapshot);
  });

  test(
      'failed different-owner secure cleanup never activates credentials; retry resumes',
      () async {
    const other = AuthenticatedAccount(
        id: 'other-user',
        email: 'other@example.test',
        service: 'neon',
        cookie: 'new-cookie');
    await stage(other);
    fixture.beforeDelete = (key) async {
      if (key == AppString.masterKey.string) {
        throw PlatformException(code: 'KEYCHAIN_LOCKED');
      }
    };
    await expectLater(complete(), throwsStateError);
    expect(await SessionCleanup.instance.pending, isTrue);
    expect(SessionWork.active, isFalse);
    expect(fixture.secrets[AppString.jwtToken.string], isNull);
    expect(fixture.secrets[AppString.sessionCookie.string], isNull);
    fixture.beforeDelete = null;
    expect(await SessionCleanup.instance.resume(), isTrue);
    await complete();
    await cleared(other.id);
  });

  test(
      'partial credential activation remains locked and retries the verified candidate',
      () async {
    await stage();
    fixture.beforeWrite = (key, _) async {
      if (key == AppString.jwtToken.string) {
        throw PlatformException(code: 'KEYCHAIN_LOCKED');
      }
    };
    await expectLater(complete(), throwsA(isA<PlatformException>()));
    await retained();
    fixture.beforeWrite = null;
    await complete();
    expect(SessionWork.active, isTrue);
    expect(fixture.secrets[AppString.masterKey.string], master);
  });

  test('late candidate validation cannot overwrite a newer sign-in attempt',
      () async {
    final entered = Completer<void>(), gate = Completer<void>();
    final normal = respond;
    respond = (request) async {
      if (!entered.isCompleted) {
        entered.complete();
        await gate.future;
      }
      return normal(request);
    };
    await stage();
    final old = complete();
    await entered.future;
    final newer = await sessions.beginAttempt();
    final rejected = expectLater(old, throwsA(isA<SessionInvalidated>()));
    gate.complete();
    await rejected;
    await retained();
    await sessions.stageVerified(newer, account);
    await complete();
    expect(SessionWork.active, isTrue);
  });

  test('cleanup cannot erase a vault over a newer committed sign-in attempt',
      () async {
    const other = AuthenticatedAccount(
        id: 'other-user',
        email: 'other@example.test',
        service: 'neon',
        cookie: 'new-cookie');
    final reading = Completer<void>(), release = Completer<void>();
    var validated = false, paused = false, newerCommitted = false;
    final normal = respond;
    respond = (request) async {
      final result = await normal(request);
      validated = true;
      return result;
    };
    fixture.afterRead = (key, value) async {
      if (key == AppString.authenticationCandidate.string &&
          validated &&
          !paused) {
        paused = true;
        reading.complete();
        await release.future;
      }
    };
    await stage(other);
    Object? oldError, newerError;
    final old = complete().catchError((Object error) {
      oldError = error;
    });
    await reading.future;
    final newer = sessions.beginAttempt().then((_) {
      newerCommitted = true;
    }).catchError((Object error) {
      newerError = error;
    });
    // Give a competing secure-store mutation an opportunity to commit while
    // the old intent's platform read is still in flight.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    release.complete();
    await Future.wait([old, newer]);
    expect(!newerCommitted || oldError is SessionInvalidated, isTrue,
        reason: 'A superseded sign-in must not erase the retained vault');
    if (newerCommitted) {
      await retained();
    } else {
      expect(newerError, isA<SessionInvalidated>());
      await cleared(other.id);
    }
  });

  test(
      'failed candidate removal after activation cannot reactivate retired credentials',
      () async {
    await stage();
    fixture.beforeDelete = (key) async {
      if (key == AppString.authenticationCandidate.string) {
        throw PlatformException(code: 'LOCKED');
      }
    };
    await complete();
    expect(SessionWork.active, isTrue);
    expect(await sessions.pendingAccount(), isNull);
    await expectLater(complete(), throwsStateError);
  });
}
