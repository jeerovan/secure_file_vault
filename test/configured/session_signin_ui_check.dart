// Isolated authentication UI, run with NEON_AUTH=https://auth.example.test.
import 'dart:convert';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_authentication.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
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
