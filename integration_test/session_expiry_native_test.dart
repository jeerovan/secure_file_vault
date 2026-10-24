import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart' show MyApp;
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'support/native_test_install.dart';
import 'support/provider_test_inputs.dart';

/// Entry leaves an expired vault locked. Restart runs in the same isolated app
/// after an actual process kill. Only HTTP is controlled; all storage is native.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native normal expiry, restart, same owner and account switch',
      (tester) async {
    await verifyNativeTestInstall();
    final input = (await readNativeProviderInputs()).single as Map;
    final stage = input['stage'] as String, runId = input['runId'] as String;
    expect(['entry', 'restart'], contains(stage));
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    final storage = SecureStorage();
    final db = StorageSqlite.instance;
    final docs = await getApplicationDocumentsDirectory();
    final temp = await getTemporaryDirectory();
    final saved = File('${docs.path}/fife-session-fixture.json');
    final result = File('${docs.path}/fife-session-result.json');
    final download = File('${docs.path}/FiFe/native-download.txt');
    final original = File('${docs.path}/fixture-original.txt');
    final part = File('${temp.path}/${'A' * 43}_1.crypt.ready');
    const email = 'native-session@example.test', user = 'native-session-user';
    final master = base64Encode(List<int>.generate(32, (i) => i));

    Future<Map<String, Object>> snapshot() async => {
          for (final table in ['items', 'files', 'parts', 'item_tasks'])
            table: await db.getAll(table),
        };
    Future<void> until(bool Function() ready) async {
      final watch = Stopwatch()..start();
      while (!ready() && watch.elapsed < const Duration(seconds: 45)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue);
    }

    if (stage == 'entry') {
      expect(await SessionCleanup.instance.request(), isTrue);
      await (await ModelProfile.fromMap({'id': user, 'email': email})).insert();
      for (final entry in {
        AppString.signedIn: 'yes',
        AppString.onboarding: 'yes',
        AppString.deviceUuid: 'native-device',
        AppString.deviceHash: 'native-device-hash',
        AppString.vaultGeneration: 'vault-1',
        AppString.syncWithNotification: 'no',
        AppString.foregroundSyncIntervalMinutes: '7',
        AppString.locale: 'de',
      }.entries) {
        await ModelSetting.set(entry.key.string, entry.value);
      }
      for (final entry in {
        AppString.masterKey: master,
        AppString.fileHashKey: master,
        AppString.keyCipher: 'native-cipher',
        AppString.keyNonce: 'native-nonce',
        AppString.jwtToken: 'expired',
        AppString.sessionCookie: 'expired-native-cookie'
      }.entries) {
        await storage.write(key: entry.key.string, value: entry.value);
      }
      await ModelItem.ensureVaultRoot();
      await db.insert('files', {'id': 'native-file', 'parts': 1});
      await db.insert('parts', {'id': 'native-file_1', 'size': 32});
      await db.insert(
          'item_tasks', {'id': 'native-file', 'task': 1, 'state': 'pending'});
      await download.parent.create(recursive: true);
      await download.writeAsString('private native download', flush: true);
      await original.writeAsString('keep original', flush: true);
      await part.writeAsString('native encrypted part fixture', flush: true);
      await saved.writeAsString(
          jsonEncode({'runId': runId, 'snapshot': await snapshot()}),
          flush: true);
    } else {
      expect(SessionWork.authenticationRequired, isTrue);
      expect(SessionWork.active, isFalse);
      final state = jsonDecode(await saved.readAsString()) as Map;
      expect(state['runId'], runId);
      await SessionWork.authenticate(() async {
        expect(await snapshot(), state['snapshot']);
        expect(await getDeviceUuid(), 'native-device');
      });
    }

    final setup = AppSetupState(storage);
    final locale = LocaleProvider();
    try {
      await setup.recheckStatus();
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider.value(value: setup),
        ChangeNotifierProvider.value(value: locale)
      ], child: const MyApp()));
      if (stage == 'entry') {
        await until(() => find.byType(MaterialApp).evaluate().isNotEmpty);
        final navigator = tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .navigatorKey!
            .currentState!;
        unawaited(navigator.push(MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Private native fixture')))));
        await tester.pumpAndSettle();
        final auth = NeonAuth(
            httpClient: MockClient((_) async => http.Response('null', 200)));
        await auth.refreshSessionAndGetJWT();
        await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
        expect(find.text('Private native fixture'), findsNothing);
        expect(navigator.mounted, isFalse);
      } else {
        await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
      }
      expect(SessionWork.authenticationRequired, isTrue);
      expect(await SyncUtils.canSync(), isFalse);
      expect(await storage.read(key: AppString.masterKey.string), master);
      expect(await storage.read(key: AppString.jwtToken.string), isNull);
      expect(await storage.read(key: AppString.sessionCookie.string), isNull);
      expect(await download.exists(), isTrue);
      expect(await part.exists(), isTrue);

      if (stage == 'restart') {
        // No private UI runs during programmatic provider-authenticated fixtures.
        await tester.pumpWidget(const SizedBox.shrink());
        final sessions = SessionAuthentication.test(
            apiFactory: (account, device, generation) => BackendApi(
                baseUrlOverride: 'https://fixture.example.test/api',
                httpClient: MockClient((request) async {
                  expect(
                      request.headers['x-fife-session'], 'fresh-native-cookie');
                  return http.Response(
                      jsonEncode({
                        'success': 1,
                        'data': request.url.path.endsWith('/keys')
                            ? {
                                'cipher': 'native-cipher',
                                'nonce': 'native-nonce',
                                'vault_generation': 'vault-1'
                              }
                            : {'id': 'native-device', 'active': 1}
                      }),
                      200);
                }),
                accessTokenProvider: () async => account.jwt,
                signedEmailIdProvider: () async => account.email,
                deviceUuidProvider: () async => device,
                sessionCookieProvider: () async => account.cookie,
                vaultGenerationOverride: generation,
                localTestingProvider: () => false,
                enforceDeviceRevocation: false,
                requireFreshAuthentication: true,
                refreshAuth: () async {}));
        Future<void> signin(String id, String address) async {
          final jwt = 'header.${base64UrlEncode(utf8.encode(jsonEncode({
                'sub': id,
                'email': address,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
              }))).replaceAll('=', '')}.signature';
          final auth = NeonAuth(
              httpClient: MockClient((request) async => request.url.path
                      .endsWith('/email-otp')
                  ? http.Response(
                      jsonEncode({
                        'user': {'id': id, 'email': address}
                      }),
                      200,
                      headers: {
                          'set-cookie':
                              '__Secure-neon-auth.session_token=fresh-native-cookie; Secure; HttpOnly'
                        })
                  : http.Response('{}', 200, headers: {'set-auth-jwt': jwt})));
          expect(await auth.verifyOTP(address, '123456'), id);
          await sessions.completeSignin(refreshNeon: auth.refreshForSignin);
        }

        await signin(user, email);
        expect(SessionWork.active, isTrue);
        expect(await storage.read(key: AppString.masterKey.string), master);
        expect(await getDeviceUuid(), 'native-device');
        expect(await snapshot(),
            (jsonDecode(await saved.readAsString()) as Map)['snapshot']);
        expect(ModelSetting.foregroundSyncIntervalMinutes, 7);
        expect(await SyncUtils.canSync(), isTrue);
        expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
        await signin('different-native-user', 'different-native@example.test');
        expect(await getSignedInUserId(), 'different-native-user');
        expect(await getMasterKey(), isNull);
        expect(await getDeviceUuid(), isEmpty);
        expect(await ModelSetting.getRaw(AppString.locale.string), 'de');
        for (final table in ['files', 'parts', 'item_tasks']) {
          expect(await db.getAll(table), isEmpty);
        }
        expect(await download.exists(), isFalse);
        expect(await part.exists(), isFalse);
        expect(await original.readAsString(), 'keep original');
        expect(await storage.read(key: AppString.sessionCookie.string),
            'fresh-native-cookie');
      }
      expect(tester.takeException(), isNull);
      await result.writeAsString(
          jsonEncode({
            'runId': runId,
            'stage': stage,
            'passed': true,
            'nativeStorage': true,
            'httpControlled': true
          }),
          flush: true);
      debugPrint('Native normal session expiry $stage passed');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
    }
  });
}
