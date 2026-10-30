// Isolated authentication UI. Run with:
// --dart-define=NEON_AUTH=https://auth.example.test
// --dart-define=API_BASE_URL=https://backend.example.test
// API_BASE_URL is the origin; BackendApi appends /api itself.
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/sync_fixture.dart';

void main() {
  testWidgets(
      'expired-session email can change; verified new owner clears old vault before activation',
      (tester) async {
    await tester.runAsync(() async {
      final fixture = await SyncFixture.create();
      AppSetupState? setup;
      try {
        await ModelItem.ensureVaultRoot();
        await ModelSetting.set(AppString.signedIn.string, 'yes');
        await ModelSetting.set(AppString.onboarding.string, 'yes');
        final original = await fixture.text('pending.txt', 'external original');
        await fixture.scan();
        final download = File('${fixture.directory.path}/FiFe/download.txt');
        await download.parent.create(recursive: true);
        await download.writeAsString('old private download');
        final part =
            File('${fixture.directory.path}/${'A' * 43}_1.crypt.ready');
        await part.writeAsString('old encrypted upload part');
        final master = fixture.secrets[AppString.masterKey.string];
        final oldState = await fixture.snapshot();
        expect(oldState['item_tasks'], isNotEmpty);
        expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
        setup = AppSetupState(SecureStorage());
        await setup.recheckStatus();
        expect(setup.currentStep, SetupStep.signin);

        const nextEmail = 'other@example.test', nextId = 'other-verified-user';
        var otpAccepted = false, backendOnline = false, activationChecks = 0;
        final jwt = 'header.${base64UrlEncode(utf8.encode(jsonEncode({
              'sub': nextId,
              'email': nextEmail,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            }))).replaceAll('=', '')}.signature';
        Future<void> retained() async {
          expect(SessionWork.authenticationRequired, isTrue);
          expect(fixture.secrets[AppString.masterKey.string], master);
          await SessionWork.authenticate(() async {
            expect((await ModelProfile.get())?.id, 'fixture-user');
            expect(await fixture.snapshot(), oldState);
          });
          expect(await download.exists(), isTrue);
          expect(await part.exists(), isTrue);
          expect(await original.readAsString(), 'external original');
        }

        fixture.beforeWrite = (key, _) async {
          if (key == AppString.sessionCookie.string ||
              key == AppString.jwtToken.string) {
            activationChecks++;
            expect(fixture.secrets[AppString.masterKey.string], isNull);
            final db = await StorageSqlite.instance.executor;
            expect(await db.query('item_tasks'), isEmpty);
            expect(await db.query('files'), isEmpty);
            expect(await download.exists(), isFalse);
            expect(await part.exists(), isFalse);
            expect(SessionWork.authenticationRequired, isTrue);
          }
        };
        Future<http.Response> respond(http.Request request) async {
          if (request.url.path.endsWith('send-verification-otp')) {
            expect(jsonDecode(request.body)['email'], nextEmail);
            await retained();
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('email-otp')) {
            expect(jsonDecode(request.body)['email'], nextEmail);
            await retained();
            return http.Response(
                otpAccepted
                    ? jsonEncode({
                        'user': {'id': nextId, 'email': nextEmail}
                      })
                    : '{}',
                otpAccepted ? 200 : 401,
                headers: otpAccepted
                    ? {
                        'set-cookie':
                            '__Secure-neon-auth.session_token=other-cookie; Secure; HttpOnly'
                      }
                    : {});
          }
          if (request.url.path.endsWith('get-session')) {
            expect(request.headers['cookie'], contains('other-cookie'));
            return http.Response('{}', 200, headers: {'set-auth-jwt': jwt});
          }
          expect(request.url.path, '/api/keys');
          expect(request.headers['authorization'], 'Bearer $jwt');
          expect(request.headers['device_uuid'], isNull);
          return http.Response(
              jsonEncode(backendOnline
                  ? {
                      'success': 1,
                      'data': {
                        'cipher': 'other-cipher',
                        'nonce': 'other-nonce',
                        'vault_generation': 'other-vault'
                      }
                    }
                  : {'success': 0}),
              backendOnline ? 200 : 503);
        }

        await http.runWithClient(() async {
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: setup,
              child: MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: const PageSignin())));
          Future<void> until(bool Function() ready) async {
            for (var i = 0; i < 300 && !ready(); i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(ready(), isTrue);
          }

          Future<void> tap(String label) async {
            final button = find.widgetWithText(FilledButton, label);
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pump();
          }

          await until(() => tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text
              .isNotEmpty);
          final field =
              tester.widget<TextFormField>(find.byType(TextFormField));
          expect(field.controller!.text, 'fixture@example.test');
          expect(field.enabled, isNot(false));
          expect(
              tester.widget<EditableText>(find.byType(EditableText)).readOnly,
              isFalse);
          await tester.enterText(find.byType(TextFormField), nextEmail);
          await retained();
          await tap('Send OTP');
          await until(() => find.text('Verify OTP').evaluate().isNotEmpty);
          await tester.enterText(find.byType(TextFormField), '000000');
          await tap('Verify OTP');
          await until(
              () => find.text('Retry Verification').evaluate().isNotEmpty);
          await retained();
          expect(activationChecks, 0);
          otpAccepted = true;
          await tester.enterText(find.byType(TextFormField), '123456');
          await tap('Retry Verification');
          await until(() => find
              .text('Your email is verified. Continue to finish signing in.')
              .evaluate()
              .isNotEmpty);
          await retained();
          expect(activationChecks, 0);
          backendOnline = true;
          await tap('Continue');
          await until(() => setup!.currentStep == SetupStep.checkAccessKey);
          expect(activationChecks, 2);
          expect(SessionWork.authenticationRequired, isFalse);
          expect((await ModelProfile.get())?.id, nextId);
          expect((await ModelProfile.get())?.email, nextEmail);
          expect(
              fixture.secrets[AppString.sessionCookie.string], 'other-cookie');
          expect(fixture.secrets[AppString.masterKey.string], isNull);
          expect(
              await ModelSetting.getRaw(AppString.deviceUuid.string), isEmpty);
          expect((await fixture.snapshot())['files'], isEmpty);
          expect((await fixture.snapshot())['item_tasks'], isEmpty);
          expect(await download.exists(), isFalse);
          expect(await part.exists(), isFalse);
          expect(await original.readAsString(), 'external original');
          expect(tester.takeException(), isNull);
        }, () => MockClient(respond));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        setup?.dispose();
        await fixture.dispose();
      }
    });
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets('retained verified sign-in fits large text at 320px in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final fixture = await SyncFixture.create();
        try {
          expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
          final sessions = SessionAuthentication.instance;
          final attempt = await sessions.beginAttempt();
          await sessions.stageVerified(
              attempt,
              const AuthenticatedAccount(
                  id: 'fixture-user',
                  email: 'fixture@example.test',
                  service: 'neon',
                  cookie: 'verified-cookie'));
          await tester.pumpWidget(MaterialApp(
              locale: locale,
              theme: ThemeData.dark(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: const PageSignin()));
          final loc =
              AppLocalizations.of(tester.element(find.byType(PageSignin)))!;
          for (var i = 0;
              i < 100 &&
                  find.text(loc.signinVerifiedContinue).evaluate().isEmpty;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
          expect(find.text(loc.signinVerifiedContinue), findsOneWidget);
          await tester.ensureVisible(find.text(loc.continueLabel));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(FilledButton, loc.continueLabel),
              findsOneWidget);
          expect(
              Directionality.of(tester.element(find.byType(PageSignin))),
              locale.languageCode == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await fixture.dispose();
        }
      });
    });
  }

  for (final backendFailureStatus in [503, 401, 403, 200]) {
    testWidgets(
        'default clients resume retained vault after wrong OTP and backend $backendFailureStatus validation retry',
        (tester) async {
      await tester.runAsync(() async {
        final fixture = await SyncFixture.create();
        AppSetupState? setup;
        try {
          await ModelItem.ensureVaultRoot();
          await ModelSetting.set(AppString.signedIn.string, 'yes');
          await ModelSetting.set(AppString.onboarding.string, 'yes');
          final master = fixture.secrets[AppString.masterKey.string];
          expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
          setup = AppSetupState(SecureStorage());
          await setup.recheckStatus();
          var otpAccepted = false, backendOnline = false;
          var otpRequests = 0, verifications = 0;
          final jwt = 'header.${base64UrlEncode(utf8.encode(jsonEncode({
                'sub': 'fixture-user',
                'email': 'fixture@example.test',
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }))).replaceAll('=', '')}.signature';
          Future<http.Response> respond(http.Request request) async {
            if (request.url.path.endsWith('send-verification-otp')) {
              otpRequests++;
              return http.Response('{}', otpRequests == 1 ? 503 : 200);
            }
            if (request.url.path.endsWith('email-otp')) {
              verifications++;
              return http.Response(
                  otpAccepted
                      ? '{"user":{"id":"fixture-user","email":"fixture@example.test"}}'
                      : '{}',
                  otpAccepted ? 200 : 401,
                  headers: otpAccepted
                      ? {
                          'set-cookie':
                              '__Secure-neon-auth.session_token=new-cookie; Secure; HttpOnly'
                        }
                      : {});
            }
            if (request.url.path.endsWith('get-session')) {
              expect(request.headers['cookie'], contains('new-cookie'));
              return http.Response('{}', 200, headers: {'set-auth-jwt': jwt});
            }
            expect(request.url.path, isIn(['/api/keys', '/api/devices']));
            expect(request.headers['authorization'], 'Bearer $jwt');
            return http.Response(
                jsonEncode(!backendOnline
                    ? {
                        'success': 0,
                        if (backendFailureStatus == 200) 'message': 14
                      }
                    : {
                        'success': 1,
                        'data': request.url.path.endsWith('keys')
                            ? {
                                'cipher': 'cipher',
                                'nonce': 'nonce',
                                'vault_generation': 'legacy'
                              }
                            : {'id': 'fixture-device-uuid', 'active': 1}
                      }),
                backendOnline ? 200 : backendFailureStatus);
          }

          await http.runWithClient(() async {
            await tester.pumpWidget(ChangeNotifierProvider.value(
                value: setup,
                child: MaterialApp(
                    locale: const Locale('en'),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: const PageSignin())));
            Future<void> until(bool Function() ready) async {
              for (var i = 0; i < 300 && !ready(); i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(ready(), isTrue);
            }

            Future<void> tap(String text) async {
              final button = find.widgetWithText(FilledButton, text);
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pump();
            }

            await until(() => tester
                .widget<TextFormField>(find.byType(TextFormField))
                .controller!
                .text
                .isNotEmpty);
            await tap('Send OTP');
            await until(
                () => find.text('Retry Sending OTP').evaluate().isNotEmpty);
            expect(fixture.secrets[AppString.masterKey.string], master);
            expect(SessionWork.authenticationRequired, isTrue);
            await tap('Retry Sending OTP');
            await until(() => find.text('Verify OTP').evaluate().isNotEmpty);
            await tester.enterText(find.byType(TextFormField), '000000');
            await tap('Verify OTP');
            await until(() => find
                .text('OTP verification failed. Please try again.')
                .evaluate()
                .isNotEmpty);
            expect(fixture.secrets[AppString.masterKey.string], master);
            expect(SessionWork.authenticationRequired, isTrue);
            otpAccepted = true;
            await tester.enterText(find.byType(TextFormField), '123456');
            await tap('Retry Verification');
            await until(() => find
                .text('Your email is verified. Continue to finish signing in.')
                .evaluate()
                .isNotEmpty);
            expect(fixture.secrets[AppString.sessionCookie.string], isNull);
            expect(fixture.secrets[AppString.masterKey.string], master);
            expect(SessionWork.authenticationRequired, isTrue);
            expect(await SessionAuthentication.instance.pendingAccount(),
                isNotNull);
            backendOnline = true;
            await tap('Continue');
            await until(() => setup!.currentStep == SetupStep.explorer);
            expect(verifications, 2);
            expect(otpRequests, 2);
            expect(SessionWork.authenticationRequired, isFalse);
            expect(
                fixture.secrets[AppString.sessionCookie.string], 'new-cookie');
            expect(fixture.secrets[AppString.masterKey.string], master);
            expect(tester.takeException(), isNull);
          }, () => MockClient(respond));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          setup?.dispose();
          await fixture.dispose();
        }
      });
    });
  }
}
