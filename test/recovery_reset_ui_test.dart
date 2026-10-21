import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_display.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_lost_recovery.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_reset.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  testWidgets(
      'opening and canceling lost phrase preserves entered words and focus without requests',
      (tester) async {
    await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
    await tester.enterText(
        find.byType(TextFormField), 'partially entered recovery words');
    await tester.ensureVisible(find.text('Lost recovery phrase'));
    await tester.tap(find.text('Lost recovery phrase'));
    await tester.pumpAndSettle();
    expect(find.byType(PageLostRecovery), findsOneWidget);
    expect(peer.requests, isEmpty);
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
    expect(peer.requests, isEmpty);
    expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
    expect(tester.takeException(), isNull);
  });

  for (final setting in [
    AppString.recoveryResetAvailable,
    AppString.simulateTesting,
    AppString.localTesting
  ]) {
    testWidgets('reset entry respects ${setting.name} gate', (tester) async {
      await tester.runAsync(() => ModelSetting.set(setting.string,
          setting == AppString.recoveryResetAvailable ? 'no' : 'yes'));
      await mount(tester, PageAccessKeyDecode(recoveryService: peer.service()));
      expect(
          find.text('Lost recovery phrase'),
          setting == AppString.localTesting && !AppEnv.localTestingBuild
              ? findsOneWidget
              : findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(peer.requests, isEmpty);
    });
  }

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
      'verified deletion shows generation before revealing the fresh phrase',
      (tester) async {
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
        expect(peer.requests, isEmpty);
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
