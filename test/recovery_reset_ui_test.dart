import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_vault_key_setup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_check.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_display.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_lost_recovery.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_reset.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/recovery_reset_fixture.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late RecoveryResetPeer peer;
  setUp(() async {
    fixture = await SyncFixture.create();
    peer = RecoveryResetPeer();
    fixture.secrets.remove(AppString.masterKey.string);
    fixture.secrets.remove(AppString.fileHashKey.string);
    fixture.secrets[AppString.sessionCookie.string] = 'fixture-cookie';
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.recoveryResetAvailable.string, 'yes');
    await ModelSetting.delete(AppString.deviceUuid.string);
  });
  tearDown(() async => fixture.dispose());

  Future<void> ioFrames(WidgetTester tester, bool Function() ready) async {
    // SQLite/key-store I/O is real; a frame-count limit is not a latency
    // requirement and flakes while native builds compete for the same disk.
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  Future<AppSetupState> mount(WidgetTester tester, Widget page,
      {Locale locale = const Locale('en'),
      Brightness brightness = Brightness.light,
      bool largeText = false}) async {
    final setup = (await tester.runAsync(() async {
      final state = AppSetupState(SecureStorage());
      await state.recheckStatus();
      return state;
    }))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: setup,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(largeText ? 2 : 1),
                    disableAnimations: true),
                child: child!),
            home: page,
          )));
    });
    await tester.pump();
    if (page is PageLostRecovery && peer.beforeStatus == null) {
      await ioFrames(tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
    }
    return setup;
  }

  Future<void> mountWithControlledTimers(WidgetTester tester) async {
    final setup = await mount(tester, const SizedBox.shrink());
    // Start the periodic timer in the widget test's controlled timer zone.
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: setup,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PageRecoveryReset(service: peer.service()),
        )));
  }

  Finder readinessRetry() => find.ancestor(
      of: find.text('Try Again'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton));

  testWidgets('lost phrase explains fifteen minutes and verified deletion',
      (tester) async {
    await mount(tester, PageLostRecovery(service: peer.service()));
    expect(find.textContaining('15 minutes or longer'), findsOneWidget);
    expect(find.textContaining('until cloud deletion is verified'),
        findsOneWidget);
    expect(find.textContaining('24 hours'), findsNothing);
    expect(peer.requests, ['GET /api/recovery-reset/status']);
  });

  testWidgets(
      'opening and canceling lost phrase preserves words with only a readiness read',
      (tester) async {
    await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
    await tester.enterText(
        find.byType(TextFormField), 'partially entered recovery words');
    await tester.ensureVisible(find.text('Lost recovery phrase'));
    await tester.tap(find.text('Lost recovery phrase'));
    await tester.pump();
    await ioFrames(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(PageLostRecovery), findsOneWidget);
    expect(peer.requests, ['GET /api/recovery-reset/status']);
    await tester.ensureVisible(find.text('Continue to reset'));
    await tester.tap(find.text('Continue to reset'));
    await tester.tap(find.text('Continue to reset'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final input = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(input.controller!.text, 'partially entered recovery words');
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
    expect(peer.requests, ['GET /api/recovery-reset/status']);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    expect(tester.takeException(), isNull);
  });

  for (final setting in [
    AppString.recoveryResetAvailable,
    AppString.simulateTesting,
    AppString.localTesting
  ]) {
    testWidgets('reset entry visibility with ${setting.name}', (tester) async {
      await tester.runAsync(() => ModelSetting.set(setting.string,
          setting == AppString.recoveryResetAvailable ? 'no' : 'yes'));
      await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
      expect(find.text('Lost recovery phrase'),
          setting == AppString.simulateTesting ? findsNothing : findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(peer.requests, isEmpty);
    });
  }

  testWidgets('reset entry remains visible when availability is unknown',
      (tester) async {
    await tester.runAsync(
        () => ModelSetting.delete(AppString.recoveryResetAvailable.string));
    await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
    expect(find.text('Lost recovery phrase'), findsOneWidget);
    expect(peer.requests, isEmpty);
  });

  testWidgets(
      'unavailable reset explains the disabled action and preserves words',
      (tester) async {
    peer.available = false;
    await tester.runAsync(
        () => ModelSetting.set(AppString.recoveryResetAvailable.string, 'no'));
    await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
    await tester.enterText(
        find.byType(TextFormField), 'unfinished recovery words');
    await tester.ensureVisible(find.text('Lost recovery phrase'));
    await tester.tap(find.text('Lost recovery phrase'));
    await tester.pump();
    await ioFrames(tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(
        find.text('Vault reset is temporarily unavailable. Try again later.'),
        findsOneWidget);
    final continueButton =
        find.widgetWithText(FilledButton, 'Continue to reset');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(peer.requests, ['GET /api/recovery-reset/status']);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'unfinished recovery words');
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readiness retry enables confirmation without preparing a reset',
      (tester) async {
    await tester.runAsync(
        () => ModelSetting.set(AppString.recoveryResetAvailable.string, 'no'));
    peer.available = false;
    await mount(tester, PageLostRecovery(service: peer.service()));
    peer.available = true;
    final release = Completer<void>();
    peer.beforeStatus = () => release.future;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final retry = readinessRetry();
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.tap(retry);
    await ioFrames(tester, () => peer.statusCalls == 2);
    expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);
    release.complete();
    final continueButton =
        find.widgetWithText(FilledButton, 'Continue to reset');
    await ioFrames(tester,
        () => tester.widget<FilledButton>(continueButton).onPressed != null);
    expect(ModelSetting.get(AppString.recoveryResetAvailable.string), 'yes');
    expect(peer.statusCalls, 2);
    expect(peer.requests, List.filled(2, 'GET /api/recovery-reset/status'));
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(peer.prepareCalls, 0);
    expect(peer.confirmCalls, 0);
  });

  for (final available in [true, false]) {
    testWidgets('entry replaces stale availability with live value $available',
        (tester) async {
      await tester.runAsync(() => ModelSetting.set(
          AppString.recoveryResetAvailable.string, available ? 'no' : 'yes'));
      peer.available = available;
      await mount(tester, PageLostRecovery(service: peer.service()));
      final action = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continue to reset'));
      expect(action.onPressed != null, available);
      expect(ModelSetting.get(AppString.recoveryResetAvailable.string),
          available ? 'yes' : 'no');
      expect(peer.requests, ['GET /api/recovery-reset/status']);
      expect(peer.prepareCalls, 0);
      expect(peer.confirmCalls, 0);
      expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    });
  }

  for (final offline in [false, true]) {
    testWidgets('readiness retry keeps reset disabled when offline=$offline',
        (tester) async {
      await tester.runAsync(() =>
          ModelSetting.set(AppString.recoveryResetAvailable.string, 'no'));
      peer.available = false;
      peer.offline = offline;
      await mount(tester, PageLostRecovery(service: peer.service()));
      final retry = readinessRetry();
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      await ioFrames(
          tester, () => tester.widget<OutlinedButton>(retry).onPressed != null);
      final continueButton =
          find.widgetWithText(FilledButton, 'Continue to reset');
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      expect(
          find.text('Vault reset is temporarily unavailable. Try again later.'),
          findsOneWidget);
      expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
      expect(peer.prepareCalls, 0);
      expect(peer.confirmCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final error in ['sign_in_again', '14', '18']) {
    testWidgets(
        'entry checks authentication error $error and offers sign-in, not an outage',
        (tester) async {
      await tester.runAsync(() =>
          ModelSetting.set(AppString.recoveryResetAvailable.string, 'no'));
      peer.statusError = error;
      final setup =
          await mount(tester, PageLostRecovery(service: peer.service()));
      expect(peer.statusCalls, greaterThan(0));
      expect(
          find.text(
              'Sign in again to verify your session before resetting the vault.'),
          findsOneWidget);
      expect(
          find.text('Vault reset is temporarily unavailable. Try again later.'),
          findsNothing);
      final signin = find.widgetWithText(FilledButton, 'Return to sign-in');
      expect(tester.widget<FilledButton>(signin).onPressed, isNotNull);
      expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
      expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
      expect(peer.prepareCalls, 0);
      expect(peer.confirmCalls, 0);
      await tester.ensureVisible(signin);
      await tester.tap(signin);
      await ioFrames(tester, () => setup.currentStep == SetupStep.signin);
      expect(fixture.secrets[AppString.sessionCookie.string], isNull);
      expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
      expect(
          peer.requests.every((request) => request.startsWith('GET ')), isTrue);
      expect(peer.prepareCalls, 0);
      expect(peer.confirmCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'missing session at confirmation offers sign-in without staging a reset',
      (tester) async {
    fixture.secrets.remove(AppString.sessionCookie.string);
    await mount(tester, PageLostRecovery(service: peer.service()));
    await tester.ensureVisible(find.text('Continue to reset'));
    await tester.tap(find.text('Continue to reset'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Delete vault and start fresh'));
    await ioFrames(
        tester, () => find.text('Return to sign-in').evaluate().isNotEmpty);
    expect(
        find.text(
            'Sign in again to verify your session before resetting the vault.'),
        findsOneWidget);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    expect(peer.requests, ['GET /api/recovery-reset/status']);
    expect(tester.takeException(), isNull);
  });

  for (final error in ['sign_in_again', '14', '18']) {
    testWidgets('confirmation authentication error $error offers fresh sign-in',
        (tester) async {
      final setup =
          await mount(tester, PageLostRecovery(service: peer.service()));
      peer.prepareError = error;
      await tester.ensureVisible(find.text('Continue to reset'));
      await tester.tap(find.text('Continue to reset'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.widgetWithText(FilledButton, 'Delete vault and start fresh'));
      await ioFrames(
          tester, () => find.text('Return to sign-in').evaluate().isNotEmpty);
      expect(
          find.text(
              'Sign in again to verify your session before resetting the vault.'),
          findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Continue to reset'), findsNothing);
      expect(setup.currentStep, isNot(SetupStep.recoveryReset));
      final staged = fixture.secrets[AppString.recoveryResetStage.string];
      expect(staged, isNotNull);
      expect(peer.confirmCalls, 0);
      expect(peer.envelope, isNull);

      final signin = find.widgetWithText(FilledButton, 'Return to sign-in');
      await tester.ensureVisible(signin);
      await tester.tap(signin);
      await ioFrames(tester, () => setup.currentStep == SetupStep.signin);
      expect(fixture.secrets[AppString.sessionCookie.string], isNull);
      expect(fixture.secrets[AppString.recoveryResetStage.string], staged);
      expect(peer.confirmCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'reopened reset remembers rejected preparation and offers sign-in',
      (tester) async {
    peer.prepareError = 'sign_in_again';
    await tester.runAsync(() => peer.service().confirm());
    final staged = fixture.secrets[AppString.recoveryResetStage.string];
    peer.prepareError = null;
    final setup =
        await mount(tester, PageRecoveryReset(service: peer.service()));
    await ioFrames(
        tester, () => find.text('Return to sign-in').evaluate().isNotEmpty);
    expect(find.textContaining('Sign in as'), findsOneWidget);
    expect(find.text('Continue to reset'), findsNothing);
    expect(find.text('Try Again'), findsNothing);
    expect(fixture.secrets[AppString.recoveryResetStage.string], staged);
    expect(peer.confirmCalls, 0);
    expect(peer.envelope, isNull);
    final signin = find.widgetWithText(FilledButton, 'Return to sign-in');
    await tester.ensureVisible(signin);
    await tester.tap(signin);
    await ioFrames(tester, () => setup.currentStep == SetupStep.signin);
    expect(fixture.secrets[AppString.sessionCookie.string], isNull);
    expect(fixture.secrets[AppString.recoveryResetStage.string], staged);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopened sign-in guidance supports large RTL text',
      (tester) async {
    peer.prepareError = 'sign_in_again';
    await tester.runAsync(() => peer.service().confirm());
    await mount(tester, PageRecoveryReset(service: peer.service()),
        locale: const Locale('ar'),
        brightness: Brightness.dark,
        largeText: true);
    final context = tester.element(find.byType(PageRecoveryReset));
    final loc = AppLocalizations.of(context)!;
    final signin = find.widgetWithText(FilledButton, loc.recoveryResetDiscard);
    await ioFrames(tester, () => signin.evaluate().isNotEmpty);
    expect(
        find.text(
            loc.recoveryResetSigninAs('\u2068fixture@example.test\u2069')),
        findsOneWidget);
    expect(Directionality.of(context), TextDirection.rtl);
    expect(find.text(loc.tryAgain), findsNothing);
    await tester.ensureVisible(signin);
    expect(tester.widget<FilledButton>(signin).onPressed, isNotNull);
    expect(peer.confirmCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during readiness check ignores its delayed UI result',
      (tester) async {
    await tester.runAsync(
        () => ModelSetting.set(AppString.recoveryResetAvailable.string, 'no'));
    final release = Completer<void>();
    peer.beforeStatus = () => release.future;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
    await tester.ensureVisible(find.text('Lost recovery phrase'));
    await tester.tap(find.text('Lost recovery phrase'));
    await tester.pump();
    await ioFrames(tester, () => peer.statusCalls == 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    release.complete();
    await ioFrames(
        tester,
        () =>
            ModelSetting.get(AppString.recoveryResetAvailable.string) == 'yes');
    expect(find.byType(PageAccessKeyDecode), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
  });

  testWidgets('confirmed reset handles double taps as one operation',
      (tester) async {
    final release = Completer<void>();
    peer.beforePrepare = () => release.future;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final setup =
        await mount(tester, PageLostRecovery(service: peer.service()));
    await tester.ensureVisible(find.text('Continue to reset'));
    await tester.tap(find.text('Continue to reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vault and start fresh'));
    await tester.pump();
    await ioFrames(tester, () => peer.prepareCalls == 1);
    await tester.ensureVisible(find.text('Continue to reset'));
    await tester.tap(find.text('Continue to reset'));
    await tester.pump();
    expect(peer.prepareCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    release.complete();
    await ioFrames(tester, () => setup.currentStep == SetupStep.recoveryReset);
    expect(peer.confirmCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fresh generation publishes once and resumes the saved phrase after restart',
      (tester) async {
    Map<String, dynamic>? envelope;
    var posts = 0;
    final service = VaultKeySetupService.test(
        apiFactory: () => BackendApi(
            baseUrlOverride: 'https://api.example.test/api',
            refreshAuth: () async {},
            httpClient: MockClient((request) async {
              if (request.method == 'POST') {
                posts++;
                envelope = jsonDecode(request.body);
                return http.Response('{"success":1}', 200);
              }
              return http.Response(
                  jsonEncode({
                    'success': 1,
                    'data': {...?envelope, 'vault_generation': 'legacy'}
                  }),
                  200);
            })));
    final setup = await mount(tester, PageAccessKeyNotice(service: service));
    final generate = find.byType(FilledButton);
    await ioFrames(
        tester, () => tester.widget<FilledButton>(generate).onPressed != null);
    expect(fixture.secrets[AppString.vaultKeySetupStage.string], isNull);
    expect(fixture.secrets[AppString.masterKey.string], isNull);
    await tester.tap(generate);
    await ioFrames(tester, () => setup.currentStep == SetupStep.showAccessKey);
    expect(posts, 1);
    final candidate =
        jsonDecode(fixture.secrets[AppString.vaultKeySetupStage.string]!);
    expect(candidate['phase'], 'phrase');
    await tester.runAsync(() => setup.recheckStatus());
    expect(setup.currentStep, SetupStep.generateAccessKey);
    await tester.pumpWidget(const SizedBox.shrink());
    final restarted =
        await mount(tester, PageAccessKeyNotice(service: service));
    await ioFrames(
        tester, () => restarted.currentStep == SetupStep.showAccessKey);
    expect(posts, 1);
    expect(
        jsonDecode(fixture.secrets[AppString.vaultKeySetupStage.string]!)[
            'privateKeys'],
        candidate['privateKeys']);
    expect(tester.takeException(), isNull);
  });

  for (final switchedAccount in [true, false]) {
    testWidgets(
        'interrupted key setup returns to sign-in after ${switchedAccount ? 'an account switch' : 'a newer vault reset'}',
        (tester) async {
      var offline = true;
      final service = VaultKeySetupService.test(
          apiFactory: () => BackendApi(
              baseUrlOverride: 'https://api.example.test/api',
              refreshAuth: () async {},
              httpClient: MockClient((request) async {
                if (offline) return http.Response('', 503);
                expect(request.method, 'GET');
                return http.Response(
                    jsonEncode({
                      'success': 1,
                      'data': {
                        'cipher': null,
                        'nonce': null,
                        'key_state': 'missing',
                        'vault_generation': RecoveryResetPeer.generation
                      }
                    }),
                    200);
              })));
      await tester.runAsync(() async {
        expect(
            (await service.generate()).phase, VaultKeySetupPhase.unavailable);
        expect(fixture.secrets[AppString.vaultKeySetupStage.string], isNotNull);
        offline = false;
        if (switchedAccount) {
          await (await fixture.db).delete('profiles');
          await (await ModelProfile.fromMap(
                  {'id': 'other-account', 'email': 'other@example.test'}))
              .insert();
        }
      });
      final candidate = fixture.secrets[AppString.vaultKeySetupStage.string];
      final setup = await mount(tester, PageAccessKeyNotice(service: service));
      await ioFrames(tester, () => setup.currentStep == SetupStep.signin);
      await tester.runAsync(() async {
        expect(
            await ModelSetting.getRaw(AppString.signedIn.string), isNot('yes'));
        expect(fixture.secrets[AppString.masterKey.string], isNull);
        expect(fixture.secrets[AppString.vaultKeySetupStage.string],
            switchedAccount ? candidate : isNull);
      });
      expect(tester.takeException(), isNull);
    });
  }

  for (final state in ['missing', 'present', 'pending', 'malformed']) {
    testWidgets('key lookup routes the shared $state vault correctly',
        (tester) async {
      fixture.secrets[AppString.keyCipher.string] = 'stale-envelope';
      fixture.secrets[AppString.keyNonce.string] = 'stale-nonce';
      final api = BackendApi(
          baseUrlOverride: 'https://api.example.test/api',
          refreshAuth: () async {},
          httpClient: MockClient((request) async => http.Response(
              jsonEncode(state == 'pending'
                  ? {
                      'success': 0,
                      'message': 17,
                      'reason': 'vault_reset_pending'
                    }
                  : {
                      'success': 1,
                      'data': {
                        'vault_generation': RecoveryResetPeer.generation,
                        'key_state': state,
                        'cipher': state == 'present' ? 'winner-cipher' : null,
                        'nonce': state == 'present'
                            ? 'winner-nonce'
                            : state == 'malformed'
                                ? 7
                                : null
                      }
                    }),
              200)));
      final setup = await mount(tester, PageAccessKeyCheck(api: api));
      if (state == 'malformed') {
        await ioFrames(
            tester,
            () => find
                .widgetWithText(FilledButton, 'Try Again')
                .evaluate()
                .isNotEmpty);
      } else {
        final expected = state == 'missing'
            ? SetupStep.generateAccessKey
            : state == 'present'
                ? SetupStep.decodeAccessKey
                : SetupStep.recoveryReset;
        await ioFrames(tester, () => setup.currentStep == expected);
        expect(
            fixture.secrets[AppString.keyCipher.string],
            state == 'missing'
                ? isNull
                : state == 'present'
                    ? 'winner-cipher'
                    : 'stale-envelope');
      }
      expect(fixture.secrets[AppString.masterKey.string], isNull);
      expect(peer.confirmCalls, 0);
      expect(tester.takeException(), isNull);
      api.close();
    });
  }

  testWidgets(
      'verified shared deletion releases reset context into common setup',
      (tester) async {
    await tester.runAsync(() => peer.service().confirm());
    peer.phase = 'ready';
    final setup =
        await mount(tester, PageRecoveryReset(service: peer.service()));
    await ioFrames(tester, () => setup.currentStep == SetupStep.checkAccessKey);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    expect(fixture.secrets[AppString.masterKey.string], isNull);
    expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
    expect(peer.confirmCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'verified deletion shows generation before revealing the fresh phrase',
      (tester) async {
    peer.deferredKeySetup =
        false; // Released reset with an existing staged envelope.

    await tester.runAsync(() => peer.service().confirm());
    final saved = fixture.secrets[AppString.recoveryResetStage.string];
    final setup =
        await mount(tester, PageRecoveryReset(service: peer.service()));
    await ioFrames(tester,
        () => find.text('Deleting your previous vault').evaluate().isNotEmpty);
    expect(find.byType(PageAccessKey), findsNothing);
    expect(peer.confirmCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    peer.phase = 'ready';
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: setup,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: PageRecoveryReset(service: peer.service()),
          )));
    });
    await ioFrames(
        tester, () => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty);
    expect(find.byType(PageAccessKey), findsNothing);
    expect(fixture.secrets[AppString.masterKey.string], isNull);
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    peer.beforeStatus = () => release.future;
    final generate = find.descendant(
        of: find.byType(PageAccessKeyNotice),
        matching: find.byType(FilledButton));
    await tester.tap(generate);
    await tester.pump();
    expect(tester.widget<FilledButton>(generate).onPressed, isNull);
    await tester.tap(generate);
    release.complete();
    await ioFrames(
        tester, () => find.byType(PageAccessKey).evaluate().isNotEmpty);
    expect(peer.confirmCalls, 1);
    final now =
        jsonDecode(fixture.secrets[AppString.recoveryResetStage.string]!);
    expect(now['privateKeys'], jsonDecode(saved!)['privateKeys']);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets('generation stays reachable at large text in $locale',
        (tester) async {
      peer.deferredKeySetup =
          false; // Released reset with an existing staged envelope.

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => peer.service().confirm());
      peer.phase = 'ready';
      await mount(tester, PageRecoveryReset(service: peer.service()),
          locale: locale, brightness: Brightness.dark, largeText: true);
      await ioFrames(
          tester, () => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty);
      final generate = find.descendant(
          of: find.byType(PageAccessKeyNotice),
          matching: find.byType(FilledButton));
      await tester.ensureVisible(generate);
      await tester.pump();
      expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
      expect(find.byType(PageAccessKey), findsNothing);
      expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'generation waits for resume verification before enabling its action',
      (tester) async {
    peer.deferredKeySetup =
        false; // Released reset with an existing staged envelope.

    await tester.runAsync(() => peer.service().confirm());
    peer.phase = 'ready';
    await mount(tester, PageRecoveryReset(service: peer.service()));
    await ioFrames(
        tester, () => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty);
    final release = Completer<void>();
    peer.beforeStatus = () => release.future;
    final generate = find.descendant(
        of: find.byType(PageAccessKeyNotice),
        matching: find.byType(FilledButton));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    try {
      expect(tester.widget<FilledButton>(generate).onPressed, isNull);
      expect(fixture.secrets[AppString.masterKey.string], isNull);
    } finally {
      release.complete();
      peer.beforeStatus = null;
      await ioFrames(tester,
          () => tester.widget<FilledButton>(generate).onPressed != null);
    }
    expect(find.byType(PageAccessKey), findsNothing);
    expect(fixture.secrets[AppString.sessionCookie.string], 'fixture-cookie');
  });

  testWidgets('status polling does not interrupt an open reset confirmation',
      (tester) async {
    peer.confirmError = 'storage_access_required';
    await tester.runAsync(() => peer.service().confirm());
    await mountWithControlledTimers(tester);
    final continueButton =
        find.widgetWithText(FilledButton, 'Continue to reset');
    await ioFrames(
        tester,
        () =>
            continueButton.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(continueButton).onPressed != null);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final release = Completer<void>();
    peer.beforeStatus = () => release.future;
    try {
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    } finally {
      release.complete();
      peer.beforeStatus = null;
    }
    await tester.tap(find.text('Delete vault and start fresh'));
    await ioFrames(tester, () => peer.confirmCalls == 2);
    await ioFrames(
        tester,
        () =>
            continueButton.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(continueButton).onPressed != null);
    expect(peer.envelope, isNull);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'status polling pauses while discarding unusable staging is cancelled',
      (tester) async {
    fixture.secrets[AppString.recoveryResetStage.string] = 'corrupt-staging';
    await mountWithControlledTimers(tester);
    final returnButton = find.widgetWithText(FilledButton, 'Return to sign-in');
    await ioFrames(
        tester,
        () =>
            returnButton.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(returnButton).onPressed != null);
    await tester.tap(returnButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final release = Completer<void>();
    peer.beforeStatus = () => release.future;
    try {
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(fixture.secrets[AppString.recoveryResetStage.string],
          'corrupt-staging');
    } finally {
      release.complete();
      peer.beforeStatus = null;
    }
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.secrets[AppString.recoveryResetStage.string],
        'corrupt-staging');
    expect(peer.prepareCalls, 0);
    expect(peer.confirmCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected preparation exposes the safe return action',
      (tester) async {
    peer.prepareError = 'recovery_unavailable';
    peer.available = false;
    await tester.runAsync(() => peer.service().confirm());
    final original = fixture.secrets[AppString.recoveryResetStage.string];
    await mountWithControlledTimers(tester);
    final returnButton = find.widgetWithText(FilledButton, 'Return to sign-in');
    await ioFrames(tester, () => returnButton.evaluate().isNotEmpty);
    await tester.ensureVisible(returnButton);
    await tester.tap(returnButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.secrets[AppString.recoveryResetStage.string], original);
    expect(peer.confirmCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
          'recovery screens support 320px, large text, $locale and $brightness',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await mount(tester, PageLostRecovery(service: peer.service()),
            locale: locale, brightness: brightness, largeText: true);
        final loc =
            AppLocalizations.of(tester.element(find.byType(PageLostRecovery)))!;
        await tester.ensureVisible(find.text(loc.recoveryResetContinue));
        await tester.tap(find.text(loc.recoveryResetContinue));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(loc.cancel));
        await tester.pumpAndSettle();
        expect(peer.requests, ['GET /api/recovery-reset/status']);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.secrets[AppString.accessKey.string] =
            base64Encode(List<int>.generate(32, (i) => i));
        var acknowledged = 0;
        await mount(
            tester,
            PageAccessKey(
                requireAcknowledgment: true,
                onAcknowledged: () async => acknowledged++),
            locale: locale,
            brightness: brightness,
            largeText: true);
        await ioFrames(
            tester,
            () =>
                tester
                    .widget<FilledButton>(
                        find.widgetWithText(FilledButton, loc.copy))
                    .onPressed !=
                null);
        final continueButton =
            find.widgetWithText(OutlinedButton, loc.continueLabel);
        expect(tester.widget<OutlinedButton>(continueButton).onPressed, isNull);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pump();
        expect(acknowledged, 1);
        expect(
            Directionality.of(tester.element(find.byType(PageAccessKey))),
            locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      });
    }
  }
}
