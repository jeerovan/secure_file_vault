import 'dart:io';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_display.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'support/iphone_results.dart';
import 'support/native_test_install.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recordIphoneResults(binding, 'revocation');

  testWidgets('LAN revocation preserves offline data then erases on discovery',
      (tester) async {
    expect(
        const bool.fromEnvironment('FIFE_RUN_RECOVERY_NATIVE_TESTS'), isTrue);
    expect(AppEnv.localTestingBuild, isTrue);
    expect(AppEnv.localTestUserId.startsWith('fife-provider-local-'), isTrue);
    expect(AppEnv.effectiveApiBaseUrl, AppEnv.apiBaseUrl);
    await verifyNativeTestInstall();

    await addTrustedCertificates();
    final mainUuid = const Uuid().v4();
    final peerUuid = const Uuid().v4();
    BackendApi client(String uuid) => BackendApi(
        localTestingProvider: () => true,
        deviceUuidProvider: () async => uuid,
        refreshAuth: () async {});
    final absent = await client('').get(endpoint: '/keys');
    expect(absent['success'], 0,
        reason: 'This fixture requires an empty disposable local account');
    expect(absent['message'].toString(), '1');
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    expect(await SessionCleanup.instance.request(), isTrue);
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.deviceUuid.string, mainUuid);
    await (await ModelProfile.fromMap(
            {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
        .insert();
    final keys =
        CryptoUtils(await SodiumSumoInit.init()).generateKeys().getResult()!;
    final secure = SecureStorage();
    for (final entry
        in (keys[AppString.privateKeys.string] as Map<String, dynamic>)
            .entries) {
      await secure.write(key: entry.key, value: entry.value as String);
    }
    final api = client(mainUuid);
    expect(
        (await api.post(
            endpoint: '/keys',
            jsonBody: keys[AppString.serverKeys.string]))['success'],
        1);
    for (final uuid in [mainUuid, peerUuid]) {
      expect(
          (await client('').post(endpoint: '/devices', jsonBody: {
            'device_uuid': uuid,
            'title': 'Disposable native revocation fixture',
            'type': 1,
            'active': 1,
          }))['success'],
          1);
    }
    final documents = await getApplicationDocumentsDirectory();
    final temporary = await getTemporaryDirectory();
    final owned = File('${documents.path}/FiFe/revocation-fixture/private.txt');
    final external = File('${documents.path}/revocation-original-fixture.txt');
    final upload = File('${temporary.path}/${'B' * 43}_1.crypt.ready');
    await owned.parent.create(recursive: true);
    await owned.writeAsString('app-owned revocation fixture');
    await external.writeAsString('external original is preserved');
    await upload.writeAsString('unfinished encrypted upload fixture');
    try {
      expect(await SyncUtils.checkDeviceStatus(), isFalse);
      expect(
          (await client(peerUuid).delete(
              endpoint: '/devices',
              queryParameters: {'device_uuid': mainUuid}))['success'],
          1);
      final offline = BackendApi(
          localTestingProvider: () => true,
          deviceUuidProvider: () async => mainUuid,
          refreshAuth: () async {},
          httpClient: MockClient((_) async {
            throw const SocketException('Deliberately offline fixture');
          }));
      expect((await offline.get(endpoint: '/storages'))['success'], -1);
      expect(await secure.containsKey(key: AppString.masterKey.string), isTrue);
      expect(await ModelProfile.get(), isNotNull);
      expect(await owned.exists(), isTrue);
      expect(await upload.exists(), isTrue);
      expect(await SyncUtils.checkDeviceStatus(), isTrue);
      expect(
          await secure.containsKey(key: AppString.masterKey.string), isFalse);
      expect(await ModelProfile.get(), isNull);
      expect(await owned.exists(), isFalse);
      expect(await upload.exists(), isFalse);
      expect(await external.readAsString(), 'external original is preserved');
      expect(await SessionCleanup.instance.pending, isFalse);
    } finally {
      if (await external.exists()) await external.delete();
      expect(await SessionCleanup.instance.request(), isTrue);
      // No transfer is created by this fixture. Remove only its generated
      // development account so another native platform can run independently.
      expect(
          (await client(peerUuid)
              .post(endpoint: '/local-test/reset', jsonBody: {}))['success'],
          1);
    }
  });

  testWidgets('LAN email sign-in registers the device without an OTP',
      (tester) async {
    markNativeCheckpoint(NativeTestCheckpoint.setup);
    await verifyNativeTestInstall();
    await addTrustedCertificates();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    expect(await SessionCleanup.instance.request(), isTrue);
    await ModelSetting.set(AppString.locale.string, 'en');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    final bootstrap = BackendApi(
        localTestingProvider: () => true,
        deviceUuidProvider: () async => '',
        refreshAuth: () async {});
    expect((await bootstrap.get(endpoint: '/keys'))['message'], 1);
    if (Platform.isAndroid) ServiceForeground.instance.init();
    final setup = AppSetupState(SecureStorage());
    final locale = LocaleProvider();
    Future<void> until(Future<bool> Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        if (await ready()) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      expect(await ready(), isTrue);
    }

    try {
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider.value(value: setup),
        ChangeNotifierProvider.value(value: locale)
      ], child: const MyApp()));
      await until(() async => find.byType(PageSignin).evaluate().isNotEmpty);
      markNativeCheckpoint(NativeTestCheckpoint.signIn);
      final email = find.byType(TextFormField);
      if (kProfileMode) {
        // The detached physical iPhone runner uses AOT profile mode. Its real
        // text-input connection ignores the debug-only -1 client used by
        // enterText/receiveAction, so supply the field value in the harness and
        // exercise the actual form validation and submit button below.
        tester.widget<TextFormField>(email).controller!.text = localTestEmailId;
        await tester.pump();
      } else {
        await tester.enterText(email, localTestEmailId);
      }
      final submit = find.descendant(
          of: find.byType(PageSignin), matching: find.byType(FilledButton));
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
      await until(
          () async => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty);
      expect((await ModelProfile.get())?.email, localTestEmailId);
      expect(localTesting(), isTrue);
      expect(simulateTesting(), isFalse);
      expect(await ModelSetting.getRaw(AppString.otpSentAt.string), isEmpty);
      expect(
          await SecureStorage()
              .containsKey(key: AppString.sessionCookie.string),
          isFalse);
      markNativeCheckpoint(NativeTestCheckpoint.keys);
      await tester.tap(find.descendant(
          of: find.byType(PageAccessKeyNotice),
          matching: find.byType(FilledButton)));
      await until(() async => find.byType(PageAccessKey).evaluate().isNotEmpty);
      final next = find.widgetWithText(OutlinedButton, 'Continue');
      await until(() async =>
          next.evaluate().isNotEmpty &&
          tester.widget<OutlinedButton>(next).onPressed != null);
      await tester.ensureVisible(next);
      markNativeCheckpoint(NativeTestCheckpoint.registration);
      await tester.tap(next);
      await until(() async =>
          (await getDeviceUuid()).isNotEmpty &&
          ![SetupStep.registerDevice, SetupStep.loading]
              .contains(setup.currentStep));
      final uuid = await getDeviceUuid();
      expect(uuid.isNotEmpty, isTrue);
      expect(
          (await BackendApi().get(
              endpoint: '/devices',
              queryParameters: {'device_uuid': uuid}))['data']['active'],
          1);
      if (Platform.isAndroid) {
        final permission = await getStoragePermissionStatus();
        if (const bool.fromEnvironment(
            'FIFE_REQUIRE_AUTOMATIC_SERVICE_START')) {
          expect(permission.isGranted, isTrue,
              reason: 'Automatic-start acceptance requires an existing or '
                  'explicitly temporary test storage grant');
        }
        if (permission.isGranted) {
          expect(setup.currentStep, SetupStep.explorer);
        } else {
          // Do not grant broad device storage merely for this fixture. Verify
          // onboarding keeps its real permission gate; the controlled service
          // checks below access only app-owned data and need no such grant.
          expect(setup.currentStep, SetupStep.storagePermission);
          expect(await FlutterForegroundTask.isRunningService, isFalse);
          await ServiceForeground.instance.start();
        }
        await until(() async => FlutterForegroundTask.isRunningService);
        expect(ModelSetting.foregroundSyncIntervalMinutes, 15);
      } else {
        expect(setup.currentStep, SetupStep.explorer);
      }

      final navigator =
          Navigator.of(tester.element(find.byType(Scaffold).first));
      markNativeCheckpoint(NativeTestCheckpoint.settings);
      // Keep the ordinary setup/navigation while exercising the real settings
      // widget; all platform decisions remain in application code.
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => SettingsPage(onThemeChange: (_) {})));
      await until(() async => find.byType(SettingsPage).evaluate().isNotEmpty);
      if (Platform.isAndroid) {
        final slider = find.byType(Slider);
        await tester.ensureVisible(slider);
        await tester.pump();
        expect(tester.widget<Slider>(slider).min, 1);
        expect(tester.widget<Slider>(slider).max, 30);
        expect(tester.widget<Slider>(slider).value, 15);
        await Future<void>.delayed(const Duration(seconds: 3));
        markNativeCheckpoint(NativeTestCheckpoint.sliderMax);
        await tester.drag(slider, const Offset(1000, 0));
        await until(() async =>
            await ModelSetting.getForegroundSyncIntervalMinutes() == 30 &&
            tester.widget<Slider>(slider).onChanged != null);
        await Future<void>.delayed(const Duration(seconds: 3));
        markNativeCheckpoint(NativeTestCheckpoint.sliderMin);
        final track = tester.getRect(slider);
        await tester.dragFrom(
            Offset(track.right - 24, track.center.dy), Offset(-track.width, 0));
        await until(() async =>
            await ModelSetting.getForegroundSyncIntervalMinutes() == 1 &&
            tester.widget<Slider>(slider).onChanged != null);
        await Future<void>.delayed(const Duration(seconds: 3));
        final lease =
            await ExclusiveOperationCoordinator.tryAcquire('metadata');
        expect(lease, isNotNull);
        markNativeCheckpoint(NativeTestCheckpoint.notificationProgress);
        EventStream().publish(AppEvent(
            type: EventType.system, id: 'metadata', key: EventKey.running));
        try {
          expect(await isRecordOrSyncInProgress(), isTrue);
          await Future<void>.delayed(const Duration(seconds: 5));
        } finally {
          await lease!.release();
          EventStream().publish(AppEvent(
              type: EventType.system, id: 'metadata', key: EventKey.stopped));
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        await ServiceForeground.instance.stop();
        markNativeCheckpoint(NativeTestCheckpoint.notificationLocale);
        await ModelSetting.set(AppString.locale.string, 'hi');
        await ServiceForeground.instance.start();
        final loc = lookupAppLocalizations(const Locale('hi'));
        expect(loc.quickSyncNotificationTitle.isNotEmpty, isTrue);
        await Future<void>.delayed(const Duration(seconds: 3));
      } else {
        expect(find.byType(AutoSyncIntervalSetting), findsNothing);
      }
      expect(tester.takeException(), isNull);
      markNativeCheckpoint(NativeTestCheckpoint.complete);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
      if (Platform.isAndroid) await ServiceForeground.instance.stop();
      SyncUtils().stopAutoSync();
      await ModelSetting.set(AppString.locale.string, 'en');
      // MyApp disposal closes its shared HTTP clients. Cleanup must obtain a
      // fresh one rather than reuse the pre-onboarding bootstrap connection.
      final cleanupApi = BackendApi(
          localTestingProvider: () => true,
          deviceUuidProvider: () async => '',
          refreshAuth: () async {});
      final remaining = await cleanupApi.get(endpoint: '/keys');
      if (remaining['success'] == 1) {
        expect(
            (await cleanupApi
                .post(endpoint: '/local-test/reset', jsonBody: {}))['success'],
            1);
      } else {
        expect(remaining['message'], 1);
      }
      expect(await SessionCleanup.instance.request(), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
