// Uses normal bootstrap/auth factories; only platform storage and HTTP transport
// are fixtures. Run with the example NEON_AUTH and API_BASE_URL defines.
import 'dart:convert';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_vault_key_setup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/sync_fixture.dart';

void main() {
  testWidgets(
      'default bootstrap renews tokens after waiting to create and save a phrase',
      (tester) async {
    await tester.runAsync(() async {
      final fixture = await SyncFixture.create();
      const deviceInfo = MethodChannel('dev.fluttercommunity.plus/device_info');
      AppSetupState? setup;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                deviceInfo,
                (_) async => {
                      'computerName': 'Fixture Mac',
                      'hostName': 'fixture',
                      'arch': 'arm64',
                      'model': 'fixture',
                      'modelName': 'fixture',
                      'kernelVersion': 'fixture',
                      'osRelease': 'fixture',
                      'majorVersion': 12,
                      'minorVersion': 0,
                      'patchVersion': 0,
                      'activeCPUs': 1,
                      'memorySize': 1024,
                      'cpuFrequency': 1,
                      'systemGUID': 'fixture-device'
                    });
        for (final key in [
          AppString.masterKey,
          AppString.accessKey,
          AppString.fileHashKey
        ]) {
          fixture.secrets.remove(key.string);
        }
        await ModelSetting.set(AppString.signedIn.string, 'yes');
        await ModelSetting.set(AppString.onboarding.string, 'yes');
        await ModelSetting.delete(AppString.deviceUuid.string);
        const generation = '11111111-1111-4111-8111-111111111111';
        await ModelSetting.set(AppString.vaultGeneration.string, generation);
        String jwt(int offset) =>
            'header.${base64UrlEncode(utf8.encode(jsonEncode({
                  'sub': 'fixture-user',
                  'email': 'fixture@example.test',
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + offset,
                }))).replaceAll('=', '')}.signature';
        final expired = jwt(-60), renewed = jwt(3600);
        fixture.secrets[AppString.jwtToken.string] = expired;
        fixture.secrets[AppString.sessionCookie.string] = 'valid-session';
        final keyBodies = <String>[], deviceBodies = <String>[];
        var renewals = 0;
        Future<http.Response> respond(http.Request request) async {
          if (request.url.path.endsWith('get-session')) {
            renewals++;
            expect(request.headers['cookie'], contains('valid-session'));
            return http.Response(
                '{"session":{"id":"fixture-session"},"user":{"id":"fixture-user"}}',
                200,
                headers: {'set-auth-jwt': renewed});
          }
          expect(request.method, 'POST');
          expect(request.url.path, isIn(['/api/keys', '/api/devices']));
          final keys = request.url.path.endsWith('keys');
          (keys ? keyBodies : deviceBodies).add(request.body);
          if (keys) expect(await getMasterKey(), isNull);
          if (request.headers['authorization'] == 'Bearer $expired') {
            return http.Response('{"success":0,"message":14}', 200);
          }
          expect(request.headers['authorization'], 'Bearer $renewed');
          return http.Response('{"success":1}', 200);
        }

        setup = AppSetupState(SecureStorage());
        await setup.recheckStatus();
        Future<void> until(bool Function() ready) async {
          final elapsed = Stopwatch()..start();
          while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(ready(), isTrue);
        }

        Future<void> mount(Widget page) =>
            tester.pumpWidget(ChangeNotifierProvider.value(
                value: setup!,
                child: MaterialApp(
                    key: ValueKey(page.runtimeType),
                    locale: const Locale('en'),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: page)));

        await http.runWithClient(() async {
          await mount(const PageAccessKeyNotice());
          final generate = find.byType(FilledButton);
          await until(
              () => tester.widget<FilledButton>(generate).onPressed != null);
          await tester.ensureVisible(generate);
          await tester.tap(generate);
          await until(() => setup!.currentStep == SetupStep.showAccessKey);
          expect(renewals, 1);
          expect(keyBodies, hasLength(2));
          expect(keyBodies[0], keyBodies[1]);
          expect(deviceBodies, isEmpty);
          final stage =
              jsonDecode(fixture.secrets[AppString.vaultKeySetupStage.string]!);
          final master = fixture.secrets[AppString.masterKey.string];
          await expectLater(VaultKeySetupService.instance.registrationUuid(),
              throwsStateError);
          await VaultKeySetupService.instance.acknowledge();

          // The user may spend longer than a JWT lifetime saving the words.
          fixture.secrets[AppString.jwtToken.string] = expired;
          await mount(const PageRegisterDevice());
          await until(() => setup!.currentStep == SetupStep.explorer);
          expect(renewals, 2);
          expect(deviceBodies, hasLength(2));
          expect(deviceBodies[0], deviceBodies[1]);
          expect(
              jsonDecode(deviceBodies[0])['device_uuid'], stage['deviceUuid']);
          expect(await getDeviceUuid(), stage['deviceUuid']);
          expect(await VaultKeySetupService.instance.hasPending(), isFalse);
          expect(fixture.secrets[AppString.masterKey.string] == master, isTrue);
          expect(await getSignedInUserId(), 'fixture-user');
          expect((await ModelItem.get('fife'))!.name, 'FiFe');
          expect(tester.takeException(), isNull);
        }, () => MockClient(respond));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        setup?.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(deviceInfo, null);
        await fixture.dispose();
      }
    });
  }, skip: AppEnv.neonAuthUrl.isEmpty || AppEnv.effectiveApiBaseUrl.isEmpty);
}
