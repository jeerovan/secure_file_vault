import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_recovery_phrase.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_channel.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/native_test_install.dart';
import 'support/macos_accessibility.dart';

/// Native transport/cleanup integration, NOT authentication evidence. Supplies
/// the native privacy ready-frame prerequisite directly, after the separate
/// owner-authenticated journey. Uses only synthetic words and the disposable
/// vault created by macos_folder_journey_native_test. The real Save sheet and
/// the default SessionCleanup actions remain in use.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
      'Mac Save cancellation and session cleanup retire native export',
      (tester) => withMacNativeAccessibility(binding, () async {
            await verifyNativeTestInstall();
            expect(Platform.isMacOS, isTrue);
            const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
            expect(runId, startsWith('mac-folders-'));
            final support = await getApplicationSupportDirectory();
            expect(await File('${support.path}/$runId-phase').readAsString(),
                'complete');
            await StorageSqlite.initialize(ExecutionMode.mainApp);
            expect(await SessionCleanup.instance.resume(), isTrue);
            final roots = await ModelItem.getAllSyncedFolders();
            expect(roots.length, 1);
            final access =
                await ChannelStorage.startAccessing(roots.single.bookmark!);
            expect(access, endsWith('/Replacement'));
            final signal = File('$access/$runId-cleanup-request');
            expect(await signal.exists(), isFalse);
            const privacy = SystemAppLockPrivacy();
            var active = false;
            final unwatch = await privacy.watchLifecycle(
                (state) => active = state == AppLifecycleState.resumed);
            await tester.pumpWidget(const MaterialApp(
                home: Scaffold(
                    body: Center(
                        child: Text('Synthetic Mac Save cancellation test')))));
            await privacy.setEnabled(true);
            addTearDown(() async {
              await RecoveryPhraseExportFiles.clear();
              await privacy.setEnabled(false);
              unwatch();
              await ChannelStorage.stopAccessing(access!);
            });
            var phase = 'await_active_test_window';
            void checkpoint(String next) {
              phase = next;
              debugPrint('FIFE_MAC_EXPORT_PHASE $next');
            }

            Future<void> until(FutureOr<bool> Function() ready) async {
              final watch = Stopwatch()..start();
              while (!await ready()) {
                if (watch.elapsed > const Duration(minutes: 3)) {
                  throw StateError('Timed out at $phase');
                }
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }

            final platform = NativeRecoveryPhrasePlatform();
            final words = List.filled(24, 'synthetic').join(' ');
            Future<String?> reserve() async {
              await until(() => active);
              await privacy.frameReady(allowNativeDocuments: true);
              return platform.reserveSave();
            }

            final canceledToken = await reserve();
            checkpoint('cancel_native_Save_sheet');
            final canceled = await platform
                .save(words, 'Synthetic cancellation', canceledToken)
                .timeout(const Duration(minutes: 3));
            expect(canceled, isFalse);
            expect(NativeRecoveryPhrasePlatform.saveInProgress, isFalse);
            await expectLater(
                RecoveryPhraseExportFiles.channel.invokeMethod<bool>(
                    'save', {'reservation': canceledToken, 'text': words}),
                throwsA(isA<PlatformException>()));
            checkpoint('PASS_cancel_retires_reservation');

            final obsolete = await reserve();
            final pending =
                platform.save(words, 'Synthetic cleanup race', obsolete);
            checkpoint('inspect_Save_sheet_then_signal_cleanup');
            // The external controller first observes the real sheet, then creates this
            // nonsecret test signal inside the already granted generated folder.
            await until(signal.exists);
            expect(NativeRecoveryPhrasePlatform.saveInProgress, isTrue);
            expect(await SessionCleanup.instance.request(), isTrue);
            expect(await pending.timeout(const Duration(seconds: 10)), isFalse);
            expect(NativeRecoveryPhrasePlatform.saveInProgress, isFalse);
            expect(await ModelProfile.get(), isNull);
            expect(await SessionCleanup.instance.pending, isFalse);
            await expectLater(
                RecoveryPhraseExportFiles.channel.invokeMethod<bool>(
                    'save', {'reservation': obsolete, 'text': words}),
                throwsA(isA<PlatformException>()));
            expect(await File('$access/fife_recovery_phrase.txt').exists(),
                isFalse);
            expect(await File('$access/sibling.txt').readAsString(),
                'Synthetic sibling backup\n');
            checkpoint(
                'PASS_real_session_cleanup_closes_sheet_rejects_late_save');
          }),
      timeout: const Timeout(Duration(minutes: 12)));
}
