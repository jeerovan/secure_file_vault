import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show DartPluginRegistrant, RootIsolateToken;

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_recovery_reset.dart';
import 'package:file_vault_bb/services/service_vault_key_setup.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_display.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../test/support/recovery_reset_fixture.dart';
import 'support/iphone_results.dart';
import 'support/native_test_install.dart';

@pragma('vm:entry-point')
Future<void> cleanupInIndependentIsolate(List<Object> arguments) async {
  final reply = arguments[1] as SendPort;
  try {
    BackgroundIsolateBinaryMessenger.ensureInitialized(
        arguments[0] as RootIsolateToken);
    DartPluginRegistrant.ensureInitialized();
    await StorageSqlite.initialize(ExecutionMode.foregroundService);
    if (!await SessionCleanup.instance.resume()) {
      throw StateError('Pending cleanup');
    }
    final succeeded = await SessionCleanup.instance.request();
    // This isolate uses the UI engine's binary messenger and native SQLite
    // handles. The UI owns their lifetime; closing here can interrupt its
    // cleanup-completion reads and leave it on the retry screen.
    reply.send(succeeded ? 'cleaned' : 'pending');
  } catch (error) {
    // Never send key-store values or arbitrary native exception messages.
    reply.send('failed:${error.runtimeType}');
  }
}

@pragma('vm:entry-point')
void startNativeCleanupTestTask() {
  FlutterForegroundTask.setTaskHandler(_NativeCleanupTestTask());
}

class _NativeCleanupTestTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await StorageSqlite.initialize(ExecutionMode.foregroundService);
    final directory = await getApplicationSupportDirectory();
    await File('${directory.path}/fife-native-engine-fixture.json')
        .writeAsString(
            jsonEncode({
              'rootEngine': RootIsolateToken.instance != null,
              'foregroundService': StorageSqlite.executionMode ==
                  ExecutionMode.foregroundService,
            }),
            flush: true);
    if (await SessionCleanup.instance.resume()) {
      await SessionCleanup.instance.request();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

void main() {
  registerRecoveryNativeTests();
}

void registerRecoveryNativeTests({bool reportResults = true}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  }
  if (reportResults) recordIphoneResults(binding, 'recovery');
  final storage = SecureStorage();

  setUpAll(() async {
    expect(const bool.fromEnvironment('FIFE_RUN_RECOVERY_NATIVE_TESTS'), isTrue,
        reason: 'Native cleanup tests require an explicit disposable install');
    await verifyNativeTestInstall();
  });

  Future<void> until(WidgetTester tester, bool Function() ready,
      {String Function()? describe}) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 30)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Queue the frame after the live binding has installed its completion
      // future. Never timeout a guarded pump: it cannot be canceled safely.
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ready(), isTrue, reason: describe?.call());
  }

  Future<void> fresh() async {
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    expect(await SessionCleanup.instance.request(), isTrue);
  }

  testWidgets(
      'native isolate cleanup removes cached UI on discovery, keys and owned files',
      (tester) async {
    await fresh();
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'no');
    await ModelSetting.set(
        'managed_upload:native-fixture', 'private upload receipt fixture');
    await ModelSetting.set(
        'managed_cleanup:native-fixture', 'private cleanup receipt fixture');
    await (await ModelProfile.fromMap(
            {'id': 'native-fixture-user', 'email': 'native@example.test'}))
        .insert();
    await storage.write(
        key: AppString.masterKey.string,
        value: base64Encode(List<int>.filled(32, 7)));
    await storage.write(
        key: AppString.sessionCookie.string, value: 'native-fixture-cookie');
    final documents = await getApplicationDocumentsDirectory();
    final temporary = await getTemporaryDirectory();
    final owned = File('${documents.path}/FiFe/native-fixture/private.txt');
    await owned.parent.create(recursive: true);
    await owned.writeAsString('fixture private data');
    final external = File('${documents.path}/native-original-fixture.txt');
    await external.writeAsString('fixture original outside FiFe');
    final upload = File('${temporary.path}/${'A' * 43}_1.crypt.ready');
    await upload.writeAsString('fixture upload');
    final export = File('${temporary.path}/fife_access_key.txt');
    await export.writeAsString('fixture export');
    final unrelated = File('${temporary.path}/unrelated-native-fixture.txt');
    await unrelated.writeAsString('keep fixture');

    final setup = AppSetupState(storage);
    final locale = LocaleProvider();
    await until(tester, () => setup.currentStep == SetupStep.signin);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: setup),
      ChangeNotifierProvider.value(value: locale)
    ], child: const MyApp()));
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(PageSignin)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Text('Cached native private page')))));
    await tester.pumpAndSettle();
    if (Platform.isAndroid) ServiceForeground.instance.init();
    final release = Completer<void>();
    final entered = Completer<void>();
    final stale = expectLater(SessionWork.run(() async {
      entered.complete();
      await release.future;
      await storage.write(key: 'retired-native-key', value: 'must not return');
      await ModelSetting.set('retired-native-setting', 'must not return');
    }), throwsA(isA<SessionInvalidated>()));
    await entered.future;
    final result = ReceivePort();
    final isolate = await Isolate.spawn(cleanupInIndependentIsolate,
        <Object>[RootIsolateToken.instance!, result.sendPort]);
    try {
      expect(
          await result.first.timeout(const Duration(seconds: 40)), 'cleaned');
      if (!Platform.isAndroid) {
        // Android has an immediate native IPC wakeup. iOS/desktop discover
        // external cleanup through this same check on lifecycle resume.
        await SessionCleanup.instance.observeExternalState();
      }
      await until(
          tester,
          () =>
              find.text('Cached native private page').evaluate().isEmpty &&
              find.byType(PageSignin).evaluate().isNotEmpty);
      release.complete();
      await stale;
      expect(await storage.read(key: AppString.masterKey.string), isNull);
      expect(await storage.read(key: AppString.sessionCookie.string), isNull);
      expect(await storage.read(key: 'retired-native-key'), isNull);
      expect(await ModelProfile.get(), isNull);
      expect(await ModelSetting.getRaw('retired-native-setting'), isEmpty);
      expect(
          await ModelSetting.getRaw('managed_upload:native-fixture'), isEmpty);
      expect(
          await ModelSetting.getRaw('managed_cleanup:native-fixture'), isEmpty);
      expect(await owned.exists(), isFalse);
      expect(await upload.exists(), isFalse);
      expect(await export.exists(), isFalse);
      expect(await external.readAsString(), 'fixture original outside FiFe');
      expect(await unrelated.readAsString(), 'keep fixture');
      expect(await SessionCleanup.instance.pending, isFalse);
      expect(navigator.mounted, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      if (!release.isCompleted) release.complete();
      isolate.kill(priority: Isolate.immediate);
      result.close();
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
      await external.delete();
      await unrelated.delete();
    }
  });

  testWidgets(
      'native shared reset releases staging and fresh phrase acknowledgment gates registration',
      (tester) async {
    await fresh();
    await (await ModelProfile.fromMap(
            {'id': 'native-fixture-user', 'email': 'native@example.test'}))
        .insert();
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await storage.write(
        key: AppString.sessionCookie.string, value: 'native-fixture-cookie');
    await storage.write(
        key: AppString.jwtToken.string, value: 'native-fixture-token');
    final peer = RecoveryResetPeer();
    expect((await peer.service().confirm()).phase, RecoveryResetPhase.waiting);
    expect(await getMasterKey(), isNull);
    expect((await peer.service().refresh()).phase, RecoveryResetPhase.waiting);
    peer.phase = 'ready';
    expect(
        (await peer.service().refresh()).phase, RecoveryResetPhase.bootstrap);
    expect(
        await storage.read(key: AppString.recoveryResetStage.string), isNull);
    expect(await getMasterKey(), isNull);
    expect(await storage.read(key: AppString.sessionCookie.string),
        'native-fixture-cookie');
    Map<String, dynamic>? envelope;
    VaultKeySetupService setupService() => VaultKeySetupService.test(
        apiFactory: () => BackendApi(
            baseUrlOverride: 'https://api.example.test/api',
            refreshAuth: () async {},
            httpClient: MockClient((request) async {
              if (request.method == 'POST') {
                envelope = jsonDecode(request.body);
                return http.Response('{"success":1}', 200);
              }
              return http.Response(
                  jsonEncode({
                    'success': 1,
                    'data': {
                      ...?envelope,
                      'vault_generation': RecoveryResetPeer.generation
                    }
                  }),
                  200);
            })));
    var generated = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PageAccessKeyNotice(onGenerate: () async {
        expect(
            (await setupService().generate()).phase, VaultKeySetupPhase.phrase);
        generated = true;
      }),
    ));
    await tester.tap(find.descendant(
        of: find.byType(PageAccessKeyNotice),
        matching: find.byType(FilledButton)));
    await until(tester, () => generated);
    final staged = jsonDecode(
            (await storage.read(key: AppString.vaultKeySetupStage.string))!)
        as Map<String, dynamic>;
    expect((await setupService().resume()).phase, VaultKeySetupPhase.phrase);
    expect(await storage.read(key: AppString.masterKey.string),
        staged['privateKeys'][AppString.masterKey.string]);
    var acknowledged = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PageAccessKey(
          requireAcknowledgment: true,
          onAcknowledged: () async {
            await setupService().acknowledge();
            expect(
                await setupService().registrationUuid(), staged['deviceUuid']);
            acknowledged = true;
          }),
    ));
    await until(
        tester,
        () =>
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Copy'))
                .onPressed !=
            null);
    final next = find.widgetWithText(OutlinedButton, 'Continue');
    expect(tester.widget<OutlinedButton>(next).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await until(tester, () => acknowledged);
    expect(await ModelSetting.getRaw(AppString.pendingDeviceUuid.string),
        staged['deviceUuid']);
    expect(peer.confirmCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await fresh();
  });

  for (final switchedAccount in [true, false]) {
    testWidgets(
        'native interrupted key setup recovers after ${switchedAccount ? 'an account switch' : 'a newer vault reset'}',
        (tester) async {
      await fresh();
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      await ModelSetting.set(AppString.localTesting.string, 'yes');
      await ModelSetting.set(AppString.vaultGeneration.string, 'legacy');
      await (await ModelProfile.fromMap(
              {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
          .insert();
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
      expect((await service.generate()).phase, VaultKeySetupPhase.unavailable);
      final candidate =
          await storage.read(key: AppString.vaultKeySetupStage.string);
      expect(candidate != null, isTrue);
      offline = false;
      if (switchedAccount) {
        await (await StorageSqlite.instance.database).delete('profiles');
        await (await ModelProfile.fromMap(
                {'id': 'other-native-account', 'email': 'other@example.test'}))
            .insert();
      }
      final setup = AppSetupState(storage);
      try {
        await setup.recheckStatus();
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: setup,
            child: MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PageAccessKeyNotice(service: service))));
        await until(tester, () => setup.currentStep == SetupStep.signin,
            describe: () => 'Interrupted key setup step: '
                '${setup.currentStep.name}');
        expect(await getMasterKey(), isNull);
        expect(
            await ModelSetting.getRaw(AppString.signedIn.string), isNot('yes'));
        final retained =
            await storage.read(key: AppString.vaultKeySetupStage.string);
        expect(
            switchedAccount ? retained == candidate : retained == null, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        setup.dispose();
        expect(await SessionCleanup.instance.request(), isTrue);
      }
    });
  }

  testWidgets('native cleanup waits for another engine publication',
      (tester) async {
    await fresh();
    final documents = await getApplicationDocumentsDirectory();
    final published = File('${documents.path}/native-published-fixture.txt');
    final entered = Completer<void>();
    final release = Completer<void>();
    final publication =
        SessionWork.run(() => SessionCleanup.instance.withPublication(() async {
              entered.complete();
              await release.future;
              await published.writeAsString('completed external download');
              await SessionWork.checkpoint();
            }));
    await entered.future;
    final result = ReceivePort();
    final isolate = await Isolate.spawn(cleanupInIndependentIsolate,
        <Object>[RootIsolateToken.instance!, result.sendPort]);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(await SessionCleanup.instance.pending, isFalse);
      release.complete();
      await publication;
      expect(
          await result.first.timeout(const Duration(seconds: 40)), 'cleaned');
      expect(await SessionCleanup.instance.resume(), isTrue);
      expect(await published.readAsString(), 'completed external download');
      expect(await SessionCleanup.instance.pending, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await publication;
      isolate.kill(priority: Isolate.immediate);
      result.close();
      if (await published.exists()) await published.delete();
      await fresh();
    }
  });

  testWidgets('Android native foreground engine revocation clears local data',
      (tester) async {
    await fresh();
    final storage = SecureStorage();
    await (await ModelProfile.fromMap({
      'id': 'native-engine-fixture-user',
      'email': 'native-engine@example.test'
    }))
        .insert();
    await storage.write(
        key: AppString.masterKey.string,
        value: base64Encode(List<int>.filled(32, 17)));
    final documents = await getApplicationDocumentsDirectory();
    final owned = File('${documents.path}/FiFe/engine-fixture/private.txt');
    await owned.parent.create(recursive: true);
    await owned.writeAsString('owned engine fixture');
    final external = File('${documents.path}/engine-external-fixture.txt');
    await external.writeAsString('preserved original');
    final support = await getApplicationSupportDirectory();
    final proof = File('${support.path}/fife-native-engine-fixture.json');
    if (await proof.exists()) await proof.delete();
    ServiceForeground.instance.init();
    try {
      final started = await FlutterForegroundTask.startService(
          serviceId: 300,
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: 'FiFe cleanup test',
          notificationText: 'Testing disposable local data',
          callback: startNativeCleanupTestTask);
      expect(started, isNot(isA<ServiceRequestFailure>()));
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      var cleaned = false;
      while (DateTime.now().isBefore(deadline)) {
        if (await proof.exists() && !await owned.exists()) {
          // Owned-file removal precedes the billing step and lock release.
          // A competing main-engine resume can legitimately return retryable
          // false while the service is finishing. Require durable completion.
          cleaned = await SessionCleanup.instance.resume();
          if (cleaned &&
              !await SessionCleanup.instance.pending &&
              !await FlutterForegroundTask.isRunningService) {
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(await proof.exists(), isTrue);
      expect(jsonDecode(await proof.readAsString()),
          {'rootEngine': true, 'foregroundService': true});
      expect(cleaned, isTrue);
      expect(await storage.read(key: AppString.masterKey.string), isNull);
      expect(await ModelProfile.get(), isNull);
      expect(await owned.exists(), isFalse);
      expect(await external.readAsString(), 'preserved original');
      expect(await SessionCleanup.instance.pending, isFalse);
      expect(await FlutterForegroundTask.isRunningService, isFalse);
    } finally {
      await ServiceForeground.instance.stop();
      if (await proof.exists()) await proof.delete();
      if (await external.exists()) await external.delete();
      await fresh();
    }
  }, skip: !Platform.isAndroid);
}
