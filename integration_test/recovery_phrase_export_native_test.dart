import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_recovery_phrase.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_phrase_export.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'support/iphone_results.dart';
import 'support/native_test_install.dart';

/// Real default Settings, key storage, device authentication and OS clipboard /
/// document save. Only the unrelated signed-in account/entropy is synthetic.
void main() {
  if (const bool.fromEnvironment('FIFE_NATIVE_UNIT_HOST')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(child: Text('FiFe native component tests')))));
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    ..shouldPropagateDevicePointerEvents = true;
  recordIphoneResults(binding, 'recovery-phrase-export', probeBackend: false);
  const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
  unawaited(binding.allTestsPassed.future.then((passed) async {
    final documents = await getApplicationDocumentsDirectory();
    final result = File('${documents.path}/fife-recovery-export-result.json');
    await result.writeAsString(
        jsonEncode({
          'runId': runId,
          'passed': passed,
          'failureCount': binding.failureMethodsDetails.length,
          'syntheticDataOnly': true
        }),
        flush: true);
  }));

  testWidgets('protected Settings recovery export on a physical phone',
      (tester) async {
    await verifyNativeTestInstall();
    expect(runId, startsWith('recovery-export-'));
    expect(Uri.parse(AppEnv.effectiveApiBaseUrl).host, endsWith('.test'));
    expect(
        AppEnv.neonAuthUrl.isEmpty ||
            Uri.parse(AppEnv.neonAuthUrl).host.endsWith('.test'),
        isTrue);
    final documents = await getApplicationDocumentsDirectory();
    final progress =
        File('${documents.path}/fife-recovery-export-progress.json');
    final exportDirectory = Directory('${documents.path}/$runId');
    if (Platform.isIOS) {
      expect(await exportDirectory.exists(), isFalse);
      await exportDirectory.create();
    }
    final checks = <String, bool>{};
    Future<void> checkpoint(String phase) async {
      final partial = File('${progress.path}.partial');
      await partial.writeAsString(
          jsonEncode({
            'runId': runId,
            'phase': phase,
            'checks': checks,
            'syntheticDataOnly': true,
            'at': DateTime.now().millisecondsSinceEpoch
          }),
          flush: true);
      await partial.rename(progress.path);
      debugPrint('FIFE_RECOVERY_EXPORT_PHASE ${jsonEncode({
            'runId': runId,
            'phase': phase,
            'checks': checks
          })}');
    }

    Future<void> until(FutureOr<bool> Function() ready) async {
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      while (!await ready()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Recovery export checkpoint timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Future<void> tap(Finder finder) async {
      await tester.scrollUntilVisible(finder, 240,
          scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await until(() => finder.hitTestable().evaluate().length == 1);
      await tester.tap(finder);
    }

    // The external controller seeds only the stale file before this cold
    // launch. No SQL/cleanup initializer may clear it before actual main().
    final owned = Directory('${documents.parent.path}/tmp/FiFeRecoveryExports');
    if (Platform.isIOS) {
      final stale = File('${owned.path}/interrupted/fife_recovery_phrase.txt');
      expect(await stale.exists(), isTrue,
          reason: 'A pre-launch interrupted-export fixture is required');
    }
    await checkpoint('normal_startup_cleanup');
    await application.main();
    await until(() => find.byType(application.MyApp).evaluate().isNotEmpty);
    if (Platform.isIOS) {
      expect(await owned.exists(), isFalse);
      checks['actualLauncherClearedInterruptedExport'] = true;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await SessionCleanup.instance.request(), isTrue);
    final storage = SecureStorage();
    final access = base64Encode(Uint8List(32));
    final master = base64Encode(Uint8List.fromList(List.filled(32, 7)));
    final words = '${List.filled(23, 'abandon').join(' ')} art';
    await storage.write(key: AppString.accessKey.string, value: access);
    await storage.write(key: AppString.masterKey.string, value: master);
    await ModelProfile(
            id: AppEnv.localTestUserId, email: 'recovery-export@example.test')
        .insert();
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.syncWithNotification.string, 'no');
    await ModelSetting.set(AppString.appLockEnabled.string, 'no');
    await ModelSetting.set(AppString.appLockTimeoutMinutes.string, '5');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    final lock = AppLockController();
    final locale = LocaleProvider();
    await lock.load();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (Platform.isIOS) {
        await BackgroundExecutionService.instance.cancelIosWork();
      }
      await SessionCleanup.instance.resume();
      await SessionCleanup.instance.request();
      await const SystemAppLockPrivacy().setEnabled(false);
      lock.dispose();
      locale.dispose();
    });
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lock),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppLockNavigatorObserver(lock)],
          builder: (_, child) => AppLockGate(controller: lock, child: child!),
          home: SettingsPage(onThemeChange: (_) {}),
        )));
    await until(() => find.byType(SettingsPage).evaluate().isNotEmpty);
    expect(
        find.byKey(const ValueKey('download-recovery-phrase')), findsNothing);
    checks['hiddenWhenOff'] = true;
    await checkpoint('awaiting_enable_auth');
    await tap(find.byKey(const ValueKey('app-lock-switch')));
    await until(() => lock.enabled && !lock.busy);
    expect(lock.minutes, 5);
    checks['enabledAfterRealDeviceAuthentication'] = true;

    // A retired reservation must fail in the real native actor, even if a
    // previously queued platform message arrives after a cleanup request.
    if (Platform.isIOS) {
      await until(() => lock.foreground);
      String? token;
      await until(() async {
        try {
          token = await RecoveryPhraseExportFiles.channel
              .invokeMethod<String>('reserve');
          return token != null;
        } on PlatformException {
          return false;
        }
      });
      await RecoveryPhraseExportFiles.clear();
      await expectLater(
          RecoveryPhraseExportFiles.channel.invokeMethod<bool>('save', {
            'text': words,
            'title': 'Synthetic export',
            'reservation': token
          }),
          throwsA(isA<PlatformException>()));
      expect(await owned.exists(), isFalse);
      checks['realNativeRejectsLateRetiredPublication'] = true;
    }

    final action = find.byKey(const ValueKey('download-recovery-phrase'));
    await checkpoint('awaiting_export_cancel');
    await tap(action);
    await until(() =>
        !lock.busy && lock.failure == AppLockFailure.authenticationFailed);
    expect(find.byType(RecoveryPhraseExportPage), findsNothing);
    checks['canceledAuthenticationRevealsNothing'] = true;

    Future<void> showPhrase(String phase) async {
      if (find
          .byKey(const ValueKey('recovery-phrase-words'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
      await checkpoint(phase);
      await tap(action);
      await until(() => find
          .byKey(const ValueKey('recovery-phrase-words'))
          .evaluate()
          .isNotEmpty);
      expect(find.text(words), findsOneWidget);
      expect(await storage.read(key: AppString.accessKey.string), access);
      expect(await storage.read(key: AppString.masterKey.string), master);
    }

    await showPhrase('awaiting_export_auth');
    checks['freshAuthenticationShowsOriginalWords'] = true;
    await tap(find.byKey(const ValueKey('recovery-phrase-copy')));
    await until(() async =>
        (await Clipboard.getData(Clipboard.kTextPlain))?.text == words);
    checks['defaultNativeClipboardCopiedOriginalWords'] = true;

    var sawBackground = false;
    void observe() {
      if (!lock.foreground) sawBackground = true;
    }

    lock.addListener(observe);
    await checkpoint('awaiting_home_and_return');
    await until(() => sawBackground && lock.foreground);
    lock.removeListener(observe);
    await until(() => find
        .byType(RecoveryPhraseExportPage, skipOffstage: false)
        .evaluate()
        .isEmpty);
    expect(lock.locked, isFalse);
    checks['realBackgroundReturnClosedPhraseInsideGrace'] = true;

    await showPhrase('awaiting_reopen_auth');
    await checkpoint('awaiting_save_cancel');
    final beforeCancel = NativeRecoveryPhrasePlatform.saveAttempts;
    await tap(find.byKey(const ValueKey('recovery-phrase-download')));
    await until(() => NativeRecoveryPhrasePlatform.saveAttempts > beforeCancel);
    await until(() => !NativeRecoveryPhrasePlatform.saveInProgress);
    expect(NativeRecoveryPhrasePlatform.lastSaveResult, isFalse);
    if (Platform.isIOS) expect(await owned.exists(), isFalse);
    checks['realSaveCancelCleanedPrivateStaging'] = true;

    await showPhrase('awaiting_save_reopen_auth');
    await checkpoint('awaiting_save_to_generated_folder');
    final beforeSave = NativeRecoveryPhrasePlatform.saveAttempts;
    await tap(find.byKey(const ValueKey('recovery-phrase-download')));
    await until(() => NativeRecoveryPhrasePlatform.saveAttempts > beforeSave);
    await until(() => !NativeRecoveryPhrasePlatform.saveInProgress);
    expect(NativeRecoveryPhrasePlatform.lastSaveResult, isTrue);
    final expectedHash = sha256.convert(utf8.encode(words)).toString();
    final saved = File('${exportDirectory.path}/fife_recovery_phrase.txt');
    if (Platform.isIOS) {
      await until(saved.exists);
      expect(
          sha256.convert(await saved.readAsBytes()).toString(), expectedHash);
    } else {
      // Independent ADB observer reads only Download/<runId>/the saved file and
      // returns its hash. It never supplies the file or grants broad app access.
      await checkpoint('awaiting_independent_android_saved_file_observation');
      final receipt =
          File('${documents.path}/fife-recovery-export-save-observed.json');
      await until(receipt.exists);
      final observation = jsonDecode(await receipt.readAsString()) as Map;
      expect(observation['runId'], runId);
      expect(observation['actualFileRead'], isTrue);
      expect(observation['bytes'], utf8.encode(words).length);
      expect(observation['sha256'], expectedHash);
      await receipt.delete();
    }
    if (Platform.isIOS) {
      await until(() async => !await owned.exists());
    }
    checks['realSavedFileMatchesOriginalPhrase'] = true;
    checks['realSaveRemovedOnlyPrivateStaging'] = true;
    expect(await storage.read(key: AppString.accessKey.string), access);
    expect(await storage.read(key: AppString.masterKey.string), master);
    checks['vaultKeysUnchanged'] = true;
    // Remove only the exact public test vector from this unique generated root.
    if (Platform.isIOS) {
      await saved.delete();
      await exportDirectory.delete();
    }
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text == words) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
    await checkpoint('complete');
  }, timeout: const Timeout(Duration(hours: 1)));
}
