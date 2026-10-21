import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<void> until(Future<bool> Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await ready(), isTrue);
  }

  for (final step in [
    SetupStep.onboard,
    SetupStep.signin,
    SetupStep.checkAccessKey,
    SetupStep.registerDevice,
    SetupStep.explorer
  ]) {
    test('app startup resumes at the missing ${step.name} requirement',
        () async {
      if (step != SetupStep.onboard) {
        await ModelSetting.set(AppString.onboarding.string, 'yes');
      }
      if (step != SetupStep.onboard && step != SetupStep.signin) {
        await ModelSetting.set(AppString.signedIn.string, 'yes');
      }
      if (step == SetupStep.checkAccessKey) {
        fixture.secrets.remove(AppString.masterKey.string);
      }
      if (step == SetupStep.registerDevice) {
        await ModelSetting.delete(AppString.deviceUuid.string);
      }
      final setup = AppSetupState(SecureStorage());
      addTearDown(setup.dispose);
      await until(() async => setup.currentStep == step);
    }, skip: step == SetupStep.explorer && Platform.isAndroid);
  }

  test(
      'saved language loads, changes durably, and can return to system default',
      () async {
    await ModelSetting.set(AppString.locale.string, 'de');
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    expect(provider.locale, const Locale('de'));
    var changes = 0;
    provider.addListener(() => changes++);
    provider.setLocale(const Locale('ar'));
    await until(
        () async => await ModelSetting.getRaw(AppString.locale.string) == 'ar');
    expect(provider.locale, const Locale('ar'));
    expect(changes, 1);
    provider.clearLocale();
    await until(
        () async => await ModelSetting.getRaw(AppString.locale.string) == '');
    expect(provider.locale, isNull);
    expect(changes, 2);
  });

  test('unsupported language preserves the current locale and saved preference',
      () async {
    await ModelSetting.set(AppString.locale.string, 'en');
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    var changes = 0;
    provider.addListener(() => changes++);
    provider.setLocale(const Locale('unsupported'));
    expect(provider.locale, const Locale('en'));
    expect(await ModelSetting.getRaw(AppString.locale.string), 'en');
    expect(changes, 0);
  });

  testWidgets('registration can retry unavailable reset staging storage',
      (tester) async {
    final originalSecrets = Map<String, String>.of(fixture.secrets);
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncFixture.secure, (call) async {
      if (call.method == 'containsKey') {
        attempts++;
        throw PlatformException(code: 'KEY_STORE_UNAVAILABLE');
      }
      if (call.method == 'read') {
        return fixture.secrets[call.arguments['key']];
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PageRegisterDevice(),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Please try again.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(attempts, 2);
    expect(fixture.secrets, originalSecrets);
    final profiles =
        await tester.runAsync(() async => (await fixture.db).query('profiles'));
    expect(profiles!.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
