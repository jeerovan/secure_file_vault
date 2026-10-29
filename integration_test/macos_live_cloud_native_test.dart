import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/managed_file_copies.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/synced_folder_access.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/pages/page_welcome.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'support/macos_accessibility.dart';
import 'support/native_test_identity.dart';

/// Owner-authorized live-cloud journey. Normal main, real Neon sign-in, native
/// folder picker, default networking/queue/crypto/storage; no injected state.
/// Only generated external files are selected or changed. Run again with the
/// same app identity to verify the saved session/grant after a process restart.
/// Private OTP/phrase input is consumed once from a loopback test controller;
/// it is never compiled, logged, included in assertions or copied to clipboard.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    ..shouldPropagateDevicePointerEvents = true;
  testWidgets(
      'Mac live-cloud small, multipart, modified and restored transfers',
      (tester) => withMacNativeAccessibility(binding, () async {
            const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
            const account = 'tojeevansingh@gmail.com';
            const largeDigest =
                String.fromEnvironment('FIFE_LIVE_LARGE_SHA256');
            final control = Uri.parse(
                const String.fromEnvironment('FIFE_LIVE_CONTROL_URL'));
            expect(control.host, '127.0.0.1');
            expect(control.scheme, 'http');
            final controller = HttpClient();
            addTearDown(() => controller.close(force: true));
            final folderName = 'FiFe-$runId';
            final originalText = 'Synthetic FiFe live Mac check $runId v1\n';
            final modifiedText =
                'Synthetic FiFe live Mac check $runId v2 modified\n';
            expect(Platform.isMacOS, isTrue);
            expect(
                const bool.fromEnvironment('FIFE_RUN_MAC_LIVE_CLOUD'), isTrue);
            expect(AppEnv.localTestingBuild, isFalse);
            expect(Uri.parse(AppEnv.effectiveApiBaseUrl).scheme, 'https');
            expect(Uri.parse(AppEnv.neonAuthUrl).scheme, 'https');
            expect(runId, matches(RegExp(r'^mac-live-[a-f0-9]{10}$')));
            expect(largeDigest, matches(RegExp(r'^[a-f0-9]{64}$')));
            final bundle = (await PackageInfo.fromPlatform()).packageName;
            expect(isIsolatedNativeTestBundle(bundle), isTrue);
            final support = await getApplicationSupportDirectory();
            expect(support.path.contains(bundle), isTrue);
            final report = File('${support.path}/$runId-progress.json');
            final finished = File('${support.path}/$runId-complete');
            final checks = <String, bool>{};
            final metrics = <String, Object>{};
            var phase = 'normal_main';
            Future<void> checkpoint(String next) async {
              phase = next;
              await report.writeAsString(
                  jsonEncode({
                    'runId': runId,
                    'phase': phase,
                    'checks': checks,
                    'metrics': metrics,
                    'time': DateTime.now().toUtc().toIso8601String(),
                  }),
                  flush: true);
              final request = await controller
                  .postUrl(control.resolve('${control.path}/progress'));
              request.headers.contentType = ContentType.json;
              final payload = await report.readAsBytes();
              request.contentLength = payload.length;
              request.add(payload);
              final response = await request.close();
              await response.drain<void>();
              expect(response.statusCode, 204);
              debugPrint('FIFE_MAC_LIVE_PHASE $next');
            }

            Future<void> until(FutureOr<bool> Function() ready,
                {Duration timeout = const Duration(minutes: 5)}) async {
              final clock = Stopwatch()..start();
              while (!await ready()) {
                if (clock.elapsed > timeout) {
                  throw StateError('Timed out at $phase');
                }
                await Future<void>.delayed(const Duration(milliseconds: 150));
              }
            }

            Future<void> tap(Finder target) async {
              await until(() => target.evaluate().length == 1);
              await tester.ensureVisible(target);
              await until(() {
                final hits = target.hitTestable().evaluate().toList();
                if (hits.length != 1) return false;
                final route = ModalRoute.of(hits.single);
                return (route?.isCurrent ?? true) &&
                    (route?.animation?.isCompleted ?? true);
              });
              await tester.tap(target.hitTestable());
            }

            Future<void> enter(Finder field, String text) async {
              await tap(field);
              final editable = tester.state<EditableTextState>(find.descendant(
                  of: field,
                  matching: find.byType(EditableText),
                  matchRoot: true));
              await until(() => editable.widget.focusNode.hasFocus);
              editable.updateEditingValue(TextEditingValue(
                  text: text,
                  selection: TextSelection.collapsed(offset: text.length)));
            }

            Future<String?> privateValue(String kind) async {
              final request = await controller
                  .getUrl(control.resolve('${control.path}/input/$kind'));
              final response = await request.close();
              final body = await utf8.decoder.bind(response).join();
              if (response.statusCode == 204) return null;
              if (response.statusCode != 200) {
                throw StateError('Private input controller unavailable');
              }
              final data = jsonDecode(body) as Map<String, dynamic>;
              if (data['runId'] != runId ||
                  data['kind'] != kind ||
                  data['value'] is! String) {
                throw StateError(
                    'Private test input did not match this operation');
              }
              return data['value'] as String;
            }

            await checkpoint('normal_main');
            await application.main();
            var sentOtp = false;
            final setupClock = Stopwatch()..start();
            while (find.byType(FilePane).evaluate().isEmpty) {
              if (setupClock.elapsed > const Duration(minutes: 15)) {
                throw StateError('Sign-in did not finish at $phase');
              }
              if (find.byType(FiFeOnboardingScreen).evaluate().isNotEmpty) {
                await checkpoint('onboarding');
                await until(() => find
                    .descendant(
                        of: find.byType(FiFeOnboardingScreen),
                        matching: find.byType(PageView))
                    .evaluate()
                    .isNotEmpty);
                final view = tester.widget<PageView>(find.descendant(
                    of: find.byType(FiFeOnboardingScreen),
                    matching: find.byType(PageView)));
                final before = view.controller!.page!.round();
                await tap(find.descendant(
                    of: find.byType(FiFeOnboardingScreen),
                    matching: find.byType(FilledButton)));
                await until(() =>
                    find.byType(FiFeOnboardingScreen).evaluate().isEmpty ||
                    (view.controller!.hasClients &&
                        ((view.controller!.page ?? -1) - before - 1).abs() <
                            0.001));
              } else if (find
                  .byType(PageAccessKeyNotice)
                  .evaluate()
                  .isNotEmpty) {
                throw StateError(
                    'Existing account requested new keys; stopped without generating');
              } else if (find
                  .byType(PageAccessKeyDecode)
                  .evaluate()
                  .isNotEmpty) {
                if (phase != 'recovery_phrase_required') {
                  await checkpoint('recovery_phrase_required');
                }
                final phrase = await privateValue('phrase');
                if (phrase != null) {
                  final loc = AppLocalizations.of(
                      tester.element(find.byType(PageAccessKeyDecode)))!;
                  await enter(
                      find.descendant(
                          of: find.byType(PageAccessKeyDecode),
                          matching: find.byType(TextFormField)),
                      phrase);
                  await tap(find.widgetWithText(FilledButton, loc.verify));
                  await checkpoint('recovery_phrase_submitted');
                  await until(() =>
                      find.byType(PageAccessKeyDecode).evaluate().isEmpty ||
                      find.byType(AlertDialog).evaluate().isNotEmpty);
                  if (find.byType(AlertDialog).evaluate().isNotEmpty) {
                    throw StateError(
                        'Configured phrase was rejected; owner input required');
                  }
                }
              } else if (find.byType(PageSignin).evaluate().isNotEmpty) {
                final loc = AppLocalizations.of(
                    tester.element(find.byType(PageSignin)))!;
                if (!sentOtp && find.text(loc.sendOtp).evaluate().isNotEmpty) {
                  await checkpoint('sign_in');
                  await enter(
                      find.descendant(
                          of: find.byType(PageSignin),
                          matching: find.byType(TextFormField)),
                      account);
                  final send = find.widgetWithText(FilledButton, loc.sendOtp);
                  await until(() =>
                      tester.widget<FilledButton>(send).onPressed != null);
                  await tap(send);
                  sentOtp = true;
                  await until(
                      () => find.text(loc.enterOtpLabel).evaluate().isNotEmpty);
                }
                if (find.text(loc.enterOtpLabel).evaluate().isNotEmpty) {
                  if (phase != 'email_otp_required') {
                    await checkpoint('email_otp_required');
                  }
                  final code = await privateValue('otp');
                  if (code != null) {
                    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                      throw StateError('Invalid OTP format');
                    }
                    await enter(
                        find.descendant(
                            of: find.byType(PageSignin),
                            matching: find.byType(TextFormField)),
                        code);
                    await tap(find.widgetWithText(FilledButton, loc.verifyOtp));
                    await checkpoint('otp_submitted');
                    await until(
                        () => find.byType(PageSignin).evaluate().isEmpty);
                  }
                }
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
            expect((await ModelProfile.get())?.email?.toLowerCase() == account,
                isTrue,
                reason: 'Only the owner-authorized account may be used');
            expect(localTesting(), isFalse);
            expect(simulateTesting(), isFalse);
            checks['production_auth_and_normal_setup'] = true;
            final loc =
                AppLocalizations.of(tester.element(find.byType(FilePane)))!;
            final device = await getDeviceHash();
            final db = await StorageSqlite.instance.database;
            Future<ModelItem?> named(String parent, String name) async {
              final rows = await db.query('items',
                  where: 'parent_id = ? AND name = ? AND archived_at = 0',
                  whereArgs: [parent, name]);
              if (rows.length > 1) {
                throw StateError('Ambiguous generated test item');
              }
              return rows.isEmpty ? null : ModelItem.fromMap(rows.single);
            }

            Finder row(String id) => find.byKey(ValueKey(id));
            Future<void> currentDevice() async {
              await tap(find.descendant(
                  of: find.byType(BreadcrumbTrail),
                  matching: find.text('FiFe')));
              await tap(row(device));
              await until(
                  () => find.byIcon(LucideIcons.plus).evaluate().isNotEmpty);
            }

            Future<void> sync() async {
              await tap(find.byIcon(LucideIcons.moreVertical));
              await tap(find.widgetWithText(PopupMenuItem<int>, loc.sync));
            }

            await currentDevice();
            var root = await named(device, folderName);
            if (root == null) {
              await checkpoint('select_generated_folder_in_native_picker');
              await tap(find.byIcon(LucideIcons.plus));
              await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
              expect(
                  find.descendant(
                      of: find.byType(AlertDialog),
                      matching: find.text(folderName)),
                  findsOneWidget);
              await tap(find.widgetWithText(TextButton, loc.confirm));
              await until(() async => await named(device, folderName) != null);
              root = await named(device, folderName);
            }
            final rootId = root!.id;
            Future<ModelItem> child(String name) async {
              await until(() async => await named(rootId, name) != null);
              return (await named(rootId, name))!;
            }

            final small = await child('small.txt');
            final large = await child('multipart.bin');
            Future<ModelFile> uploaded(String id) async {
              await until(() async {
                final item = await ModelItem.get(id);
                if (item?.fileHash == null) return false;
                final file = await ModelFile.get(item!.fileHash!);
                return file != null &&
                    file.uploadedAt > 0 &&
                    await ModelItemTask.get(id) == null;
              }, timeout: const Duration(minutes: 8));
              return (await ModelFile.get(
                  (await ModelItem.get(id))!.fileHash!))!;
            }

            if (await finished.exists()) {
              await checkpoint('restart_saved_session_and_grant');
              expect(await SyncedFolderAccess.isAvailable(root), isTrue);
              expect(
                  await LocalItemAccess.withAccess(
                      small.id, (p) => File(p).readAsString()),
                  modifiedText);
              // A newly created file must reach the live cloud after restart;
              // merely seeing retained uploaded_at values would not prove that
              // the saved session can authorize new work.
              await checkpoint('add_generated_restart_probe');
              await until(() async =>
                  await LocalItemAccess.withAccess(
                      rootId, (p) => File('$p/restart-probe.txt').exists()) ==
                  true);
              await sync();
              final probe = await child('restart-probe.txt');
              await uploaded(probe.id);
              expect(
                  await LocalItemAccess.withAccess(
                      probe.id, (p) => File(p).readAsString()),
                  'Synthetic restart probe $runId\n');
              checks['saved_session_native_grant_after_restart'] = true;
              checks['new_live_upload_after_restart'] = true;
              await checkpoint('PASS_restart');
              return;
            }
            await checkpoint('waiting_for_live_uploads');
            final initialSmall = await uploaded(small.id);
            final largeFile = await uploaded(large.id);
            expect(largeFile.parts, greaterThan(1));
            metrics['multipart_parts'] = largeFile.parts;
            metrics['provider_ids_used'] =
                {initialSmall.providerId, largeFile.providerId}.toList();
            expect(
                await LocalItemAccess.withAccess(
                    small.id, (p) => File(p).readAsString()),
                originalText);
            checks['initial_small_and_multipart_upload'] = true;
            await checkpoint('modify_generated_small_file');
            await until(() async =>
                await LocalItemAccess.withAccess(
                    small.id, (p) => File(p).readAsString()) ==
                modifiedText);
            await sync();
            await until(() async =>
                (await ModelItem.get(small.id))!.fileHash != initialSmall.id);
            await uploaded(small.id);
            checks['modified_file_new_cloud_revision'] = true;
            await checkpoint('move_generated_folder_to_test_Trash');
            await until(
                () async => !await SyncedFolderAccess.isAvailable(root!));
            await tap(row(rootId));
            await tap(find.byIcon(LucideIcons.arrowLeft));
            await until(() => find
                .descendant(
                    of: row(rootId),
                    matching: find.byIcon(LucideIcons.alertCircle))
                .evaluate()
                .isNotEmpty);
            await tester.longPress(row(rootId));
            await tap(find.byTooltip(loc.download));
            await checkpoint('download_and_verify_live_ciphertext');
            for (final item in [small, large]) {
              await until(
                  () async =>
                      await ManagedFileCopies.existingPath(item.id) != null &&
                      await ModelItemTask.get(item.id) == null,
                  timeout: const Duration(minutes: 8));
            }
            final smallCopy = (await ManagedFileCopies.existingPath(small.id))!;
            final largeCopy = (await ManagedFileCopies.existingPath(large.id))!;
            expect(
                await File(smallCopy).readAsString() == modifiedText, isTrue);
            expect(
                (await sha256.bind(File(largeCopy).openRead()).first)
                        .toString() ==
                    largeDigest,
                isTrue);
            expect(await File(largeCopy).length(), 36 * 1024 * 1024);
            checks['downloaded_modified_and_multipart_bytes_match'] = true;
            await checkpoint('restore_generated_folder_from_test_Trash');
            await until(
                () async => await SyncedFolderAccess.isAvailable(root!));
            await currentDevice();
            await tester.longPress(row(rootId));
            // Once the original grant works again, normal source reads win. The
            // disconnected-copy cleanup itself was verified in MP-T4.
            expect(
                await LocalItemAccess.withAccess(
                    small.id, (p) => File(p).readAsString()),
                modifiedText);
            await finished.writeAsString('restart-required', flush: true);
            await checkpoint('PASS_live_transfers_restart_required');
          }),
      timeout: const Timeout(Duration(minutes: 45)));
}
