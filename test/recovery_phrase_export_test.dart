import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_recovery_phrase.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_lock_fixture.dart';
import 'support/sync_fixture.dart';

final syntheticRecoveryPhrase = '${List.filled(23, 'abandon').join(' ')} art';

class RecoveryPlatformProbe implements RecoveryPhrasePlatform {
  final copied = <String>[];
  final saved = <String>[];
  bool saveResult = true;
  Future<String?> Function()? onReserve;
  Future<bool> Function()? onSave;
  @override
  Future<void> copy(String phrase) async => copied.add(phrase);
  @override
  Future<String?> reserveSave() async =>
      onReserve == null ? 'reservation' : onReserve!();
  @override
  Future<bool> save(String phrase, String title, String? reservation) async {
    saved.add(phrase);
    return onSave == null ? saveResult : onSave!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryAppLockStore store;
  late FakeAppLockAuthenticator auth;
  late AppLockController lock;
  late RecoveryPlatformProbe platform;
  setUp(() {
    SessionWork.resetForTesting();
    store = MemoryAppLockStore()..enabled = true;
    auth = FakeAppLockAuthenticator();
    lock = AppLockController(store: store, authenticator: auth);
    platform = RecoveryPlatformProbe();
  });
  tearDown(() {
    lock.dispose();
    SessionWork.resetForTesting();
  });

  Future<AppLockAuthorization> authorize() async {
    await lock.load();
    expect(await lock.unlock(testAppLockPrompt), isTrue);
    return (await lock.authorizeSensitiveAction(testAppLockPrompt))!;
  }

  RecoveryPhraseService service(
          {Future<String?> Function()? read,
          Future<bool> Function()? signedIn}) =>
      RecoveryPhraseService(
          readAccessKey: read ?? (() async => base64Encode(Uint8List(32))),
          signedIn: signedIn ?? (() async => true),
          platform: platform);

  test(
      'sensitive access always prompts again inside the normal unlock grace period',
      () async {
    final first = await authorize();
    expect(auth.attempts, 2);
    final second = await lock.authorizeSensitiveAction(testAppLockPrompt);
    expect(auth.attempts, 3);
    expect(first.isValid, isFalse);
    expect(second?.available, isTrue);
    expect(store.enabled, isTrue);
    expect(store.minutes, 5);
  });

  test(
      'off, locked, unsupported and canceled authentication grant no export access',
      () async {
    store.enabled = false;
    await lock.load();
    expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
    expect(auth.attempts, 0);
    store.enabled = true;
    await lock.load();
    expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
    await lock.unlock(testAppLockPrompt);
    auth.supported = false;
    expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
    auth.supported = true;
    auth.result = false;
    expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
    expect(lock.locked, isFalse);
    expect(platform.copied, isEmpty);
  });

  test('concurrent sensitive action cannot reuse an outstanding authentication',
      () async {
    await authorize();
    final pending = Completer<bool>();
    auth.onAuthenticate = (_) => pending.future;
    final first = lock.authorizeSensitiveAction(testAppLockPrompt);
    expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
    pending.complete(true);
    expect((await first)?.available, isTrue);
  });

  test('a late success for a retired session grants nothing', () async {
    await authorize();
    final pending = Completer<bool>();
    auth.onAuthenticate = (_) => pending.future;
    final operation = lock.authorizeSensitiveAction(testAppLockPrompt);
    await Future<void>.delayed(Duration.zero);
    SessionWork.invalidate('retired-owner');
    lock.invalidateSession();
    SessionWork.complete('replacement-owner');
    pending.complete(true);
    expect(await operation, isNull);
  });

  test(
      'successful native inactive completion stays unavailable until foreground',
      () async {
    await authorize();
    auth.onAuthenticate = (_) async {
      lock.handleLifecycle(AppLifecycleState.inactive);
      return true;
    };
    final proof = (await lock.authorizeSensitiveAction(testAppLockPrompt))!;
    expect(proof.isValid, isTrue);
    expect(proof.available, isFalse);
    await expectLater(
        service().read(proof), throwsA(isA<AppLockAccessDenied>()));
    lock.handleLifecycle(AppLifecycleState.resumed);
    expect(await service().read(proof), syntheticRecoveryPhrase);
  });

  test(
      'an authentication hold denies export even in the public auth zone with the same revision',
      () async {
    final proof = await authorize();
    SessionWork.complete(SessionWork.revision, authenticationRequired: true);
    await SessionWork.authenticate(() async {
      expect(proof.isValid, isFalse);
      expect(await lock.authorizeSensitiveAction(testAppLockPrompt), isNull);
      await expectLater(
          service().read(proof), throwsA(isA<AppLockAccessDenied>()));
    });
  });

  for (final authRequired in [false, true]) {
    test(
        'retired or authentication-held state ($authRequired) rejects existing proof',
        () async {
      final proof = await authorize();
      SessionWork.complete('next', authenticationRequired: authRequired);
      await expectLater(
          service().read(proof),
          throwsA(
              anyOf(isA<SessionInvalidated>(), isA<AppLockAccessDenied>())));
      await expectLater(
          service().copy(proof, syntheticRecoveryPhrase),
          throwsA(
              anyOf(isA<SessionInvalidated>(), isA<AppLockAccessDenied>())));
      expect(platform.copied, isEmpty);
    });
  }

  test(
      'loads the exact BIP39 words from existing recovery entropy, not the master key',
      () async {
    final proof = await authorize();
    expect(await service().read(proof), syntheticRecoveryPhrase);
    expect(platform.saved, isEmpty);
  });

  for (final encoded in [
    null,
    '',
    'invalid secret input !',
    base64Encode(Uint8List(16)),
    base64Encode(Uint8List(33))
  ]) {
    test(
        'missing or malformed entropy is unavailable without generating replacement keys ($encoded)',
        () async {
      final proof = await authorize();
      await expectLater(service(read: () async => encoded).read(proof),
          throwsA(isA<RecoveryPhraseUnavailable>()));
      expect(platform.saved, isEmpty);
    });
  }

  test('signed-out state never reads private entropy', () async {
    var reads = 0;
    final proof = await authorize();
    await expectLater(
        service(
            read: () async {
              reads++;
              return null;
            },
            signedIn: () async => false).read(proof),
        throwsA(isA<AppLockAccessDenied>()));
    expect(reads, 0);
  });

  test(
      'interrupted key read cannot publish data after the view proof is revoked',
      () async {
    final key = Completer<String?>();
    final proof = await authorize();
    final reading = service(read: () => key.future).read(proof);
    await Future<void>.delayed(Duration.zero);
    proof.revoke();
    key.complete(base64Encode(Uint8List(32)));
    await expectLater(reading, throwsA(isA<AppLockAccessDenied>()));
  });

  test('cleanup between native reservation and save prevents plaintext handoff',
      () async {
    final proof = await authorize();
    platform.onReserve = () async {
      SessionWork.invalidate('cleanup-started');
      return 'old-reservation';
    };
    await expectLater(service().save(proof, syntheticRecoveryPhrase, 'Save'),
        throwsA(isA<SessionInvalidated>()));
    expect(platform.saved, isEmpty);
  });

  test(
      'canceled save is not reported as successful and original phrase stays intact',
      () async {
    final proof = await authorize();
    platform.saveResult = false;
    expect(
        await service().save(proof, syntheticRecoveryPhrase, 'Save'), isFalse);
    expect(await service().read(proof), syntheticRecoveryPhrase);
  });

  for (final fails in [false, true]) {
    test('native save always clears staging and byte buffer (failure=$fails)',
        () async {
      var clears = 0;
      var releases = 0;
      Uint8List? handedOff;
      final native =
          NativeRecoveryPhrasePlatform(clearTemporaryFiles: () async {
        clears++;
      }, releaseTemporaryFiles: (reservation) async {
        releases++;
      }, saveFile: (bytes, title, reservation) async {
        handedOff = bytes;
        expect(utf8.decode(bytes), syntheticRecoveryPhrase);
        if (fails) throw StateError('synthetic platform failure');
        return true;
      });
      await native.reserveSave();
      if (fails) {
        await expectLater(native.save(syntheticRecoveryPhrase, 'Save', null),
            throwsStateError);
      } else {
        expect(
            await native.save(syntheticRecoveryPhrase, 'Save', null), isTrue);
      }
      expect(clears, 1);
      expect(releases, 1);
      expect(handedOff, everyElement(0));
    });
  }

  test(
      'native clipboard uses protected transport without an unprotected fallback',
      () async {
    const channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await NativeRecoveryPhrasePlatform().copy(syntheticRecoveryPhrase);
    expect(calls.single.method, 'copyRecoveryPhrase');
    expect(calls.single.arguments, syntheticRecoveryPhrase);
  });

  test(
      'default service reads real fixture key storage and preserves all keys/settings',
      () async {
    final fixture = await SyncFixture.create();
    try {
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      final storage = SecureStorage();
      final access = base64Encode(Uint8List(32));
      final master = base64Encode(Uint8List.fromList(List.filled(32, 7)));
      await storage.write(key: AppString.accessKey.string, value: access);
      await storage.write(key: AppString.masterKey.string, value: master);
      final proof = await authorize();
      expect(
          await RecoveryPhraseService().read(proof), syntheticRecoveryPhrase);
      expect(await storage.read(key: AppString.accessKey.string), access);
      expect(await storage.read(key: AppString.masterKey.string), master);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
    } finally {
      await fixture.dispose();
    }
  });
}
