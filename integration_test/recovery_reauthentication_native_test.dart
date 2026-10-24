import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_recovery_reset.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_lost_recovery.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_reset.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../test/support/recovery_reset_fixture.dart';
import 'support/native_test_install.dart';
import 'support/provider_test_inputs.dart';

/// Run entry, kill this isolated app, then run restart with the same install.
/// HTTP is controlled; SQLite, secure storage and process restarts are native.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native reset reauthentication preserves staging across restart',
      (tester) async {
    await verifyNativeTestInstall();
    final input = (await readNativeProviderInputs()).single as Map;
    final stage = input['stage'] as String;
    final runId = input['runId'] as String;
    expect(['entry', 'restart'], contains(stage));
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    final secure = SecureStorage();
    final documents = await getApplicationDocumentsDirectory();
    final saved = File('${documents.path}/fife-reauth-fixture.json');
    final result = File('${documents.path}/fife-reauth-result.json');
    final peer = RecoveryResetPeer();
    final service = peer.service();

    Future<void> until(bool Function() ready) async {
      final elapsed = Stopwatch()..start();
      while (!ready() && elapsed.elapsed < const Duration(seconds: 45)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> signin(String cookie) async {
      await (await ModelProfile.fromMap(
              {'id': 'fixture-user', 'email': 'fixture@example.test'}))
          .insert();
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      await ModelSetting.set(AppString.localTesting.string, 'yes');
      await ModelSetting.delete(AppString.recoveryReauthentication.string);
      await secure.write(key: AppString.sessionCookie.string, value: cookie);
      await secure.write(
          key: AppString.jwtToken.string, value: 'native-fixture-token');
    }

    if (stage == 'entry') {
      expect(await SessionCleanup.instance.request(), isTrue);
      await signin('native-expired-session-fixture');
      peer.prepareError = 'sign_in_again';
    } else {
      final state = jsonDecode(await saved.readAsString()) as Map;
      expect(state['runId'], runId);
      final raw = await secure.read(key: AppString.recoveryResetStage.string);
      expect(raw != null, isTrue);
      expect(sha256.convert(utf8.encode(raw!)).toString(), state['digest']);
      expect(await secure.read(key: AppString.sessionCookie.string),
          'native-expired-session-fixture');
    }

    final setup = AppSetupState(secure);
    try {
      await setup.recheckStatus();
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: setup,
          child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: stage == 'entry'
                  ? PageLostRecovery(service: service)
                  : PageRecoveryReset(service: service))));
      if (stage == 'entry') {
        await until(
            () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
        await tap(find.text('Continue to reset'));
        await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
        await tap(
            find.widgetWithText(FilledButton, 'Delete vault and start fresh'));
      }
      final signinButton =
          find.widgetWithText(FilledButton, 'Return to sign-in');
      await until(() => signinButton.evaluate().isNotEmpty);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Continue to reset'), findsNothing);
      expect(peer.confirmCalls, 0);
      expect(peer.envelope, isNull);
      final raw = await secure.read(key: AppString.recoveryResetStage.string);
      expect(raw != null, isTrue);
      final before = jsonDecode(raw!) as Map;
      expect(before['signinRequiredForSession'] is String, isTrue);

      if (stage == 'entry') {
        expect(peer.prepareCalls, 1);
        expect(find.textContaining('Sign in again to verify your session'),
            findsOneWidget);
        await saved.writeAsString(
            jsonEncode({
              'runId': runId,
              'digest': sha256.convert(utf8.encode(raw)).toString(),
            }),
            flush: true);
      } else {
        expect(peer.requests, isEmpty);
        expect(find.textContaining('Sign in as'), findsOneWidget);
        await tap(signinButton);
        await until(() => setup.currentStep == SetupStep.signin);
        expect(await secure.read(key: AppString.sessionCookie.string), isNull);
        expect(
            await secure.read(key: AppString.recoveryResetStage.string), raw);
        await tester.pumpWidget(const SizedBox.shrink());
        await signin('native-renewed-session-fixture');
        expect((await peer.service().refresh()).phase,
            RecoveryResetPhase.confirmation);
        expect(peer.confirmCalls, 0);
        expect(
            (await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
        final resumed = jsonDecode(
                (await secure.read(key: AppString.recoveryResetStage.string))!)
            as Map;
        for (final key in [
          'operationId',
          'challenge',
          'privateKeys',
          'serverKeys',
          'deviceUuid'
        ]) {
          expect(
              resumed[key] == before[key] ||
                  jsonEncode(resumed[key]) == jsonEncode(before[key]),
              isTrue,
              reason: 'Reset staging changed at $key');
        }
        expect(peer.prepareCalls, 1);
        expect(peer.confirmCalls, 1);
        expect(await getMasterKey(), isNull);
        expect(await getSignedInUserId(), 'fixture-user');
        expect(await secure.read(key: AppString.sessionCookie.string),
            'native-renewed-session-fixture');
      }
      expect(tester.takeException(), isNull);
      await result.writeAsString(
          jsonEncode({
            'runId': runId,
            'stage': stage,
            'passed': true,
            'nativeStorage': true,
            'httpControlled': true,
          }),
          flush: true);
      debugPrint('Native recovery reauthentication $stage passed');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
    }
  });
}
