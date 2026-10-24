// Run with --dart-define=NEON_AUTH=https://auth.example.test. All HTTP and
// secure storage are isolated test fixtures; no real account is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async {
    expect(AppEnv.neonAuthUrl, 'https://auth.example.test');
    fixture = await SyncFixture.create();
    fixture.secrets[AppString.sessionCookie.string] = 'unit-session';
  });
  tearDown(() async => fixture.dispose());

  String token(int expiresInSeconds) =>
      'header.${base64UrlEncode(utf8.encode(jsonEncode({
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                expiresInSeconds,
          }))).replaceAll('=', '')}.signature';

  test('unexpired token needs no network request or session mutation',
      () async {
    final current = token(3600);
    fixture.secrets[AppString.jwtToken.string] = current;
    final auth = NeonAuth(httpClient: MockClient((_) async {
      fail('A valid token must not require a network call');
    }));
    await auth.refreshSessionAndGetJWT();
    expect(fixture.secrets[AppString.jwtToken.string], current);
  });

  for (final current in [
    'malformed',
    'header.e30.signature',
    token(30),
    token(-10)
  ]) {
    test('expired, malformed or expiry-free token refreshes from its session',
        () async {
      fixture.secrets[AppString.jwtToken.string] = current;
      var requests = 0;
      final auth = NeonAuth(httpClient: MockClient((request) async {
        requests++;
        expect(request.url.path, '/get-session');
        expect(request.headers['cookie'],
            '__Secure-neon-auth.session_token=unit-session;');
        return http.Response('{}', 200,
            headers: {'Set-Auth-JWT': 'refreshed-token'});
      }));
      await auth.refreshSessionAndGetJWT();
      expect(requests, 1);
      expect(fixture.secrets[AppString.jwtToken.string], 'refreshed-token');
    });
  }

  for (final status in [429, 500, 503]) {
    test('refresh HTTP $status preserves the session, keys and account',
        () async {
      final before = Map.of(fixture.secrets);
      final auth = NeonAuth(
          httpClient: MockClient((_) async => http.Response('', status)));
      await auth.refreshSessionAndGetJWT();
      expect(fixture.secrets, before);
      expect((await ModelProfile.get())?.id, 'fixture-user');
    });
  }

  for (final response in [
    http.Response('{}', 401),
    http.Response('{}', 403),
    http.Response('null', 200),
    http.Response('{"session":null,"user":null}', 200),
    http.Response('null', 200, headers: {'set-auth-jwt': 'contradictory'}),
  ]) {
    test(
        'normal session ${response.statusCode} ${response.body} locks while retaining local vault data',
        () async {
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      final original = await fixture.text('pending.txt', 'external original');
      await fixture.scan();
      final before = await fixture.snapshot();
      expect(before['files'], isNotEmpty);
      expect(before['item_tasks'], isNotEmpty);
      final download = File('${fixture.directory.path}/FiFe/download.txt');
      await download.parent.create(recursive: true);
      await download.writeAsString('app-owned decrypted fixture');
      final part = File('${fixture.directory.path}/${'A' * 43}_1.crypt.ready');
      await part.writeAsString('temporary encrypted fixture');
      final paths = <String>[];
      final master = fixture.secrets[AppString.masterKey.string];
      final auth = NeonAuth(httpClient: MockClient((request) async {
        paths.add(request.url.path);
        return response;
      }));

      await auth.refreshSessionAndGetJWT();

      expect(paths, ['/get-session']);
      expect(fixture.secrets[AppString.masterKey.string], master);
      expect(fixture.secrets[AppString.sessionCookie.string], isNull);
      expect(fixture.secrets[AppString.jwtToken.string], isNull);
      expect(SessionWork.authenticationRequired, isTrue);
      await expectLater(
          SessionWork.run(() async {}), throwsA(isA<SessionInvalidated>()));
      await SessionWork.authenticate(() async {
        expect((await ModelProfile.get())?.id, 'fixture-user');
        expect(await getDeviceUuid(), 'fixture-device-uuid');
        expect(await fixture.snapshot(), before);
      });
      expect(await download.exists(), isTrue);
      expect(await part.exists(), isTrue);
      expect(await original.readAsString(), 'external original');
      final setup = AppSetupState(SecureStorage());
      try {
        await setup.recheckStatus();
        expect(setup.currentStep, SetupStep.signin);
      } finally {
        setup.dispose();
      }
    });
  }

  for (final failure in [
    const SocketException('offline'),
    TimeoutException('timeout')
  ]) {
    test('refresh ${failure.runtimeType} preserves the signed-in account',
        () async {
      final before = Map.of(fixture.secrets);
      final auth = NeonAuth(httpClient: MockClient((_) async => throw failure));
      await auth.refreshSessionAndGetJWT();
      expect(fixture.secrets, before);
      expect((await ModelProfile.get())?.id, 'fixture-user');
    });
  }

  test(
      'concurrent session refreshes share one request and one persisted result',
      () async {
    var requests = 0;
    final entered = Completer<void>();
    final gate = Completer<void>();
    final auth = NeonAuth(httpClient: MockClient((_) async {
      requests++;
      entered.complete();
      await gate.future;
      return http.Response('{}', 200,
          headers: {'set-auth-jwt': 'shared-result'});
    }));
    final calls = [
      auth.refreshSessionAndGetJWT(),
      auth.refreshSessionAndGetJWT(),
      auth.refreshSessionAndGetJWT()
    ];
    await entered.future;
    expect(requests, 1);
    gate.complete();
    await Future.wait(calls);
    expect(fixture.secrets[AppString.jwtToken.string], 'shared-result');
  });

  test(
      'OTP sign-in stages verified identity without replacing active credentials',
      () async {
    final auth = NeonAuth(httpClient: MockClient((request) async {
      if (request.url.path == '/sign-in/email-otp') {
        expect(jsonDecode(request.body),
            {'email': 'fixture@example.test', 'otp': '123456'});
        return http.Response(
            '{"user":{"id":"signed-in-user","email":"fixture@example.test"}}',
            200,
            headers: {
              'set-cookie':
                  '__Secure-neon-auth.session_token=new-session; Secure; HttpOnly'
            });
      }
      expect(request.headers['cookie'], contains('new-session'));
      return http.Response('{}', 200, headers: {'set-auth-jwt': 'new-jwt'});
    }));
    expect(await auth.verifyOTP('fixture@example.test', '123456'),
        'signed-in-user');
    final account = await SessionAuthentication.instance.pendingAccount();
    expect(account?.cookie, 'new-session');
    expect(account?.id, 'signed-in-user');
    expect(account?.email, 'fixture@example.test');
    // Credentials stay separate until ownership/cleanup and backend validation.
    expect(fixture.secrets[AppString.sessionCookie.string], 'unit-session');
  });

  test('OTP rejection never replaces existing authentication material',
      () async {
    final before = Map.of(fixture.secrets);
    final auth =
        NeonAuth(httpClient: MockClient((_) async => http.Response('{}', 401)));
    expect(await auth.verifyOTP('fixture@example.test', 'wrong'), isNull);
    expect(fixture.secrets, before);
  });

  for (final cookie in [null, '']) {
    test('missing or empty refresh cookie retains and locks the vault',
        () async {
      if (cookie == null) {
        fixture.secrets.remove(AppString.sessionCookie.string);
      } else {
        fixture.secrets[AppString.sessionCookie.string] = cookie;
      }
      final master = fixture.secrets[AppString.masterKey.string];
      final auth = NeonAuth(
          httpClient: MockClient((_) async => fail('No refresh cookie')));
      await auth.refreshSessionAndGetJWT();
      expect(SessionWork.authenticationRequired, isTrue);
      expect(fixture.secrets[AppString.masterKey.string], master);
    });
  }

  test(
      'expiry locks private access before waiting for an in-flight database writer',
      () async {
    await SessionCleanup.instance.initialize();
    final entered = Completer<void>(), release = Completer<void>();
    final writer = (await fixture.db).transaction((tx) async {
      await tx.update('profiles', {'username': 'writer'});
      entered.complete();
      await release.future;
    });
    await entered.future;
    final expiry = SessionCleanup.instance.expiredAuthentication();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(SessionWork.active, isFalse);
    } finally {
      release.complete();
      await writer;
      expect(await expiry, isTrue);
    }
    expect(SessionWork.authenticationRequired, isTrue);
    expect(fixture.secrets[AppString.masterKey.string], isNotNull);
  });

  test('fresh sign-in refresh uses the new cookie despite a valid cached JWT',
      () async {
    fixture.secrets[AppString.jwtToken.string] = token(3600);
    final jwt = 'header.${base64UrlEncode(utf8.encode(jsonEncode({
          'sub': 'new-user',
          'email': 'new@example.test',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
        }))).replaceAll('=', '')}.signature';
    final auth = NeonAuth(httpClient: MockClient((request) async {
      expect(request.headers['cookie'],
          '__Secure-neon-auth.session_token=fresh-cookie;');
      return http.Response('{}', 200, headers: {'set-auth-jwt': jwt});
    }));
    expect(
        await auth.refreshForSignin(const AuthenticatedAccount(
            id: 'new-user',
            email: 'new@example.test',
            service: 'neon',
            cookie: 'fresh-cookie')),
        jwt);
    expect(fixture.secrets[AppString.sessionCookie.string], 'unit-session');
    expect(fixture.secrets[AppString.jwtToken.string], isNot(jwt));
  });

  test('provider-verified email mismatch cannot stage a different identity',
      () async {
    final before = Map.of(fixture.secrets);
    final auth = NeonAuth(
        httpClient: MockClient((_) async => http.Response(
                '{"user":{"id":"foreign","email":"foreign@example.test"}}', 200,
                headers: {
                  'set-cookie':
                      '__Secure-neon-auth.session_token=foreign-cookie;'
                })));
    expect(await auth.verifyOTP('fixture@example.test', '123456'), isNull);
    expect(fixture.secrets, before);
    expect(await SessionAuthentication.instance.pendingAccount(), isNull);
  });

  test(
      'a late old-session refresh cannot overwrite reauthenticated credentials',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final oldAuth = NeonAuth(httpClient: MockClient((_) async {
      entered.complete();
      await release.future;
      return http.Response('{}', 200, headers: {'set-auth-jwt': 'retired-jwt'});
    }));
    final oldRefresh = oldAuth.refreshSessionAndGetJWT();
    await entered.future;
    expect(
        await SessionWork.authenticate(
            SessionCleanup.instance.expiredAuthentication),
        isTrue);
    final sessions = SessionAuthentication.instance;
    final attempt = await sessions.beginAttempt();
    await sessions.stageVerified(
        attempt,
        const AuthenticatedAccount(
            id: 'fixture-user',
            email: 'fixture@example.test',
            service: 'neon',
            cookie: 'fresh-cookie'));
    await http.runWithClient(
        () => sessions.completeSignin(refreshNeon: (_) async => 'fresh-jwt'),
        () => MockClient((request) async => http.Response(
            jsonEncode({
              'success': 1,
              'data': request.url.path.endsWith('/keys')
                  ? {
                      'cipher': 'cipher',
                      'nonce': 'nonce',
                      'vault_generation': 'legacy'
                    }
                  : {'id': 'fixture-device-uuid', 'active': 1}
            }),
            200)));
    final rejected =
        expectLater(oldRefresh, throwsA(isA<SessionInvalidated>()));
    release.complete();
    await rejected;
    expect(fixture.secrets[AppString.jwtToken.string], 'fresh-jwt');
    expect(fixture.secrets[AppString.sessionCookie.string], 'fresh-cookie');
    expect(SessionWork.active, isTrue);
  });

  test('OTP request uses the passwordless sign-in payload', () async {
    final auth = NeonAuth(httpClient: MockClient((request) async {
      expect(request.url.path, '/email-otp/send-verification-otp');
      expect(jsonDecode(request.body),
          {'email': 'fixture@example.test', 'type': 'sign-in'});
      return http.Response('{}', 200);
    }));
    expect((await auth.sendOTP('fixture@example.test')).statusCode, 200);
  });

  for (final status in [200, 503]) {
    test(
        'sign-out HTTP $status reports whether the server invalidated the session',
        () async {
      final auth = NeonAuth(httpClient: MockClient((request) async {
        expect(request.url.path, '/sign-out');
        expect(request.headers['cookie'], contains('unit-session'));
        return http.Response('{}', status);
      }));
      expect(await auth.signOut(), status == 200);
    });
  }

  test(
      'a malformed successful refresh cannot erase local keys and account data',
      () async {
    // Simulate the native billing cleanup successfully so it cannot hide a
    // destructive reset behind an unrelated MissingPluginException.
    const purchases = MethodChannel('purchases_flutter');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        purchases, (call) async => call.method == 'isAnonymous' ? true : null);
    addTearDown(() => messenger.setMockMethodCallHandler(purchases, null));
    final before = Map.of(fixture.secrets);
    final auth =
        NeonAuth(httpClient: MockClient((_) async => http.Response('{}', 200)));
    await auth.refreshSessionAndGetJWT();
    expect(fixture.secrets, before);
    expect((await ModelProfile.get())?.id, 'fixture-user');
  });
}
