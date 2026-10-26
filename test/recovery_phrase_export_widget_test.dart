import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_recovery_phrase.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_phrase_export.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/ui/thumb_reach_list.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'recovery_phrase_export_test.dart'
    show syntheticRecoveryPhrase, RecoveryPlatformProbe;
import 'support/app_lock_fixture.dart';
import 'support/sync_fixture.dart';

class _Privacy implements AppLockPrivacyBridge {
  @override
  bool get supported => false;
  @override
  bool get reportsApplicationLifecycle => false;
  @override
  Future<VoidCallback> watchLifecycle(
          ValueChanged<AppLifecycleState> listener) async =>
      () {};
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> frameReady({bool allowNativeDocuments = false}) async {}
}

class _SavePicker extends FilePickerPlatform {
  final phrases = <String>[];
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    expect(fileName, 'fife_recovery_phrase.txt');
    expect(mimeType, 'text/plain');
    phrases.add(utf8.decode(bytes));
    return Uri.file('/synthetic/recovery.txt');
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late AppLockController lock;
  late MemoryAppLockStore store;
  late FakeAppLockAuthenticator auth;
  late RecoveryPlatformProbe platform;
  late SyncFixture fixture;
  late FilePickerPlatform priorPicker;
  late _SavePicker picker;
  final copied = <String>[];
  const privacyChannel = MethodChannel('com.jeerovan.fife/app_lock_privacy');

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  Future<void> mount(WidgetTester tester,
      {bool enabled = true,
      bool normalSettings = false,
      RecoveryPhraseService? service,
      Locale locale = const Locale('en'),
      double scale = 1,
      Size size = const Size(390, 844)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    fixture = (await tester.runAsync(SyncFixture.create))!;
    await tester
        .runAsync(() => ModelSetting.set(AppString.signedIn.string, 'yes'));
    fixture.secrets[AppString.accessKey.string] = base64Encode(Uint8List(32));
    store = MemoryAppLockStore()..enabled = enabled;
    auth = FakeAppLockAuthenticator();
    lock = AppLockController(store: store, authenticator: auth);
    await lock.load();
    if (enabled) await lock.unlock(testAppLockPrompt);
    platform = RecoveryPlatformProbe();
    final localeProvider = LocaleProvider();
    PackageInfo.setMockInitialValues(
        appName: 'FiFe',
        packageName: 'fixture',
        version: '1',
        buildNumber: '1',
        buildSignature: 'fixture');
    priorPicker = FilePickerPlatform.instance;
    picker = _SavePicker();
    FilePickerPlatform.instance = picker;
    copied.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(privacyChannel,
        (call) async {
      if (call.method == 'copyRecoveryPhrase') {
        copied.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      lock.dispose();
      localeProvider.dispose();
      FilePickerPlatform.instance = priorPicker;
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(privacyChannel, null);
      await tester.runAsync(fixture.dispose);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final protectedSettings = normalSettings
        ? SettingsPage(onThemeChange: (_) {})
        : Scaffold(
            body: ListView(children: [
            AppLockSettings(controller: lock, enabledActions: [
              RecoveryPhraseSettingsAction(
                  controller: lock,
                  service: service ??
                      RecoveryPhraseService(
                          signedIn: () async => true,
                          readAccessKey: () async =>
                              base64Encode(Uint8List(32)),
                          platform: platform)),
            ])
          ]));
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lock),
          ChangeNotifierProvider.value(value: localeProvider),
        ],
        child: MaterialApp(
          locale: locale,
          theme: ThemeData(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppLockNavigatorObserver(lock)],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true),
              child: AppLockGate(
                  controller: lock, privacy: _Privacy(), child: child!)),
          home: protectedSettings,
        )));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('download-recovery-phrase'));
    await tester.scrollUntilVisible(action, 240,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await until(
        tester,
        () => find
            .byKey(const ValueKey('recovery-phrase-words'))
            .evaluate()
            .isNotEmpty);
  }

  testWidgets(
      'Settings hides export while off; enabling reveals it beneath the timeout',
      (tester) async {
    await mount(tester, enabled: false);
    expect(
        find.byKey(const ValueKey('download-recovery-phrase')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Download recovery phrase'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Download recovery phrase')).dy,
        greaterThan(tester
            .getTopLeft(find.byKey(const ValueKey('app-lock-timeout')))
            .dy));
  });

  testWidgets(
      'normal Settings and default service read/copy/save the original phrase without key changes',
      (tester) async {
    await mount(tester, normalSettings: true);
    final before = Map<String, String>.from(fixture.secrets);
    await open(tester);
    expect(auth.attempts, 2);
    expect(find.text(syntheticRecoveryPhrase), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recovery-phrase-copy')));
    await until(tester, () => copied.isNotEmpty);
    expect(copied, [syntheticRecoveryPhrase]);
    await until(
        tester,
        () =>
            tester
                .widget<OutlinedButton>(
                    find.byKey(const ValueKey('recovery-phrase-copy')))
                .onPressed !=
            null);
    await tester.tap(find.byKey(const ValueKey('recovery-phrase-download')));
    await until(tester, () => picker.phrases.isNotEmpty);
    expect(picker.phrases, [syntheticRecoveryPhrase]);
    expect(fixture.secrets, before);
  });

  testWidgets(
      'no entropy read or phrase screen before fresh phone authentication completes',
      (tester) async {
    var reads = 0;
    await mount(tester,
        service: RecoveryPhraseService(
            signedIn: () async => true,
            readAccessKey: () async {
              reads++;
              return base64Encode(Uint8List(32));
            }));
    final pending = Completer<bool>();
    auth.onAuthenticate = (_) => pending.future;
    await tester.tap(find.byKey(const ValueKey('download-recovery-phrase')));
    await until(tester, () => auth.attempts == 2);
    expect(reads, 0);
    expect(find.byType(RecoveryPhraseExportPage), findsNothing);
    pending.complete(true);
    await until(
        tester, () => find.text(syntheticRecoveryPhrase).evaluate().isNotEmpty);
    expect(reads, 1);
  });

  testWidgets(
      'cancel stays on Settings and retry requires a new successful prompt',
      (tester) async {
    await mount(tester);
    auth.result = false;
    await tester.tap(find.byKey(const ValueKey('download-recovery-phrase')));
    await until(tester, () => auth.attempts == 2 && !lock.busy);
    expect(find.byType(RecoveryPhraseExportPage), findsNothing);
    auth.result = true;
    await open(tester);
    expect(auth.attempts, 3);
  });

  testWidgets(
      'background hides/removes the phrase even within App lock grace; reopening authenticates again',
      (tester) async {
    await mount(tester);
    await open(tester);
    lock.handleLifecycle(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text(syntheticRecoveryPhrase), findsNothing);
    await tester.pumpAndSettle();
    lock.handleLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(lock.locked, isFalse);
    expect(find.byType(RecoveryPhraseExportPage), findsNothing);
    await open(tester);
    expect(auth.attempts, 3);
  });

  testWidgets('late key read after session invalidation cannot reveal words',
      (tester) async {
    final pending = Completer<String?>();
    var reads = 0;
    await mount(tester,
        service: RecoveryPhraseService(
            signedIn: () async => true,
            readAccessKey: () {
              reads++;
              return pending.future;
            }));
    await tester.tap(find.byKey(const ValueKey('download-recovery-phrase')));
    await until(tester, () => reads == 1);
    SessionWork.invalidate('replacement-owner');
    lock.invalidateSession();
    pending.complete(base64Encode(Uint8List(32)));
    await until(
        tester,
        () => find
            .byType(RecoveryPhraseExportPage, skipOffstage: false)
            .evaluate()
            .isEmpty);
    expect(find.text(syntheticRecoveryPhrase), findsNothing);
    expect(find.byType(RecoveryPhraseExportPage), findsNothing);
  });

  testWidgets(
      'missing entropy offers retry and never enters generation/registration',
      (tester) async {
    await mount(tester,
        service: RecoveryPhraseService(
            signedIn: () async => true, readAccessKey: () async => null));
    await tester.tap(find.byKey(const ValueKey('download-recovery-phrase')));
    await until(tester,
        () => find.textContaining("couldn't be loaded").evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('recovery-phrase-words')), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('recovery-phrase-download')))
            .onPressed,
        isNull);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets(
        'compact large-text export fits with LTR words in ${locale.languageCode}',
        (tester) async {
      await mount(tester, locale: locale, scale: 2, size: const Size(320, 700));
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(
          tester.widget<Text>(find.text(syntheticRecoveryPhrase)).textDirection,
          TextDirection.ltr);
      final button = tester
          .getRect(find.byKey(const ValueKey('recovery-phrase-download')));
      expect(button.bottom, lessThanOrEqualTo(700));
      expect(button.height, greaterThanOrEqualTo(48));
    });
  }

  testWidgets('phrase view retains portrait reach and clears it in landscape',
      (tester) async {
    await mount(tester);
    await open(tester);
    final view =
        tester.widget<ThumbReachListView>(find.byType(ThumbReachListView));
    expect(view.controller!.position.pixels, 0);
    final gesture = await tester.startGesture(const Offset(190, 200));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(view.controller!.position.pixels, lessThan(0));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(view.controller!.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });
}
