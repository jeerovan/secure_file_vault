import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart' show MyApp;
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_vault_key_setup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
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
import 'support/native_http_overrides.dart';
import 'support/provider_test_inputs.dart';
import 'support/iphone_results.dart';

Future<T> _withNativeClient<T>(
    Future<T> Function() action, http.Client Function() createClient) async {
  final previous = HttpOverrides.current;
  final client = createClient();
  AppHttpClients.closeAll();
  HttpOverrides.global = NativeFixtureHttpOverrides(
      (request) async => http.Response.fromStream(await client.send(request)));
  try {
    return await action();
  } finally {
    AppHttpClients.closeAll();
    client.close();
    HttpOverrides.global = previous;
  }
}

/// Entry leaves an expired vault locked. Restart runs in the same isolated app
/// after an actual process kill. Only HTTP is controlled; all storage is native.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recordIphoneResults(binding, 'session-expiry-native', probeBackend: false);
  testWidgets('native normal expiry, restart, same owner and account switch',
      (tester) async {
    var phase = 'verify-install';
    var isolatedInstallVerified = false;
    var completed = false;
    addTearDown(() async {
      if (!isolatedInstallVerified || completed) return;
      try {
        final documents = await getApplicationDocumentsDirectory();
        await File('${documents.path}/fife-session-failure.json').writeAsString(
            jsonEncode({
              'runId': const String.fromEnvironment('FIFE_NATIVE_RUN_ID'),
              'phase': phase,
              'scenarioCompleted': false,
            }),
            flush: true);
      } catch (_) {
        // Preserve the original failure if native diagnostic storage also fails.
        debugPrint('Native session diagnostic could not be written.');
      }
    });
    await verifyNativeTestInstall();
    isolatedInstallVerified = true;
    expect(Uri.parse(AppEnv.effectiveApiBaseUrl).host, 'backend.example.test',
        reason: 'Set LOCAL_API_BASE_URL to the controlled backend host');
    expect(Uri.parse(AppEnv.neonAuthUrl).host, 'auth.example.test');
    phase = 'read-input';
    final input = (await readNativeProviderInputs()).single as Map;
    final stage = input['stage'] as String, runId = input['runId'] as String;
    expect(['entry', 'restart'], contains(stage));
    const reportRunId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
    if (reportRunId.isNotEmpty) expect(runId, reportRunId);
    phase = 'initialize-native-storage';
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
      phase = 'seed-unrelated-vault-preconditions';
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
      phase = 'restore-expired-native-state';
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
      phase = 'setup-and-private-route';
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
        phase = 'controlled-no-session-response';
        await _withNativeClient(() => NeonAuth().refreshSessionAndGetJWT(),
            () => MockClient((_) async => http.Response('null', 200)));
        AppHttpClients.closeAll();
        await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
        expect(find.text('Private native fixture'), findsNothing);
        expect(navigator.mounted, isFalse);
      } else {
        await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
      }
      phase = 'assert-locked-retention';
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
        Future<void> signin(String id, String address,
            {bool rejectBackendOnce = false}) async {
          var rejected = false;
          var otpRequests = 0, verifications = 0;
          final jwt = 'header.${base64UrlEncode(utf8.encode(jsonEncode({
                'sub': id,
                'email': address,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
              }))).replaceAll('=', '')}.signature';
          AppHttpClients.closeAll();
          final auth = NeonAuth();
          await _withNativeClient(() async {
            expect((await auth.sendOTP(address)).statusCode, 200);
            expect(await auth.verifyOTP(address, '123456'), id);
            if (rejectBackendOnce) {
              await expectLater(
                  SessionAuthentication.instance
                      .completeSignin(refreshNeon: auth.refreshForSignin),
                  throwsA(isA<BackendAuthenticationExpired>()));
              expect(SessionWork.authenticationRequired, isTrue);
              expect(
                  (await SessionAuthentication.instance.pendingAccount())?.id,
                  id);
              expect(
                  await storage.read(key: AppString.masterKey.string), master);
              expect(await SessionWork.authenticate(snapshot),
                  (jsonDecode(await saved.readAsString()) as Map)['snapshot']);
            }
            await SessionAuthentication.instance
                .completeSignin(refreshNeon: auth.refreshForSignin);
          },
              () => MockClient((request) async {
                    if (request.url.path.endsWith('/send-verification-otp')) {
                      otpRequests++;
                      return http.Response('{}', 200);
                    }
                    if (request.url.path.endsWith('/email-otp')) {
                      verifications++;
                      return http.Response(
                          jsonEncode({
                            'user': {'id': id, 'email': address}
                          }),
                          200,
                          headers: {
                            'set-cookie':
                                '__Secure-neon-auth.session_token=fresh-native-cookie; Secure; HttpOnly'
                          });
                    }
                    if (request.url.path.endsWith('/get-session')) {
                      return http.Response('{}', 200,
                          headers: {'set-auth-jwt': jwt});
                    }
                    expect(
                        request.url.path, isIn(['/api/keys', '/api/devices']));
                    expect(request.headers['x-fife-session'],
                        'fresh-native-cookie');
                    if (rejectBackendOnce && !rejected) {
                      rejected = true;
                      return http.Response('{"success":0,"message":14}', 403);
                    }
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
                  }));
          expect(otpRequests, 1);
          expect(verifications, 1);
          if (rejectBackendOnce) expect(rejected, isTrue);
        }

        phase = 'same-owner-retry-and-resume';
        await signin(user, email, rejectBackendOnce: true);
        expect(SessionWork.active, isTrue);
        expect(await storage.read(key: AppString.masterKey.string), master);
        expect(await getDeviceUuid(), 'native-device');
        expect(await snapshot(),
            (jsonDecode(await saved.readAsString()) as Map)['snapshot']);
        expect(ModelSetting.foregroundSyncIntervalMinutes, 7);
        expect(await SyncUtils.canSync(), isTrue);
        expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
        phase = 'different-owner-cleanup';
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
        phase = 'default-native-bootstrap';
        await _verifyNativeBootstrap(tester);
      }
      phase = 'write-asserted-result';
      expect(tester.takeException(), isNull);
      await result.writeAsString(
          jsonEncode({
            'runId': runId,
            'stage': stage,
            'passed': true,
            'nativeStorage': true,
            'httpControlled': true,
            'defaultClientConstructors': true,
            'backendDenialRetriedWithoutAnotherOtp': stage == 'restart',
            'nativeBootstrapJwtRenewal': stage == 'restart',
            'nativeBootstrapSameKeyAndDevicePayload': stage == 'restart',
            'nativeBootstrapNoBroadStoragePermission': stage == 'restart'
          }),
          flush: true);
      debugPrint('Native normal session expiry $stage passed');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      AppHttpClients.closeAll();
      setup.dispose();
      locale.dispose();
      if (stage == 'restart') {
        phase = 'fixture-teardown';
        expect(await SessionCleanup.instance.request(), isTrue);
        expect(await storage.read(key: AppString.masterKey.string), isNull);
        expect(await storage.read(key: AppString.sessionCookie.string), isNull);
        expect(await original.readAsString(), 'keep original');
      }
    }
    completed = true;
  });
}

Future<void> _verifyNativeBootstrap(WidgetTester tester) async {
  await verifyNativeTestInstall();
  expect(await SessionCleanup.instance.request(), isTrue);
  final storage = SecureStorage();
  const user = 'native-bootstrap-user';
  const email = 'native-bootstrap@example.test';
  const generation = '11111111-1111-4111-8111-111111111111';
  await (await ModelProfile.fromMap({'id': user, 'email': email})).insert();
  for (final setting in {
    AppString.signedIn: 'yes',
    AppString.onboarding: 'yes',
    AppString.syncWithNotification: 'no',
    AppString.vaultGeneration: generation,
    AppString.localTesting: 'no',
  }.entries) {
    await ModelSetting.set(setting.key.string, setting.value);
  }
  String jwt(int offset) => 'header.${base64UrlEncode(utf8.encode(jsonEncode({
            'sub': user,
            'email': email,
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + offset
          }))).replaceAll('=', '')}.signature';
  final expired = jwt(-60), renewed = jwt(3600);
  await storage.write(key: AppString.jwtToken.string, value: renewed);
  await storage.write(
      key: AppString.sessionCookie.string, value: 'native-bootstrap-cookie');
  final keyBodies = <String>[], deviceBodies = <String>[];
  Map<String, dynamic>? envelope;
  var renewals = 0;
  final setup = AppSetupState(storage);
  Future<void> until(bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 45)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (!ready()) {
      debugPrint('Native bootstrap stopped at ${setup.currentStep.name}; '
          'renewals=$renewals keyPosts=${keyBodies.length} '
          'devicePosts=${deviceBodies.length}');
    }
    expect(ready(), isTrue);
  }

  Future<void> mount(Widget page) => tester.pumpWidget(
      ChangeNotifierProvider.value(
          value: setup,
          child: MaterialApp(
              key: ValueKey(page.runtimeType),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: page)));

  final previousHttpOverrides = HttpOverrides.current;
  HttpOverrides.global = NativeFixtureHttpOverrides((request) async {
    if (request.url.path.endsWith('/get-session')) {
      renewals++;
      expectSync(
          request.headers['cookie'], contains('native-bootstrap-cookie'));
      return http.Response(
          '{"session":{"id":"native-bootstrap"},"user":{"id":"native-bootstrap-user"}}',
          200,
          headers: {'set-auth-jwt': renewed});
    }
    final keys = request.url.path.endsWith('/keys');
    if (request.method == 'GET') {
      expectSync(keys, isTrue);
      return http.Response(
          jsonEncode({
            'success': 1,
            'data': {
              'cipher': envelope?['cipher'],
              'nonce': envelope?['nonce'],
              'key_state': envelope == null ? 'missing' : 'present',
              'vault_generation': generation,
            }
          }),
          200);
    }
    expectSync(request.method, 'POST');
    expectSync(request.url.path, isIn(['/api/keys', '/api/devices']));
    (keys ? keyBodies : deviceBodies).add(request.body);
    if (request.headers['authorization'] == 'Bearer $expired') {
      return http.Response('{"success":0,"message":14}', 200);
    }
    expectSync(request.headers['authorization'], 'Bearer $renewed');
    if (keys) envelope = jsonDecode(request.body);
    return http.Response('{"success":1}', 200);
  });

  try {
    AppHttpClients.closeAll();
    await setup.recheckStatus();
    await (() async {
      await mount(const PageAccessKeyNotice());
      await until(() => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty);
      final generate = find.descendant(
          of: find.byType(PageAccessKeyNotice),
          matching: find.byType(FilledButton));
      await until(
          () => tester.widget<FilledButton>(generate).onPressed != null);
      await storage.write(key: AppString.jwtToken.string, value: expired);
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await until(() => setup.currentStep == SetupStep.showAccessKey);
      expect(renewals, 1);
      expect(keyBodies, hasLength(2));
      expect(keyBodies[0] == keyBodies[1], isTrue);
      expect(deviceBodies, isEmpty);
      final staged = jsonDecode(
          (await storage.read(key: AppString.vaultKeySetupStage.string))!);
      final master = await getMasterKey();
      await expectLater(
          VaultKeySetupService.instance.registrationUuid(), throwsStateError);
      await VaultKeySetupService.instance.acknowledge();
      await storage.write(key: AppString.jwtToken.string, value: expired);
      await mount(const PageRegisterDevice());
      final registeredStep =
          Platform.isAndroid ? SetupStep.storagePermission : SetupStep.explorer;
      await until(() => setup.currentStep == registeredStep);
      expect(renewals, 2);
      expect(deviceBodies, hasLength(2));
      expect(deviceBodies[0] == deviceBodies[1], isTrue);
      expect(await getDeviceUuid(), staged['deviceUuid']);
      expect(await getMasterKey() == master, isTrue);
      expect(await VaultKeySetupService.instance.hasPending(), isFalse);
      expect(await getSignedInUserId(), user);
      expect((await ModelItem.get('fife'))!.name, 'FiFe');
    })();
    expect(tester.takeException(), isNull);
    debugPrint('Native default bootstrap JWT renewal passed');
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    AppHttpClients.closeAll();
    HttpOverrides.global = previousHttpOverrides;
    setup.dispose();
  }
}
