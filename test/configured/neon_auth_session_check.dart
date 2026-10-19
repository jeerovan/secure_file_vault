// Run with --dart-define=NEON_AUTH=https://auth.example.test. All HTTP and
// secure storage are isolated test fixtures; no real account is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_auth.dart';
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

  test('OTP sign-in stores the cookie and obtains an authenticated JWT',
      () async {
    final auth = NeonAuth(httpClient: MockClient((request) async {
      if (request.url.path == '/sign-in/email-otp') {
        expect(jsonDecode(request.body),
            {'email': 'fixture@example.test', 'otp': '123456'});
        return http.Response('{"user":{"id":"signed-in-user"}}', 200, headers: {
          'set-cookie':
              '__Secure-neon-auth.session_token=new-session; Secure; HttpOnly'
        });
      }
      expect(request.headers['cookie'], contains('new-session'));
      return http.Response('{}', 200, headers: {'set-auth-jwt': 'new-jwt'});
    }));
    expect(await auth.verifyOTP('fixture@example.test', '123456'),
        'signed-in-user');
    expect(fixture.secrets[AppString.sessionCookie.string], 'new-session');
    expect(fixture.secrets[AppString.jwtToken.string], 'new-jwt');
  });

  test('OTP rejection never replaces existing authentication material',
      () async {
    final before = Map.of(fixture.secrets);
    final auth =
        NeonAuth(httpClient: MockClient((_) async => http.Response('{}', 401)));
    expect(await auth.verifyOTP('fixture@example.test', 'wrong'), isNull);
    expect(fixture.secrets, before);
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
