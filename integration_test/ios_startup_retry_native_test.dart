import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

import '../test/support/transfer_api.dart';
import 'support/iphone_results.dart';
import 'support/ios_fixture_bookmark.dart';
import 'support/native_test_install.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  recordIphoneResults(binding, 'ios-startup-retry', probeBackend: false);
  const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');

  testWidgets('default iOS startup and retry survive deferred work',
      (tester) async {
    await verifyNativeTestInstall();
    expect(Platform.isIOS, isTrue);
    expect(runId, startsWith('ios-startup-retry-'));
    expect(AppEnv.localTestAuthToken, isNotEmpty,
        reason: 'Controlled local HTTP still requires its fixture auth token');
    expect(Uri.parse(AppEnv.effectiveApiBaseUrl).host, endsWith('.test'));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Text('Checking sync recovery')))));
    await tester.runAsync(() async {
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      expect(await SessionCleanup.instance.resume(), isTrue);
      expect(await SessionCleanup.instance.request(), isTrue);
      final storage = SecureStorage();
      final documents = await getApplicationDocumentsDirectory();
      final temporary = await getTemporaryDirectory();
      final trace = File('${temporary.path}/fife-background-test-trace.json');
      final source = Directory('${documents.path}/$runId');
      expect(await source.exists(), isFalse);
      await source.create();
      final original = File('${source.path}/retry.txt');
      const contents = 'FiFe native retry. Synthetic content only.';
      addTearDown(() async {
        await TaskManager.stopBackgroundWakes();
        await BackgroundExecutionService.instance.cancelIosWork();
        await SessionCleanup.instance.resume();
        await SessionCleanup.instance.request();
        if (await original.exists()) {
          expect(await original.readAsString(), contents);
          await original.delete();
        }
        if (await source.exists()) {
          expect(await source.list().isEmpty, isTrue);
          await source.delete();
        }
      });
      await original.writeAsString(contents);
      final bookmark = await bookmarkIosFixtureDirectory(source.path);
      await storage.write(
          key: AppString.masterKey.string,
          value: base64Encode(List<int>.generate(32, (i) => i)));
      await storage.write(
          key: AppString.fileHashKey.string,
          value: base64Encode(List<int>.generate(32, (i) => 31 - i)));
      await storage.write(
          key: AppString.jwtToken.string, value: 'isolated-fixture-token');
      await (await ModelProfile.fromMap(
              {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
          .insert();
      await ModelSetting.set(AppString.localTesting.string, 'yes');
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      await ModelSetting.set(AppString.deviceUuid.string, 'fixture-$runId');
      await ModelSetting.set(AppString.deviceHash.string, 'fixture-device');
      await storage.write(
          key: AppString.recoveryResetStage.string, value: 'pending fixture');

      AppSetupState? setup;
      final traceStart = DateTime.now().millisecondsSinceEpoch;
      var phase = 'native-startup';
      Future<void> mark(String value) async {
        phase = value;
        await File('${documents.path}/fife-startup-retry-phase.json')
            .writeAsString(jsonEncode({'runId': runId, 'phase': phase}),
                flush: true);
      }

      Future<void> until(Future<bool> Function() ready,
          {Duration limit = const Duration(seconds: 20)}) async {
        final elapsed = Stopwatch()..start();
        while (!await ready() && elapsed.elapsed < limit) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(await ready(), isTrue);
      }

      Future<List<dynamic>> receipts() async {
        if (!await trace.exists()) return [];
        final all = jsonDecode(await trace.readAsString()) as List<dynamic>;
        return all
            .where((event) => (event['time'] as int) >= traceStart)
            .toList();
      }

      try {
        await mark('native-startup');
        // Actual startup function/default service/native callback registration;
        // do not supply scheduler.initialize() from this fixture.
        await application.initializeBackgroundExecution();
        await until(() async =>
            (await receipts()).any((e) => e['event'] == 'initialized'));
        expect(
            (await receipts()).any((e) => e['event'] == 'submitted'), isFalse);
        setup = AppSetupState(storage);
        await mark('pending-setup');
        await until(() async => setup!.currentStep == SetupStep.recoveryReset);
        // Fixture supplies unrelated acknowledged-key/device preconditions.
        // The transition under test is the normal setup readiness recheck.
        await storage.delete(key: AppString.recoveryResetStage.string);
        await setup.recheckStatus();
        expect(setup.currentStep, SetupStep.explorer);
        await until(() async => (await receipts()).any((e) =>
            e['event'] == 'queue' &&
            e['value'] is int &&
            (e['value'] as int) % 100 == 1));
        final schedulerProof = List<dynamic>.from(await receipts());
        await mark('create-source-metadata');

        await ModelItem.ensureVaultRoot();
        await (await ModelItem.fromMap({
          'id': 'fixture-device',
          'name': 'Native fixture device',
          'parent_id': 'fife',
          'is_folder': 1,
        }))
            .insert();
        final root = await ModelItem.fromMap({
          'id': 'root-$runId',
          'name': runId,
          'parent_id': 'fixture-device',
          'path': source.path,
          'bookmark': bookmark,
          'is_folder': 1,
        });
        await root.insert();
        await mark('discover-source');
        final scan = await ReconciliationService(await SodiumSumoInit.init())
            .reconcile(root);
        expect(scan.status, ReconciliationStatus.completed);
        final items = await StorageSqlite.instance.getAll('items');
        final row = items.singleWhere((e) => e['name'] == 'retry.txt');
        final task = (await ModelItemTask.get(row['id'] as String))!;
        task.state = TransferTaskState.retryWaiting;
        task.attemptCount = 1;
        task.nextAttemptAt = DateTime.now().millisecondsSinceEpoch + 1000;
        await task.update(['state', 'attempt_count', 'next_attempt_at']);
        final lease =
            await ExclusiveOperationCoordinator.tryAcquire('metadata');
        expect(lease, isNotNull);
        var released = false;
        var wakes = 0;
        final times = <DateTime>[];
        final api = TransferApi(managed: true);
        final first = Completer<void>();
        try {
          await mark('retry-wake');
          AppHttpClients.closeAll();
          await http.runWithClient(() async {
            Future<void> wake() async {
              wakes++;
              times.add(DateTime.now());
              if (wakes == 1) {
                await SyncUtils().triggerSync(caller: 'TransferRetry');
                await lease!.release();
                released = true;
                first.complete();
              } else {
                await TaskManager.init(retryWakeHandler: wake);
              }
            }

            await TaskManager.init(retryWakeHandler: wake);
            await first.future.timeout(const Duration(seconds: 5));
            await until(() async => await ModelItemTask.get(task.id) == null);
            expect(wakes, 2);
            expect(times[1].difference(times[0]),
                greaterThanOrEqualTo(const Duration(seconds: 5)));
            final uploaded = await ModelItem.get(task.id);
            expect((await ModelFile.get(uploaded!.fileHash!))!.uploadedAt,
                greaterThan(0));
            expect(api.objects, isNotEmpty);
          },
              () => MockClient((request) async => request.method == 'HEAD'
                  ? http.Response('', 200)
                  : api.handle(request)));
        } finally {
          if (!released) await lease!.release();
          await TaskManager.stopBackgroundWakes();
          AppHttpClients.closeAll();
        }
        expect(await original.readAsString(), contents);
        await mark('cleanup');
        expect(await SessionCleanup.instance.request(), isTrue);
        expect(await original.readAsString(), contents);
        await until(() async =>
            (await receipts()).last['event'] == 'queue' &&
            (await receipts()).last['value'] == 0);
        final proof = {
          'runId': runId,
          'passed': true,
          'defaultStartupFunction': true,
          'defaultNativeScheduler': true,
          'realPendingRequestObserved': true,
          'schedulerReceipts': schedulerProof,
          'currentRunReceiptsOnly': true,
          'nativeTraceStart': traceStart,
          'realNativeSqliteKeychain': true,
          'realBusyMetadataLease': true,
          'actualRetryElapsedMs': times[1].difference(times[0]).inMilliseconds,
          'realEncryptedUploadWithControlledTransport': true,
          'cleanupCancelledScheduling': true,
          'externalOriginalPreserved': true,
          'limits': [
            'Fixture owns synthetic pending-reset/key/device/task preconditions.',
            'Startup function and normal AppSetupState recheck are exercised; a complete normal launcher/reset/login journey is separate.',
            'Native submission is observed; OS-selected worker delivery is not invoked or claimed.',
            'The follow-up handler invokes TaskManager directly; full normal sync metadata wiring is a separate journey.'
          ],
        };
        await File('${documents.path}/fife-startup-retry-result.json')
            .writeAsString(jsonEncode(proof), flush: true);
        await mark('complete');
      } catch (error) {
        await File('${documents.path}/fife-startup-retry-phase.json')
            .writeAsString(
                jsonEncode({
                  'runId': runId,
                  'phase': phase,
                  'errorType': error.runtimeType.toString(),
                }),
                flush: true);
        rethrow;
      } finally {
        setup?.dispose();
        await TaskManager.stopBackgroundWakes();
        await BackgroundExecutionService.instance.cancelIosWork();
        await SessionCleanup.instance.resume();
        await SessionCleanup.instance.request();
        if (await original.exists()) await original.delete();
        if (await source.exists()) await source.delete();
      }
    });
  });
}
