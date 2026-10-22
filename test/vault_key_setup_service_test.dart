import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_vault_key_setup.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const generation = '11111111-1111-4111-8111-111111111111';
  final stageKey = AppString.vaultKeySetupStage.string;
  late SyncFixture fixture;
  Map<String, dynamic>? accepted;
  bool offline = false, loseReply = false, conflict = false, noUser = false;
  String? reportedGeneration;
  int posts = 0;
  Future<void> Function()? beforePost;
  VaultKeySetupService service() => VaultKeySetupService.test(
      apiFactory: () => BackendApi(
          baseUrlOverride: 'https://api.example.test/api',
          refreshAuth: () async {},
          httpClient: MockClient((request) async {
            expect(request.headers['x-fife-recovery-protocol'], '2');
            if (offline) return http.Response('', 503);
            if (request.method == 'POST') {
              posts++;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(
                  body.keys.toSet(), {'cipher', 'nonce', 'expectedGeneration'});
              expect(body['expectedGeneration'], generation);
              expect(fixture.secrets[stageKey], isNotNull);
              expect(await getMasterKey(), isNull);
              await beforePost?.call();
              if (conflict) {
                accepted = {
                  'cipher': 'another-device',
                  'nonce': 'another-nonce'
                };
                return http.Response(
                    jsonEncode({
                      'success': 0,
                      'message': 15,
                      'reason': 'key_setup_conflict'
                    }),
                    200);
              }
              accepted ??= {'cipher': body['cipher'], 'nonce': body['nonce']};
              if (loseReply) {
                offline = true;
                return http.Response('', 503);
              }
              return http.Response('{"success":1}', 200);
            }
            return http.Response(
                jsonEncode(noUser
                    ? {'success': 0, 'message': 1}
                    : {
                        'success': 1,
                        'data': {
                          'cipher': accepted?['cipher'],
                          'nonce': accepted?['nonce'],
                          'key_state': accepted == null ? 'missing' : 'present',
                          'vault_generation': reportedGeneration
                        }
                      }),
                200);
          })));
  Map<String, dynamic> stage() => jsonDecode(fixture.secrets[stageKey]!);
  setUp(() async {
    fixture = await SyncFixture.create();
    for (final key in [
      AppString.masterKey,
      AppString.accessKey,
      AppString.fileHashKey
    ]) {
      fixture.secrets.remove(key.string);
    }
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.vaultGeneration.string, generation);
    await ModelSetting.delete(AppString.deviceUuid.string);
    accepted = null;
    offline = false;
    loseReply = false;
    conflict = false;
    noUser = false;
    posts = 0;
    beforePost = null;
    reportedGeneration = generation;
  });
  tearDown(() => fixture.dispose());

  test('fresh notice does not create keys until explicit generation', () async {
    expect((await service().resume()).phase, VaultKeySetupPhase.generation);
    expect(fixture.secrets[stageKey], isNull);
    expect(await getMasterKey(), isNull);
    expect(posts, 0);
  });

  test(
      'accepted creation requires phrase acknowledgment and stable registration',
      () async {
    final setup = service();
    expect((await setup.generate()).phase, VaultKeySetupPhase.phrase);
    expect(await getMasterKey(),
        stage()['privateKeys'][AppString.masterKey.string]);
    expect(accepted?['cipher'], stage()['serverKeys']['cipher']);
    await expectLater(setup.registrationUuid(), throwsStateError);
    await setup.acknowledge();
    final uuid = await setup.registrationUuid();
    expect((await service().resume()).phase, VaultKeySetupPhase.registration);
    expect(await service().registrationUuid(), uuid);
    await ModelSetting.set(AppString.deviceUuid.string, uuid!);
    await service().finishRegistration(uuid);
    expect(await setup.hasPending(), isFalse);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(await getMasterKey(), isNotNull);
  });

  test('lost response and process restart recover the accepted phrase',
      () async {
    loseReply = true;
    expect((await service().generate()).phase, VaultKeySetupPhase.unavailable);
    final candidate = stage();
    expect(await getMasterKey(), isNull);
    offline = false;
    expect((await service().resume()).phase, VaultKeySetupPhase.phrase);
    expect(stage()['privateKeys'], candidate['privateKeys']);
    expect(posts, 1);
  });

  test('offline creation retries the identical unactivated candidate',
      () async {
    offline = true;
    expect((await service().generate()).phase, VaultKeySetupPhase.unavailable);
    final candidate = stage();
    expect(await getMasterKey(), isNull);
    offline = false;
    expect((await service().generate()).phase, VaultKeySetupPhase.phrase);
    expect(stage()['privateKeys'], candidate['privateKeys']);
    expect(posts, 1);
  });

  test('concurrent losing candidate is discarded without activating its keys',
      () async {
    conflict = true;
    expect((await service().generate()).phase, VaultKeySetupPhase.recovery);
    expect(fixture.secrets[stageKey], isNull);
    expect(await getMasterKey(), isNull);
    expect(await getSignedInUserId(), 'fixture-user');
    expect(accepted?['cipher'], 'another-device');
  });

  test('double generation taps publish only one candidate', () async {
    final entered = Completer<void>(), release = Completer<void>();
    beforePost = () {
      entered.complete();
      return release.future;
    };
    final setup = service();
    final first = setup.generate();
    await entered.future;
    final second = setup.generate();
    release.complete();
    expect((await first).phase, VaultKeySetupPhase.phrase);
    expect((await second).phase, VaultKeySetupPhase.phrase);
    expect(posts, 1);
  });

  test('secure staging failure prevents publication', () async {
    fixture.beforeWrite = (key, value) async {
      if (key == stageKey) throw PlatformException(code: 'LOCKED');
    };
    expect((await service().generate()).phase, VaultKeySetupPhase.unavailable);
    expect(posts, 0);
    expect(await getMasterKey(), isNull);
  });

  test(
      'partial private activation resumes the accepted candidate after restart',
      () async {
    var fail = true;
    fixture.beforeWrite = (key, value) async {
      if (key == AppString.accessKey.string && fail) {
        fail = false;
        throw PlatformException(code: 'LOCKED');
      }
    };
    expect((await service().generate()).phase, VaultKeySetupPhase.unavailable);
    final candidate = stage();
    expect(candidate['phase'], 'claimed');
    expect((await service().resume()).phase, VaultKeySetupPhase.phrase);
    expect(stage()['privateKeys'], candidate['privateKeys']);
    expect(posts, 1);
  });

  test('reauthentication preserves candidate, generation and phrase obligation',
      () async {
    await service().generate();
    final candidate = fixture.secrets[stageKey];
    expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
    expect(fixture.secrets[stageKey], candidate);
    expect(await getMasterKey(), isNull);
    expect(await getSignedInUserId(), isNull);
    await (await ModelProfile.fromMap(
            {'id': 'fixture-user', 'email': 'fixture@example.test'}))
        .insert();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    expect((await service().resume()).phase, VaultKeySetupPhase.phrase);
    await expectLater(service().registrationUuid(), throwsStateError);
    expect(posts, 1);
  });

  test('simulation creates local keys without publishing an envelope',
      () async {
    await ModelSetting.set(AppString.simulateTesting.string, 'yes');
    expect((await service().generate()).phase, VaultKeySetupPhase.phrase);
    expect(await getMasterKey(), isNotNull);
    expect(accepted, isNull);
    expect(posts, 0);
    await service().acknowledge();
    expect(await service().registrationUuid(), isNotEmpty);
  });

  test('forced removal erases private candidates too', () async {
    await service().generate();
    expect(await SessionCleanup.instance.request(), isTrue);
    expect(fixture.secrets[stageKey], isNull);
    expect(await getMasterKey(), isNull);
  });

  test('revocation while publishing cannot activate the returned keys',
      () async {
    beforePost = () async {
      SessionWork.invalidate('revoked-key-claim');
    };
    await expectLater(service().generate(), throwsA(isA<SessionInvalidated>()));
    expect(await getMasterKey(), isNull);
  });

  test('tampered candidate cannot be submitted or activated', () async {
    offline = true;
    await service().generate();
    offline = false;
    final candidate = stage();
    candidate['privateKeys'][AppString.masterKey.string] =
        base64Encode(List.filled(32, 0));
    fixture.secrets[stageKey] = jsonEncode(candidate);
    expect((await service().generate()).phase, VaultKeySetupPhase.unavailable);
    expect(posts, 0);
    expect(await getMasterKey(), isNull);
  });

  test('a changed account cannot read or submit another user candidate',
      () async {
    offline = true;
    await service().generate();
    offline = false;
    await (await fixture.db).delete('profiles');
    await (await ModelProfile.fromMap(
            {'id': 'other', 'email': 'other@example.test'}))
        .insert();
    await expectLater(service().resume(), throwsA(isA<SessionInvalidated>()));
    expect(posts, 0);
    expect(await getMasterKey(), isNull);
    expect(fixture.secrets[stageKey], isNotNull);
    expect(await ModelSetting.getRaw(AppString.signedIn.string), isNot('yes'));
    expect(await ModelProfile.get(), isNull);
  });

  for (final invalidGeneration in [null, '', 'invalid-generation']) {
    test('an ambiguous generation $invalidGeneration preserves private staging',
        () async {
      offline = true;
      await service().generate();
      final candidate = fixture.secrets[stageKey];
      offline = false;
      reportedGeneration = invalidGeneration;
      expect((await service().resume()).phase, VaultKeySetupPhase.unavailable);
      expect(fixture.secrets[stageKey], candidate);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      expect(await getMasterKey(), isNull);
    });
  }

  test('a verified newer generation clears an obsolete private candidate',
      () async {
    offline = true;
    await service().generate();
    offline = false;
    reportedGeneration = '22222222-2222-4222-8222-222222222222';
    await expectLater(service().resume(), throwsA(isA<SessionInvalidated>()));
    expect(fixture.secrets[stageKey], isNull);
    expect(await ModelSetting.getRaw(AppString.signedIn.string), isNot('yes'));
    expect(await getMasterKey(), isNull);
  });

  test(
      'an accepted candidate cannot treat a missing account as fresh generation',
      () async {
    await service().generate();
    noUser = true;
    expect((await service().resume()).phase, VaultKeySetupPhase.unavailable);
    expect(posts, 1);
    expect(fixture.secrets[stageKey], isNotNull);
  });
}
