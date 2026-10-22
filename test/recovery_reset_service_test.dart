import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_recovery_reset.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recovery_reset_fixture.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late RecoveryResetPeer peer;
  final stageKey = AppString.recoveryResetStage.string;
  setUp(() async {
    fixture = await SyncFixture.create();
    peer = RecoveryResetPeer();
    fixture.secrets.remove(AppString.masterKey.string);
    fixture.secrets.remove(AppString.fileHashKey.string);
    fixture.secrets[AppString.sessionCookie.string] = 'fixture-cookie';
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.delete(AppString.deviceUuid.string);
  });
  tearDown(() async => fixture.dispose());
  Map<String, dynamic> stage() => jsonDecode(fixture.secrets[stageKey]!);

  for (final available in [true, false]) {
    test('readiness check is read-only when available=$available', () async {
      peer.available = available;
      expect(await peer.service().checkAvailability(), available);
      expect(ModelSetting.get(AppString.recoveryResetAvailable.string),
          available ? 'yes' : 'no');
      expect(peer.requests, ['GET /api/recovery-reset/status']);
      expect(fixture.secrets[stageKey], isNull);
      expect(await getMasterKey(), isNull);
      expect(await getSignedInUserId(), 'fixture-user');
      expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
    });
  }

  test('failed readiness check cannot enable reset or stage new keys',
      () async {
    await ModelSetting.set(AppString.recoveryResetAvailable.string, 'no');
    peer.offline = true;
    await expectLater(peer.service().checkAvailability(), throwsException);
    expect(ModelSetting.get(AppString.recoveryResetAvailable.string), 'no');
    expect(fixture.secrets[stageKey], isNull);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(peer.prepareCalls, 0);
    expect(peer.confirmCalls, 0);
  });

  for (final error in ['sign_in_again', '14', '18']) {
    test(
        'readiness requires explicit reauthentication for $error without cleanup',
        () async {
      peer.statusError = error;
      final originalSecrets = Map.of(fixture.secrets);
      await expectLater(peer.service().checkAvailability(),
          throwsA(isA<RecoveryReauthenticationRequired>()));
      expect(fixture.secrets, originalSecrets);
      expect(await getSignedInUserId(), 'fixture-user');
      expect(
          peer.requests.every((request) => request.startsWith('GET ')), isTrue);
      expect(peer.prepareCalls, 0);
      expect(peer.confirmCalls, 0);
    });
  }

  test(
      'temporary session verification failure does not request reauthentication',
      () async {
    peer.statusError = 'session_unavailable';
    final originalSecrets = Map.of(fixture.secrets);
    await expectLater(peer.service().checkAvailability(),
        throwsA(isNot(isA<RecoveryReauthenticationRequired>())));
    expect(fixture.secrets, originalSecrets);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(peer.prepareCalls, 0);
    expect(peer.confirmCalls, 0);
  });

  test('readiness from a revoked session cannot enable reset', () async {
    await ModelSetting.set(AppString.recoveryResetAvailable.string, 'no');
    final entered = Completer<void>();
    final release = Completer<void>();
    peer.beforeStatus = () {
      entered.complete();
      return release.future;
    };
    final check = peer.service().checkAvailability();
    await entered.future;
    SessionWork.invalidate('revoked-readiness-session');
    final rejected = expectLater(check, throwsA(isA<SessionInvalidated>()));
    release.complete();
    await rejected;
    expect(ModelSetting.get(AppString.recoveryResetAvailable.string), 'no');
    expect(fixture.secrets[stageKey], isNull);
  });

  test(
      'verified deletion returns to generation without signing out or activating keys',
      () async {
    final service = peer.service();
    await service.confirm();
    peer.phase = 'ready';
    final ready = await peer.service().refresh();
    expect(ready.phase, RecoveryResetPhase.bootstrap);
    expect(await getMasterKey(), isNull);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
    expect(await getDeviceUuid(), isEmpty);
    expect(await SyncUtils.canSync(), isFalse);
    expect(
        (await peer.service().refresh()).phase, RecoveryResetPhase.bootstrap);
    expect(fixture.secrets[stageKey], isNull);
    expect(peer.confirmCalls, 1);
  });

  test('generation cannot activate keys before verified deletion', () async {
    await peer.service().confirm();
    final before = stage()['privateKeys'];
    expect((await peer.service().generateKeys()).phase,
        RecoveryResetPhase.waiting);
    expect(await getMasterKey(), isNull);
    expect(stage()['privateKeys'], before);
    expect(stage()['phase'], 'waiting');
    expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
  });

  test('failed durable generation action activates no keys and can be retried',
      () async {
    peer.deferredKeySetup = false; // Resume a released, already-staged reset.

    await peer.service().confirm();
    final before = stage()['privateKeys'];
    peer.phase = 'ready';
    fixture.beforeWrite = (key, value) async {
      if (key == stageKey && jsonDecode(value)['phase'] == 'activating') {
        throw PlatformException(code: 'WRITE_FAILED');
      }
    };
    expect((await peer.service().generateKeys()).phase,
        RecoveryResetPhase.unavailable);
    expect(await getMasterKey(), isNull);
    fixture.beforeWrite = null;
    expect(
        (await peer.service().refresh()).phase, RecoveryResetPhase.generation);
    expect(
        (await peer.service().generateKeys()).phase, RecoveryResetPhase.phrase);
    expect(stage()['privateKeys'], before);
    expect(peer.confirmCalls, 1);
  });

  test('an obsolete reset cannot activate keys from the generation action',
      () async {
    await peer.service().confirm();
    peer.statusError = 'vault_changed';
    expect(
        (await peer.service().generateKeys()).phase, RecoveryResetPhase.signIn);
    expect(await getMasterKey(), isNull);
    expect(await ModelProfile.get(), isNull);
    expect(fixture.secrets[stageKey], isNull);
  });

  test(
      'commit retains only the current session/staging and waits before revealing new words',
      () async {
    final original = await fixture.text('source.txt', 'external original');
    final service = peer.service();
    final view = await service.confirm();
    expect(view.phase, RecoveryResetPhase.waiting);
    expect(peer.confirmCalls, 1);
    expect(await original.readAsString(), 'external original');
    expect(await getSignedInUserId(), 'fixture-user');
    expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
    expect(fixture.secrets[AppString.jwtToken.string], 'unit-test-token');
    expect(await getMasterKey(), isNull);
    expect(await getDeviceUuid(), isEmpty);
    expect(await SyncUtils.canSync(), isFalse);
    final saved = stage();
    expect(saved['retiredCleared'], isTrue);
    expect(saved['privateKeys'].keys.toSet(), {
      AppString.masterKey.string,
      AppString.accessKey.string,
      AppString.fileHashKey.string
    });
    peer.phase = 'ready';
    expect(
        (await peer.service().refresh()).phase, RecoveryResetPhase.bootstrap);
    expect(fixture.secrets[stageKey], isNull);
    expect(await getMasterKey(), isNull);
    expect(await SyncUtils.canSync(), isFalse);
    expect(await ModelSetting.getRaw(AppString.vaultGeneration.string),
        RecoveryResetPeer.generation);
  });

  test('a newly signed-in device observes shared deletion and fresh setup',
      () async {
    await peer.service().confirm();
    fixture.secrets.remove(stageKey); // No initiating-device private state.
    var view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.waiting);
    expect(view.notBefore, peer.notBefore);
    expect(await getMasterKey(), isNull);
    peer.phase = 'ready';
    view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.bootstrap);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(await ModelSetting.getRaw(AppString.vaultGeneration.string),
        RecoveryResetPeer.generation);
    expect(peer.confirmCalls, 1);
  });

  test('shared cleanup failure remains waiting without generating keys',
      () async {
    await peer.service().confirm();
    fixture.secrets.remove(stageKey);
    peer.operationError = 'storage_unavailable';
    final view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.waiting);
    expect(view.error, 'storage_unavailable');
    expect(await getMasterKey(), isNull);
    expect(peer.confirmCalls, 1);
  });

  test('an older server cannot enable deferred-key reset', () async {
    peer.deferredKeySetup = false;
    expect(await peer.service().checkAvailability(), isFalse);
    expect(fixture.secrets[stageKey], isNull);
  });

  test('double confirmation taps create one operation and one key set',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    peer.beforePrepare = () async {
      entered.complete();
      await release.future;
    };
    final service = peer.service();
    final first = service.confirm();
    final second = service.confirm();
    await entered.future;
    release.complete();
    final results = await Future.wait([first, second]);
    expect(results.every((view) => view.phase == RecoveryResetPhase.waiting),
        isTrue);
    expect(peer.prepareCalls, 1);
    expect(peer.confirmCalls, 1);
  });

  test('fresh sign-in resumes an intent that never reached server preparation',
      () async {
    peer.offline = true;
    final service = peer.service();
    expect((await service.confirm()).phase, RecoveryResetPhase.unavailable);
    final original = stage();
    expect(original['phase'], 'intent');
    expect(peer.draft, isNull);
    fixture.secrets[AppString.sessionCookie.string] = 'fresh-fixture-cookie';
    peer.offline = false;

    expect((await peer.service().refresh()).phase,
        RecoveryResetPhase.confirmation);
    expect((await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
    final resumed = stage();
    expect(resumed['operationId'], original['operationId']);
    expect(resumed['privateKeys'], original['privateKeys']);
    expect(resumed['serverKeys'], original['serverKeys']);
    expect(resumed['deviceUuid'], original['deviceUuid']);
    expect(resumed['sessionHash'], isNot(original['sessionHash']));
    expect(peer.confirmCalls, 1);
  });

  test(
      'uncertain server status preserves an unprepared intent after fresh sign-in',
      () async {
    peer.offline = true;
    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    final original = stage();
    fixture.secrets[AppString.sessionCookie.string] = 'fresh-fixture-cookie';
    peer.offline = false;
    peer.statusError = 'session_unavailable';

    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    expect(stage(), original);
    expect(peer.prepareCalls, 0);
    expect(peer.confirmCalls, 0);
    expect(peer.envelope, isNull);
  });

  test('secure staging failure prevents any destructive request', () async {
    fixture.beforeWrite = (key, value) async {
      if (key == stageKey) throw PlatformException(code: 'LOCKED');
    };
    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    expect(peer.requests, isEmpty);
    expect(fixture.secrets[stageKey], isNull);
    expect((await ModelProfile.get())?.id, 'fixture-user');
  });

  test('rejected preparation offers a verified safe exit from reset', () async {
    peer.prepareError = 'recovery_unavailable';
    peer.available = false;
    final service = peer.service();
    expect((await service.confirm()).error, 'recovery_unavailable');
    final original = stage();
    expect(peer.draft, isNull);
    expect(peer.confirmCalls, 0);
    final view = await service.refresh();
    expect(view.phase, RecoveryResetPhase.confirmation);
    expect(view.canReturn, isTrue);
    expect(stage(), original);
    expect((await service.discardUnavailableStaging()).phase,
        RecoveryResetPhase.signIn);
    expect(await service.hasPending(), isFalse);
    expect(peer.confirmCalls, 0);
    expect(peer.envelope, isNull);
  });

  test('an uncertain unprepared intent keeps its keys and has no exit',
      () async {
    peer.prepareError = 'recovery_unavailable';
    final service = peer.service();
    await service.confirm();
    final original = stage();
    peer.statusError = 'session_unavailable';
    expect((await service.refresh()).canReturn, isFalse);
    expect((await service.discardUnavailableStaging()).phase,
        RecoveryResetPhase.unavailable);
    expect(stage(), original);
    expect(peer.confirmCalls, 0);
  });

  test(
      'failure persisting prepared progress prevents confirmation and can retry',
      () async {
    var fail = true;
    fixture.beforeWrite = (key, value) async {
      if (fail &&
          key == stageKey &&
          jsonDecode(value)['phase'] == 'confirming') {
        fail = false;
        throw PlatformException(code: 'WRITE_FAILED');
      }
    };
    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    expect(peer.confirmCalls, 0);
    final before = stage()['privateKeys'];
    expect((await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
    expect(stage()['privateKeys'], before);
    expect(peer.confirmCalls, 1);
  });

  test('a different live confirmation prevents discarding a missing intent',
      () async {
    peer.prepareError = 'recovery_unavailable';
    final service = peer.service();
    await service.confirm();
    final original = stage();
    peer.draft = {
      ...original,
      'operationId': '22222222-2222-4222-8222-222222222222'
    };
    expect((await service.refresh()).canReturn, isFalse);
    expect(
        (await service.discardUnavailableStaging()).error, 'reset_in_progress');
    expect(stage(), original);
    expect(peer.confirmCalls, 0);
  });

  test(
      'a committed request with lost response resumes the original staged keys',
      () async {
    peer.loseConfirmResponse = true;
    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    final before = stage();
    expect(peer.confirmCalls, 1);
    peer.offline = false;
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.waiting);
    expect(peer.confirmCalls, 1);
    expect(stage()['privateKeys'], before['privateKeys']);
    expect(stage()['operationId'], before['operationId']);
  });

  test('partial activation retries the same keys after process restart',
      () async {
    peer.deferredKeySetup = false; // Resume a released, already-staged reset.

    final service = peer.service();
    await service.confirm();
    peer.phase = 'ready';
    var fail = true;
    fixture.beforeWrite = (key, value) async {
      if (fail && key == AppString.accessKey.string) {
        fail = false;
        throw PlatformException(code: 'WRITE_FAILED');
      }
    };
    expect((await service.refresh()).phase, RecoveryResetPhase.generation);
    expect(
        (await service.generateKeys()).phase, RecoveryResetPhase.unavailable);
    final before = stage()['privateKeys'];
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.phrase);
    expect(stage()['privateKeys'], before);
    for (final entry in (before as Map).entries) {
      expect(fixture.secrets[entry.key], entry.value);
    }
    expect(peer.confirmCalls, 1);
  });

  test(
      'expired authentication preserves new staging while clearing account/session state',
      () async {
    peer.deferredKeySetup = false; // Resume a released, already-staged reset.

    await peer.service().confirm();
    final before = fixture.secrets[stageKey];
    expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
    expect(fixture.secrets[stageKey], before);
    expect(fixture.secrets[AppString.sessionCookie.string], isNull);
    expect(fixture.secrets[AppString.jwtToken.string], isNull);
    expect(await ModelProfile.get(), isNull);
    expect(await ModelSetting.getRaw(AppString.recoveryReauthentication.string),
        'yes');
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.signIn);
    fixture.secrets[AppString.sessionCookie.string] = 'new-cookie';
    await (await ModelProfile.fromMap(
            {'id': 'fixture-user', 'email': 'fixture@example.test'}))
        .insert();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    peer.phase = 'ready';
    expect(
        (await peer.service().refresh()).phase, RecoveryResetPhase.generation);
    expect(
        (await peer.service().generateKeys()).phase, RecoveryResetPhase.phrase);
    expect(peer.confirmCalls, 1);
  });

  test(
      'a different signed-in account cannot send or activate another account staging',
      () async {
    await peer.service().confirm();
    await SessionCleanup.instance.expiredAuthentication();
    fixture.secrets[AppString.sessionCookie.string] = 'different-cookie';
    await (await ModelProfile.fromMap(
            {'id': 'other-user', 'email': 'other@example.test'}))
        .insert();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    final requests = peer.requests.length;
    final view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.signIn);
    expect(view.email, 'fixture@example.test');
    expect(peer.requests.length, requests);
    expect(await getMasterKey(), isNull);
  });

  test(
      'mismatched server envelope never activates keys or silently starts another reset',
      () async {
    await peer.service().confirm();
    peer.phase = 'ready';
    peer.corruptEnvelopeHash = true;
    final view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.missingKeys);
    expect(view.canReturn, isTrue);
    expect(await getMasterKey(), isNull);
    expect(peer.confirmCalls, 1);
    expect(fixture.secrets[stageKey], isNotNull);
  });

  test('unusable staging cannot be discarded while deletion is still pending',
      () async {
    final service = peer.service();
    await service.confirm();
    expect((await service.discardUnavailableStaging()).phase,
        RecoveryResetPhase.unavailable);
    expect(fixture.secrets[stageKey], isNotNull);
    peer.phase = 'ready';
    expect((await service.discardUnavailableStaging()).phase,
        RecoveryResetPhase.signIn);
    expect(fixture.secrets, isEmpty);
    expect(peer.confirmCalls, 1);
  });

  test('tampered staged keys cannot reach destructive confirmation', () async {
    fixture.beforeWrite = (key, value) async {
      if (key == stageKey && jsonDecode(value)['phase'] == 'confirming') {
        throw PlatformException(code: 'LOCKED');
      }
    };
    await peer.service().confirm();
    fixture.beforeWrite = null;
    final changed = stage();
    changed['privateKeys'][AppString.masterKey.string] =
        base64Encode(Uint8List(32));
    fixture.secrets[stageKey] = jsonEncode(changed);
    final prepareCalls = peer.prepareCalls;
    final view = await peer.service().confirm();
    expect(view.phase, RecoveryResetPhase.missingKeys);
    expect(view.canReturn, isFalse);
    expect(peer.prepareCalls, prepareCalls);
    expect(peer.confirmCalls, 0);
    expect(peer.envelope, isNull);
  });

  test(
      'prepared status exposes storage failure and stale-signin recovery after restart',
      () async {
    peer.confirmError = 'storage_access_required';
    final first = await peer.service().confirm();
    expect(first.phase, RecoveryResetPhase.confirmation);
    expect(first.error, 'storage_access_required');
    expect((await peer.service().refresh()).error, 'storage_access_required');
    expect(peer.envelope, isNull);
    peer.requiresFreshSignin = true;
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.signIn);
    expect(fixture.secrets[stageKey], isNotNull);
    expect((await ModelProfile.get())?.id, 'fixture-user');
  });

  test('changed sign-in waits for authoritative preparation expiry', () async {
    peer.confirmError = 'sign_in_again';
    await peer.service().confirm();
    final before = stage();
    fixture.secrets[AppString.sessionCookie.string] = 'newer-fixture-cookie';
    // A wrong device clock cannot expire server authorization.
    peer.expiresAtOverride = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    final waiting = await peer.service().confirm();
    expect(waiting.phase, RecoveryResetPhase.confirmation);
    expect(waiting.error, 'confirmation_expiring');
    expect(peer.prepareCalls, 1);
    expect(peer.confirmCalls, 1);
    expect(stage()['operationId'], before['operationId']);
    peer.expired = true;
    final expired = await peer.service().refresh();
    expect(expired.canReturn, isTrue);
    peer.confirmError = null;
    expect((await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
    expect(stage()['operationId'], isNot(before['operationId']));
    expect(stage()['privateKeys'], isNot(before['privateKeys']));
    expect(peer.prepareCalls, 2);
  });

  test(
      'expired preparation preserves the vault generation across fresh sign-in',
      () async {
    const currentGeneration = '22222222-2222-4222-8222-222222222222';
    peer.currentGeneration = currentGeneration;
    await ModelSetting.set(AppString.vaultGeneration.string, currentGeneration);
    peer.confirmError = 'sign_in_again';
    final service = peer.service();
    await service.confirm();
    final previous = stage();
    await service.prepareSignin();
    expect(
        await ModelSetting.getRaw(AppString.vaultGeneration.string), isEmpty);
    await (await ModelProfile.fromMap(
            {'id': 'fixture-user', 'email': 'fixture@example.test'}))
        .insert();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    fixture.secrets[AppString.sessionCookie.string] = 'fresh-fixture-cookie';
    peer.expired = true;
    peer.confirmError = null;

    expect((await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
    expect(peer.draft!['expectedGeneration'], currentGeneration);
    expect(stage()['operationId'], isNot(previous['operationId']));
    expect(stage()['expectedGeneration'], currentGeneration);
  });

  test('another reset revokes obsolete staging instead of activating it',
      () async {
    await peer.service().confirm();
    peer.statusError = 'vault_changed';
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.signIn);
    expect(fixture.secrets, isEmpty);
    expect(await ModelProfile.get(), isNull);
    expect(await getMasterKey(), isNull);
  });

  test('failure saving local cleanup completion resumes committed key set',
      () async {
    var fail = true;
    fixture.beforeWrite = (key, value) async {
      if (fail && key == stageKey && jsonDecode(value)['phase'] == 'waiting') {
        fail = false;
        throw PlatformException(code: 'LOCKED');
      }
    };
    expect(
        (await peer.service().confirm()).phase, RecoveryResetPhase.unavailable);
    final before = stage();
    expect(peer.confirmCalls, 1);
    expect(await getMasterKey(), isNull);
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.waiting);
    expect(stage()['privateKeys'], before['privateKeys']);
    expect(stage()['operationId'], before['operationId']);
    expect(peer.confirmCalls, 1);
  });

  test('damaged staging remains until pending confirmation expires', () async {
    peer.confirmError = 'sign_in_again';
    await peer.service().confirm();
    fixture.secrets[stageKey] = '{invalid json';
    final view = await peer.service().refresh();
    expect(view.phase, RecoveryResetPhase.missingKeys);
    expect(view.canReturn, isFalse);
    expect((await peer.service().discardUnavailableStaging()).phase,
        RecoveryResetPhase.unavailable);
    expect(fixture.secrets[stageKey], isNotNull);
    peer.expired = true;
    expect((await peer.service().discardUnavailableStaging()).phase,
        RecoveryResetPhase.signIn);
    expect(fixture.secrets, isEmpty);
    expect(peer.envelope, isNull);
  });
}
