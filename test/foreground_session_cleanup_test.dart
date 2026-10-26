import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'service started after reset startup reconnects progress and revocation UI',
      (tester) async {
    final fixture = (await tester.runAsync(SyncFixture.create))!;
    const foreground = MethodChannel('flutter_foreground_task/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var running = false;
    messenger.setMockMethodCallHandler(foreground, (call) async {
      if (call.method == 'isRunningService') return running;
      if (call.method == 'startService') running = true;
      if (call.method == 'stopService') running = false;
      return null;
    });
    FlutterForegroundTask.skipServiceResponseCheck = true;
    final events = <EventKey>[];
    final subscription = EventStream().events.listen((event) {
      if (event.id == 'foregroundSync') events.add(event.key);
    });
    AppSetupState? setup;
    final locale = LocaleProvider();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      setup?.dispose();
      locale.dispose();
      await subscription.cancel();
      await ServiceForeground.instance.resetForTesting();
      FlutterForegroundTask.resetStatic();
      messenger.setMockMethodCallHandler(foreground, null);
      await tester.runAsync(fixture.dispose);
    });

    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 200 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ready(), isTrue);
    }

    await tester.runAsync(() async {
      // The real startup defers background initialization during a reset.
      await SecureStorage().write(
          key: AppString.recoveryResetStage.string, value: 'pending fixture');
      await initializeBackgroundExecution();
      expect(running, isFalse);
      // New keys have been saved and registration has retired reset staging.
      await SecureStorage().delete(key: AppString.recoveryResetStage.string);
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      setup = AppSetupState(SecureStorage());
      await until(() => setup!.currentStep == SetupStep.signin);
    });
    await tester.runAsync(() => tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider.value(value: setup!),
          ChangeNotifierProvider.value(value: locale),
        ], child: const MyApp())));
    final appLock = Provider.of<AppLockController>(
        tester.element(find.byType(MaterialApp)),
        listen: false);
    await tester.runAsync(() => until(() => appLock.ready));
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(PageSignin)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cached vault page')))));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      // Normal setup calls start without replaying startup initialization.
      await ServiceForeground.instance.start();
      expect(running, isTrue);
      FlutterForegroundTask.sendDataToMain(
          ForegroundSyncStateMessage.encode(isRunning: true));
      // Setup can be checked again while a service message is already queued.
      // Reusing a running service must not replace its live receive port.
      await ServiceForeground.instance.start();
      await until(() => events.isNotEmpty);
      expect(events, [EventKey.running]);

      // Rechecking setup while the service is running must retain one listener.
      await ServiceForeground.instance.start();
      FlutterForegroundTask.sendDataToMain(
          ForegroundSyncStateMessage.encode(isRunning: false));
      await until(() => events.length == 2);
      expect(events, [EventKey.running, EventKey.stopped]);

      // Shared marker and wakeup represent the independent service engine.
      await File('${fixture.directory.path}/fife-session-state.json')
          .writeAsString(
              jsonEncode({
                'revision': 'service-device-revoked',
                'pending': true,
                'mode': 'forced',
                'locale': 'en'
              }),
              flush: true);
      FlutterForegroundTask.sendDataToMain(sessionStateChangedMessage);
      await until(() => fixture.secrets.isEmpty);
      await until(() => setup!.currentStep == SetupStep.signin);
      expect(await SessionCleanup.instance.pending, isFalse);
    });
    await tester.pumpAndSettle();
    expect(find.byType(PageSignin), findsOneWidget);
    expect(find.text('Cached vault page'), findsNothing);
    expect(navigator.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });
}
