import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/managed_file_copies.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/synced_folder_access.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_trash.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/transfer_api.dart';
import 'support/native_http_overrides.dart';
import 'support/native_test_install.dart';
import 'support/macos_accessibility.dart';

// The same HTTP boundary supports the streaming downloader's dart:io API.
// It never substitutes native storage, bookmarks, queues, or task scheduling.
class _TransferHttp extends NativeFixtureHttpOverrides {
  _TransferHttp(super.respond)
      : super(allowedHosts: const {
          'backend.example.test',
          'bucket.example.test',
          'one.one.one.one',
          'icanhazip.com',
          'ajax.googleapis.com',
          'captive.apple.com',
        });
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _StreamClient(super.createHttpClient(context));
}

class _StreamClient implements HttpClient {
  _StreamClient(this.inner);
  final HttpClient inner;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      inner.openUrl(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Run twice in the SAME disposable bundle. The first launch selects and uploads
/// an external generated folder; the second proves its saved native grant after
/// process restart, then exercises the real Explorer actions. The controller
/// moves only the generated source into a generated .Trash directory between
/// checkpoints and operates the real NSOpenPanel. No bookmark/queue is seeded.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    ..shouldPropagateDevicePointerEvents = true;
  testWidgets(
      'Mac external folder restart, recovery copies and reconnect',
      (tester) => withMacNativeAccessibility(binding, () async {
            await verifyNativeTestInstall();
            expect(Platform.isMacOS, isTrue);
            expect(const bool.fromEnvironment('FIFE_RUN_MAC_FOLDER_JOURNEY'),
                isTrue);
            expect(AppEnv.effectiveApiBaseUrl, 'https://backend.example.test');
            const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
            expect(runId, startsWith('mac-folders-'));
            final support = await getApplicationSupportDirectory();
            final phaseFile = File('${support.path}/$runId-phase');
            final bucketFile =
                File('${support.path}/$runId-encrypted-bucket.json');
            await StorageSqlite.initialize(ExecutionMode.mainApp);
            // Explicit fresh-run setup for this uniquely identified disposable
            // vault. Never repair folder/queue state partway through a journey.
            if (const bool.fromEnvironment('FIFE_RESET_MAC_FOLDER_JOURNEY')) {
              expect(await SessionCleanup.instance.request(), isTrue);
              for (final file in [phaseFile, bucketFile]) {
                if (await file.exists()) await file.delete();
              }
            }
            final firstLaunch = !await phaseFile.exists();
            final api = TransferApi(managed: true);
            if (await bucketFile.exists()) {
              final saved = jsonDecode(await bucketFile.readAsString()) as Map;
              for (final entry in saved.entries) {
                api.objects[entry.key as String] =
                    base64Decode(entry.value as String);
              }
            }
            Future<void> persistBucket() => bucketFile.writeAsString(
                jsonEncode(api.objects
                    .map((key, value) => MapEntry(key, base64Encode(value)))),
                flush: true);
            HttpOverrides.global = _TransferHttp((request) async {
              if (request.method == 'HEAD') return http.Response('', 200);
              if (request.url.path.endsWith('/devices')) {
                return api.json({
                  'success': 1,
                  'data': {'active': 1}
                });
              }
              if (request.url.path.endsWith('/sync')) {
                return api.json({'success': 1, 'data': <String, dynamic>{}});
              }
              if (request.url.path.endsWith('/get-download-url')) {
                final body = jsonDecode(request.body) as Map;
                return api.json({
                  'success': 1,
                  'data': 'https://bucket.example.test/${body['file_id']}'
                });
              }
              final response = await api.handle(request);
              if (request.url.path.endsWith('/complete')) await persistBucket();
              return response;
            });
            final retainedProfile = await ModelProfile.get();
            if (retainedProfile == null) {
              expect(firstLaunch, isTrue);
              // Only unrelated authenticated-vault prerequisites are supplied. The
              // application must create folder metadata, grants, uploads and copies.
              await (await ModelProfile.fromMap({
                'id': AppEnv.localTestUserId,
                'email': localTestEmailId,
              }))
                  .insert();
              for (final entry in {
                AppString.signedIn: 'yes',
                AppString.onboarding: 'yes',
                AppString.localTesting: 'yes',
                AppString.deviceUuid: runId,
                AppString.deviceHash: runId,
                AppString.locale: 'en',
              }.entries) {
                await ModelSetting.set(entry.key.string, entry.value);
              }
              for (final key in [
                AppString.masterKey,
                AppString.fileHashKey,
                AppString.accessKey
              ]) {
                await SecureStorage().write(
                    key: key.string,
                    value: base64Encode(List<int>.filled(32, 0)));
              }
              await ModelItem.ensureVaultRoot();
              await (await ModelItem.fromMap({
                'id': runId,
                'name': 'Mac folder test',
                'parent_id': 'fife',
                'is_folder': 1
              }))
                  .insert();
            } else {
              expect(retainedProfile.id, AppEnv.localTestUserId);
            }
            var phase = 'normal_main';
            void checkpoint(String value) {
              phase = value;
              debugPrint('FIFE_MAC_FOLDER_PHASE $value');
            }

            Future<void> until(FutureOr<bool> Function() ready,
                {Duration timeout = const Duration(minutes: 3)}) async {
              final watch = Stopwatch()..start();
              while (!await ready()) {
                if (watch.elapsed > timeout) {
                  throw StateError('Timed out at $phase');
                }
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }

            Future<void> tap(Finder target) async {
              await until(() => target.evaluate().length == 1);
              await tester.ensureVisible(target);
              await until(() {
                final matches = target.hitTestable().evaluate().toList();
                if (matches.length != 1) return false;
                final route = ModalRoute.of(matches.single);
                return (route?.isCurrent ?? true) &&
                    (route?.animation?.isCompleted ?? true);
              });
              await tester.tap(target.hitTestable());
            }

            Finder row(String name) => find.byWidgetPredicate(
                (widget) => widget is FileListItem && widget.item.name == name);
            Future<void> select(String name) async {
              await until(() => row(name).hitTestable().evaluate().length == 1);
              await tester.longPress(row(name));
            }

            Future<ModelItem> item(String name) async {
              final rows = await (await StorageSqlite.instance.database)
                  .query('items', where: 'name = ?', whereArgs: [name]);
              expect(rows.length, 1);
              return ModelItem.fromMap(rows.single);
            }

            Future<void> copied(ModelItem value, String expected) async {
              await until(() async =>
                  await ManagedFileCopies.existingPath(value.id) != null &&
                  await ModelItemTask.get(value.id) == null);
              final path = (await ManagedFileCopies.existingPath(value.id))!;
              expect(p.isWithin(await ModelItem.getPathForItem('fife'), path),
                  isTrue);
              expect(
                  await LocalItemAccess.withReadableAccess(
                      value.id, (path) => File(path).readAsString()),
                  expected);
            }

            await application.main();
            await until(() => find.byType(FilePane).evaluate().isNotEmpty);
            final loc =
                AppLocalizations.of(tester.element(find.byType(FilePane)))!;
            // Normal Explorer starts at this device, not the all-devices root.
            await until(
                () => find.text('Mac folder test').evaluate().isNotEmpty);
            if (firstLaunch) {
              checkpoint('select_generated_Source_in_native_picker');
              await tap(find.byIcon(LucideIcons.plus));
              await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
              expect(find.text('Source'), findsOneWidget);
              await tap(find.widgetWithText(TextButton, loc.confirm));
              checkpoint('waiting_for_normal_upload');
              await until(() async {
                final db = await StorageSqlite.instance.database;
                final files = await db.query('files');
                return files.length == 2 &&
                    files.every((r) => (r['uploaded_at'] as int) > 0) &&
                    (await db.query('item_tasks')).isEmpty;
              });
              final root = await item('Source');
              expect(await SyncedFolderAccess.isAvailable(root), isTrue);
              expect(api.objects.length, 2);
              await persistBucket();
              await phaseFile.writeAsString('restart-required', flush: true);
              checkpoint('PASS_initial_grant_and_real_upload_restart_required');
              return;
            }
            expect(await phaseFile.readAsString(), 'restart-required');
            final root = await item('Source');
            final nested = await item('nested');
            final first = await item('nested.txt');
            final sibling = await item('sibling.txt');
            expect(await SyncedFolderAccess.isAvailable(root), isTrue);
            expect((await ModelFile.get(first.fileHash!))!.uploadedAt,
                greaterThan(0));
            checkpoint(
                'PASS_saved_native_grant_after_restart_move_Source_to_Trash');
            await until(
                () async => !await SyncedFolderAccess.isAvailable(root));
            // A normal navigate away/back refreshes rows after the external operation.
            await tap(row('Source'));
            await tap(find.byIcon(LucideIcons.arrowLeft));
            await until(() =>
                find.byIcon(LucideIcons.alertCircle).evaluate().isNotEmpty);
            await tap(row('Source'));
            await tap(row('nested'));
            await select('nested.txt');
            await until(
                () => find.byTooltip(loc.download).evaluate().isNotEmpty);
            expect(find.byTooltip(loc.info), findsOneWidget);
            await tap(find.byTooltip(loc.download));
            await copied(first, 'Synthetic nested backup\n');
            expect((await ManagedFileCopies.existingPath(first.id))!,
                endsWith('/Source/nested/nested.txt'));
            expect(await SyncedFolderAccess.isAvailable(root), isFalse);
            checkpoint('PASS_disconnected_file_download_hierarchy_readable');
            await tap(find.byIcon(LucideIcons.arrowLeft));
            await tap(find.byIcon(LucideIcons.arrowLeft));
            await until(() =>
                row('Source').evaluate().isNotEmpty ||
                row('nested').evaluate().isNotEmpty);
            if (row('nested').evaluate().isNotEmpty) {
              // An overlapping second Back may be ignored, but must never trim
              // the trail again while leaving the contents one level higher.
              expect(
                  tester
                      .widget<BreadcrumbTrail>(find.byType(BreadcrumbTrail))
                      .parentChilds
                      .last
                      .id,
                  root.id);
              await tap(find.byIcon(LucideIcons.arrowLeft));
            }
            await until(() => row('Source').evaluate().isNotEmpty);
            expect(
                tester
                    .widget<BreadcrumbTrail>(find.byType(BreadcrumbTrail))
                    .parentChilds
                    .last
                    .id,
                runId);
            checkpoint(
                'PASS_rapid_Back_keeps_contents_and_breadcrumb_together');
            await select('Source');
            await until(
                () => find.byTooltip(loc.reconnect).evaluate().isNotEmpty);
            expect(find.byTooltip(loc.archiveBackup), findsOneWidget);
            await tap(find.byTooltip(loc.download));
            await copied(sibling, 'Synthetic sibling backup\n');
            final firstCopy = (await ManagedFileCopies.existingPath(first.id))!;
            final siblingCopy =
                (await ManagedFileCopies.existingPath(sibling.id))!;
            await tap(row('Source'));
            await select('nested');
            await tap(find.byTooltip(loc.archiveBackup));
            await tap(find.widgetWithText(FilledButton, loc.archiveBackup));
            await until(
                () async => (await ModelItem.get(nested.id))!.archivedAt > 0);
            expect(await File(firstCopy).exists(), isFalse);
            expect(await File(siblingCopy).readAsString(),
                'Synthetic sibling backup\n');
            checkpoint('PASS_subfolder_archive_removed_only_its_copy');

            Future<void> restore(String name) async {
              await tap(find.byIcon(LucideIcons.moreVertical));
              await tap(find.widgetWithText(PopupMenuItem<int>, loc.trash));
              await until(() => find.byType(PageTrash).evaluate().isNotEmpty);
              await until(
                  () => find.text(name).hitTestable().evaluate().length == 1);
              await tester.longPress(find.text(name));
              await tap(find.byTooltip(loc.recover));
              await until(() => find.text(name).evaluate().isEmpty);
              await tap(find.byIcon(LucideIcons.arrowLeft));
            }

            await restore('nested');
            expect((await ModelItem.get(nested.id))!.archivedAt, 0);
            await tap(find.byIcon(LucideIcons.arrowLeft));
            await select('Source');
            await tap(find.byTooltip(loc.archiveBackup));
            await tap(find.widgetWithText(FilledButton, loc.archiveBackup));
            await until(
                () async => (await ModelItem.get(root.id))!.archivedAt > 0);
            expect(await File(siblingCopy).exists(), isFalse);
            await restore('Source');
            checkpoint('PASS_root_archive_cleanup_and_restore');
            await select('Source');
            await tap(find.byTooltip(loc.download));
            await copied(first, 'Synthetic nested backup\n');
            await copied(sibling, 'Synthetic sibling backup\n');
            final restoredCopy =
                (await ManagedFileCopies.existingPath(first.id))!;
            final managedRoot = Directory(p.dirname(p.dirname(restoredCopy)));
            final untracked = File('${managedRoot.path}/old-untracked.txt');
            await untracked.writeAsString('Synthetic old copy');
            await select('Source');
            checkpoint('select_generated_Replacement_in_native_picker');
            await tap(find.byTooltip(loc.reconnect));
            await until(() async {
              final current = (await ModelItem.get(root.id))!;
              return current.path!.endsWith('/Replacement') &&
                  await SyncedFolderAccess.isAvailable(current) &&
                  !await managedRoot.exists();
            });
            expect(await ManagedFileCopies.existingPath(first.id), isNull);
            expect(await ManagedFileCopies.existingPath(sibling.id), isNull);
            expect(await untracked.exists(), isFalse);
            await until(
                () => find.byIcon(LucideIcons.alertCircle).evaluate().isEmpty);
            await until(
                () async => (await ModelItemTask.get(first.id)) == null);
            expect(
                await LocalItemAccess.withReadableAccess(
                    first.id, (path) => File(path).readAsString()),
                'Replacement differs intentionally\n');
            await phaseFile.writeAsString('complete', flush: true);
            checkpoint(
                'PASS_reconnect_removes_entire_copy_and_preserves_replacement');
          }),
      timeout: const Timeout(Duration(minutes: 20)));
}
