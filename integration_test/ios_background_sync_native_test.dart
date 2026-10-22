import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' show backgroundTaskDispatcher;
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'support/native_test_identity.dart';
import 'support/native_test_install.dart';

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(await condition(), isTrue);
}

Future<bool> _nativePending(int expected) async {
  final cache = await getApplicationCacheDirectory();
  final trace = File('${cache.path}/fife-background-test-trace.json');
  if (!await trace.exists()) return false;
  final entries = (jsonDecode(await trace.readAsString()) as List)
      .where((entry) => entry['event'] == 'queue')
      .toList();
  return entries.isNotEmpty && (entries.last['value'] as int) % 100 == expected;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final checks = <String, bool>{};
  // Standalone signed profile runs report only outcomes, never key values,
  // account contents or signed URLs, and need no network permission.
  unawaited(binding.allTestsPassed.future.then((passed) async {
    if (!isIsolatedNativeTestBundle(
        (await PackageInfo.fromPlatform()).packageName)) {
      return;
    }
    final documents = await getApplicationDocumentsDirectory();
    await File('${documents.path}/fife-ios-auto-result.json').writeAsString(
        jsonEncode({
          'passed': passed,
          'failures': binding.failureMethodsDetails.length,
          'checks': checks
        }),
        flush: true);
  }));

  testWidgets('automatic iOS refresh follows setup, reset and local sign-out',
      (tester) async {
    await tester.runAsync(verifyNativeTestInstall);
    expect(Platform.isIOS, isTrue);
    late AppSetupState setup;
    final lock = AppLockController();
    final locale = LocaleProvider();
    addTearDown(lock.dispose);
    addTearDown(locale.dispose);
    await tester.runAsync(() async {
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), isEmpty,
          reason: 'This fixture must start in a new container');
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      await ModelSetting.set(AppString.backgroundSync.string, 'no');
      final background = BackgroundExecutionService.instance;
      expect(
          await background.initialize(
              iosCallbackDispatcher: backgroundTaskDispatcher),
          isTrue);
      await _until(() => _nativePending(0));
      checks['incompleteSetupHasNoRequest'] = true;
      setup = AppSetupState(SecureStorage());
      addTearDown(setup.dispose);
      await _until(() async => setup.currentStep == SetupStep.checkAccessKey);
      await SecureStorage().write(
          key: AppString.masterKey.string,
          value: base64Encode(List<int>.filled(32, 7)));
      await setup.recheckStatus();
      expect(setup.currentStep, SetupStep.registerDevice);
      expect(await _nativePending(0), isTrue);
      await ModelSetting.set(
          AppString.deviceUuid.string, 'ios-auto-fixture-device');
      await setup.recheckStatus();
      expect(setup.currentStep, SetupStep.explorer);
      await _until(() => _nativePending(1));
      checks['setupAutomaticallySubmittedDespiteLegacyOff'] = true;
      await lock.load();
      expect(lock.enabled, isFalse);
      expect(lock.minutes, 5);
      checks['appLockRemainsOptionalOffAtFiveMinutes'] = true;
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: locale),
        ChangeNotifierProvider.value(value: lock)
      ],
      child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(onThemeChange: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Background sync'), findsNothing);
    expect(find.text('App lock'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('app-lock-switch')))
            .value,
        isFalse);
    checks['iosSettingsHasAppLockWithoutBackgroundSwitch'] = true;
    await tester.runAsync(() async {
      final background = BackgroundExecutionService.instance;
      await SecureStorage().write(
          key: AppString.recoveryResetStage.string,
          value: 'fixture-reset-pending');
      expect(await background.setEnabled(true), isTrue);
      await _until(() => _nativePending(0));
      checks['pendingResetCancelsRequests'] = true;
      await SecureStorage().delete(key: AppString.recoveryResetStage.string);
      await setup.recheckStatus();
      await _until(() => _nativePending(1));
      checks['readyVaultResumesAutomatically'] = true;
      expect(await SessionCleanup.instance.request(), isTrue);
      await _until(() => _nativePending(0));
      expect(await isIosBackgroundSyncReady(), isFalse);
      checks['realLocalCleanupCancelsNativeRequests'] = true;
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
