import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'recovery_native_test.dart'
    show cleanupInIndependentIsolate, startNativeCleanupTestTask;
import 'support/native_test_install.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final nativeEngine in [true, false]) {
    testWidgets(
        'deferred reset startup reconnects cleanup: native engine=$nativeEngine',
        (tester) async {
      await verifyNativeTestInstall();
      debugPrint('Native foreground fixture: isolated install verified');
      expect(Platform.isAndroid, isTrue);
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      expect(await SessionCleanup.instance.resume(), isTrue);
      expect(await SessionCleanup.instance.request(), isTrue);
      debugPrint('Native foreground fixture: initial cleanup completed');
      final storage = SecureStorage();
      await storage.write(
          key: AppString.recoveryResetStage.string, value: 'pending fixture');
      await initializeBackgroundExecution();
      debugPrint('Native foreground fixture: startup deferred during reset');
      expect(await FlutterForegroundTask.isRunningService, isFalse);
      await storage.delete(key: AppString.recoveryResetStage.string);
      await storage.write(
          key: AppString.masterKey.string, value: 'disposable native fixture');
      await (await ModelProfile.fromMap(
              {'id': 'native-foreground-user', 'email': 'native@example.test'}))
          .insert();
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'no');
      await ModelSetting.set(
          'managed_upload:native-foreground', 'fixture receipt');
      final documents = await getApplicationDocumentsDirectory();
      final temporary = await getTemporaryDirectory();
      final owned = File('${documents.path}/FiFe/foreground-fixture.txt');
      await owned.parent.create(recursive: true);
      await owned.writeAsString('app-owned decrypted fixture');
      final upload = File('${temporary.path}/${'A' * 43}_1.crypt.ready');
      await upload.writeAsString('encrypted fixture part');
      final original =
          File('${documents.path}/foreground-original-fixture.txt');
      await original.writeAsString('preserved external original');

      final setup = AppSetupState(storage);
      final locale = LocaleProvider();
      final events = <EventKey>[];
      final subscription = EventStream().events.listen((event) {
        if (event.id == 'foregroundSync') events.add(event.key);
      });
      ReceivePort? result;
      Isolate? isolate;
      Future<void> until(String stage, bool Function() ready) async {
        final clock = Stopwatch()..start();
        while (!ready() && clock.elapsed < const Duration(seconds: 30)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(ready(), isTrue,
            reason: '$stage: step=${setup.currentStep}, '
                'active=${SessionWork.active}, events=$events');
        debugPrint('Native foreground fixture: $stage');
      }

      try {
        await until(
            'initial sign-in', () => setup.currentStep == SetupStep.signin);
        await tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider.value(value: setup),
          ChangeNotifierProvider.value(value: locale),
        ], child: const MyApp()));
        await tester.pumpAndSettle();
        final navigator = Navigator.of(tester.element(find.byType(PageSignin)));
        unawaited(navigator.push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cached vault page')))));
        await tester.pumpAndSettle();
        // Exercise normal startup, without manually calling service.init().
        await ServiceForeground.instance.start();
        expect(await FlutterForegroundTask.isRunningService, isTrue);
        debugPrint('Native foreground fixture: native service started');
        FlutterForegroundTask.sendDataToMain(
            ForegroundSyncStateMessage.encode(isRunning: true));
        await until(
            'service IPC connected', () => events.contains(EventKey.running));

        if (nativeEngine) {
          await ServiceForeground.instance.stop();
          final started = await FlutterForegroundTask.startService(
              serviceId: 300,
              serviceTypes: [ForegroundServiceTypes.dataSync],
              notificationTitle: 'FiFe cleanup test',
              notificationText: 'Testing disposable local data',
              callback: startNativeCleanupTestTask);
          expect(started, isNot(isA<ServiceRequestFailure>()));
        } else {
          result = ReceivePort();
          isolate = await Isolate.spawn(cleanupInIndependentIsolate,
              <Object>[RootIsolateToken.instance!, result.sendPort]);
          expect(await result.first.timeout(const Duration(seconds: 40)),
              'cleaned');
        }
        // The native wakeup must clear the running UI without a manual probe.
        await until(
            'sign-in after independent cleanup',
            () =>
                find.text('Cached vault page').evaluate().isEmpty &&
                find.byType(PageSignin).evaluate().isNotEmpty);
        expect(navigator.mounted, isFalse);
        expect(await storage.read(key: AppString.masterKey.string), isNull);
        expect(await ModelProfile.get(), isNull);
        expect(await ModelSetting.getRaw('managed_upload:native-foreground'),
            isEmpty);
        expect(await owned.exists(), isFalse);
        expect(await upload.exists(), isFalse);
        expect(await original.readAsString(), 'preserved external original');
        expect(await SessionCleanup.instance.pending, isFalse);
        expect(await FlutterForegroundTask.isRunningService, isFalse);
        if (nativeEngine) {
          final support = await getApplicationSupportDirectory();
          final engineProof =
              File('${support.path}/fife-native-engine-fixture.json');
          expect(jsonDecode(await engineProof.readAsString()),
              {'rootEngine': true, 'foregroundService': true});
        }
        expect(tester.takeException(), isNull);
      } finally {
        isolate?.kill(priority: Isolate.immediate);
        result?.close();
        await subscription.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        setup.dispose();
        locale.dispose();
        await ServiceForeground.instance.stop();
        if (await original.exists()) await original.delete();
        // Resume an external revision instead of masking an assertion failure
        // with a new cleanup request that requires an already active session.
        await SessionCleanup.instance.resume();
      }
    });
  }
}
