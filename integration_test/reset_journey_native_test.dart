import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_display.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_lost_recovery.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_reset.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import 'support/native_test_install.dart';
import 'support/provider_test_inputs.dart';

/// Run staged against one disposable local account in two isolated native apps.
/// The runner preserves each app's SQLite/key store between stages. There are
/// no HTTP mocks, forced reset deadlines, or shortened scheduler intervals.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local two-device reset follows real UI, cloud and cleanup',
      (tester) async {
    await verifyNativeTestInstall();
    expect(Platform.isAndroid, isTrue);
    final inputs = await readNativeProviderInputs();
    expect(inputs.length, 1);
    final input = Map<String, dynamic>.from(inputs.single as Map);
    final stage = input['stage'] as String;
    expect(
        const {
          'peer-seed',
          'initiator-confirm',
          'peer-discover',
          'peer-create',
          'initiator-join',
        }.contains(stage),
        isTrue);
    final documents = await getApplicationDocumentsDirectory();
    final stateFile = File('${documents.path}/fife-reset-state.json');
    final resultFile = File('${documents.path}/fife-reset-result.json');
    final secure = SecureStorage();
    var state = await stateFile.exists()
        ? Map<String, dynamic>.from(jsonDecode(await stateFile.readAsString()))
        : <String, dynamic>{};

    Future<void> until(bool Function() condition,
        {Duration timeout = const Duration(seconds: 60),
        String reason =
            'Native reset UI did not reach the expected state'}) async {
      final elapsed = Stopwatch()..start();
      while (!condition() && elapsed.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(condition(), isTrue, reason: reason);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> boot({bool fresh = false}) async {
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      if (fresh) {
        expect(await SessionCleanup.instance.resume(), isTrue);
        expect(await SessionCleanup.instance.request(), isTrue);
        await ModelSetting.set(AppString.onboarding.string, 'yes');
        await ModelSetting.set(AppString.locale.string, 'en');
        // A normal user preference: this journey discovers revocation on start.
        await ModelSetting.set(AppString.syncWithNotification.string, 'no');
      }
      await application.main();
    }

    Future<void> signin() async {
      await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
      await tester.enterText(
          find.byType(TextFormField).first, localTestEmailId);
      await tap(find
          .descendant(
              of: find.byType(PageSignin), matching: find.byType(FilledButton))
          .first);
    }

    Future<String> acknowledgePhrase() async {
      await until(() => find.byType(PageAccessKey).evaluate().isNotEmpty);
      final copy = find.widgetWithText(FilledButton, 'Copy');
      await until(() => tester.widget<FilledButton>(copy).onPressed != null);
      final access = await secure.read(key: AppString.accessKey.string);
      expect(access != null && access.isNotEmpty, isTrue);
      final entropy = base64Decode(access!)
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      final phrase = bip39.entropyToMnemonic(entropy);
      expect(bip39.validateMnemonic(phrase), isTrue);
      final next = find.widgetWithText(OutlinedButton, 'Continue');
      expect(tester.widget<OutlinedButton>(next).onPressed == null, isTrue);
      await tap(find.byType(CheckboxListTile));
      await until(() => tester.widget<OutlinedButton>(next).onPressed != null);
      await tap(next);
      await until(() => find.byType(PageExplorer).evaluate().isNotEmpty);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      return phrase;
    }

    Future<String> generate() async {
      await until(() => find.byType(PageAccessKeyNotice).evaluate().isNotEmpty,
          // The real cleanup scheduler can need its next five-minute tick.
          timeout: const Duration(minutes: 8));
      final button = find.descendant(
          of: find.byType(PageAccessKeyNotice),
          matching: find.byType(FilledButton));
      await until(() => tester.widget<FilledButton>(button).onPressed != null);
      expect(await getMasterKey() == null, isTrue);
      await tap(button);
      return acknowledgePhrase();
    }

    Future<ModelItem> upload(String folder, List<int> bytes) async {
      final source = await Directory('${documents.path}/$folder').create();
      final path = File('${source.path}/fixture.bin');
      await path.writeAsBytes(bytes, flush: true);
      final db = await StorageSqlite.instance.database;
      final roots = await db.query('items',
          where: 'path = ? AND is_folder = 1', whereArgs: [source.path]);
      expect(roots.length, lessThanOrEqualTo(1));
      final rootId =
          roots.isEmpty ? const Uuid().v4() : roots.single['id'] as String;
      if (roots.isEmpty) {
        await db.insert('items', {
          'id': rootId,
          'parent_id': await getDeviceHash(),
          'name': folder,
          'path': source.path,
          'is_folder': 1,
        });
      }
      final recon = ReconciliationService(await SodiumSumoInit.init());
      final reconDeadline = Stopwatch()..start();
      var result = await recon.reconcile((await ModelItem.get(rootId))!);
      while (result.status == ReconciliationStatus.busy &&
          reconDeadline.elapsed < const Duration(minutes: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        result = await recon.reconcile((await ModelItem.get(rootId))!);
      }
      expect(result.status, ReconciliationStatus.completed);
      final rows = await db.query('items',
          where: 'root_id = ? AND is_folder = 0', whereArgs: [rootId]);
      expect(rows.length, 1);
      final item = await ModelItem.fromMap(rows.single);
      expect(await SyncUtils.pushMapChanges(), isTrue);
      final uploadDeadline = Stopwatch()..start();
      while (uploadDeadline.elapsed < const Duration(minutes: 2)) {
        final task = await ModelItemTask.get(item.id);
        if (task == null) break;
        if (task.state == TransferTaskState.running ||
            task.state == TransferTaskState.retryWaiting &&
                task.nextAttemptAt > DateTime.now().millisecondsSinceEpoch) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        await TaskManager()
            .checkInitUpload(task)
            .timeout(const Duration(seconds: 120));
      }
      expect(await ModelItemTask.get(item.id) == null, isTrue);
      final file = (await ModelFile.get(item.fileHash!))!;
      expect(file.providerId, 6);
      expect(file.uploadedAt, greaterThan(0));
      expect(await SyncUtils.pushMapChanges(), isTrue);
      return item;
    }

    Future<void> download(
        ModelItem item, File target, List<int> expected) async {
      await target.delete();
      await ModelItemTask.addTask(item.id, ItemTask.download.value);
      final downloadDeadline = Stopwatch()..start();
      while (downloadDeadline.elapsed < const Duration(minutes: 2)) {
        final task = await ModelItemTask.get(item.id);
        if (task == null) break;
        if (task.state == TransferTaskState.running ||
            task.state == TransferTaskState.retryWaiting &&
                task.nextAttemptAt > DateTime.now().millisecondsSinceEpoch) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        await TaskManager()
            .checkInitDownload(task)
            .timeout(const Duration(seconds: 120));
      }
      expect(await ModelItemTask.get(item.id) == null, isTrue);
      expect(await target.exists(), isTrue);
      expect(
          sha256.convert(await target.readAsBytes()).toString() ==
              sha256.convert(expected).toString(),
          isTrue);
    }

    final passed = <String, Object>{'stage': stage, 'passed': true};
    if (stage == 'peer-seed') {
      if (input['resumeSeed'] == true) {
        await boot();
        await until(() =>
            find.byType(PageExplorer).evaluate().isNotEmpty ||
            find.byType(PageAccessKey).evaluate().isNotEmpty);
        if (find.byType(PageAccessKey).evaluate().isNotEmpty) {
          await acknowledgePhrase();
        }
      } else {
        await boot(fresh: true);
        await signin();
        await generate();
      }
      // Session cleanup closes shared HTTP clients; obtain the current client
      // only after boot/sign-in, as the real provider settings screen does.
      final registration = await BackendApi()
          .post(endpoint: '/s3/add-account', jsonBody: input['providerFields']);
      expect(registration['success'] == 1, isTrue,
          reason: 'Disposable S3 connection registration failed');
      final protocol =
          await BackendApi().post(endpoint: '/uploads/protocol', jsonBody: {});
      expect(
          protocol['data'] is Map &&
              protocol['data']['protocol'] == 'managed-v1',
          isTrue);
      final bytes = List<int>.generate(512 * 1024 + 19, (i) => i % 251);
      final item = await upload('reset-original-source', bytes);
      final original =
          File('${documents.path}/reset-original-source/fixture.bin');
      await download(item, original, bytes);
      final owned = File('${documents.path}/FiFe/reset-downloaded/private.bin');
      await owned.parent.create(recursive: true);
      await original.copy(owned.path);
      final external = File(
          '/sdcard/Download/fife-reset-original-${AppEnv.localTestUserId}.bin');
      await external.writeAsBytes(bytes, flush: true);
      final temporary = await getTemporaryDirectory();
      final encrypted = File('${temporary.path}/${'Q' * 43}_1.crypt.ready');
      await encrypted.writeAsBytes([7, 9, 11], flush: true);
      final db = await StorageSqlite.instance.database;
      await db.insert('item_tasks', {
        'id': item.id,
        'task': ItemTask.upload.value,
        'state': 'retryWaiting',
        'next_attempt_at':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await ModelSetting.set(
          'managed_upload:reset-native-pending', 'fixture receipt');
      await ModelSetting.set(
          'managed_cleanup:reset-native-pending', 'fixture cleanup receipt');
      state = {
        'oldDeviceUuid': await getDeviceUuid(),
        'oldFileHash': item.fileHash,
        'oldStorageId': (await ModelFile.get(item.fileHash!))!.storageId,
        'ownedPath': owned.path,
        'externalPath': external.path,
        'encryptedPath': encrypted.path,
        'originalPath': original.path,
        'plaintextHash': sha256.convert(bytes).toString(),
      };
      passed.addAll(
          {'managedUploadAndDownload': true, 'pendingUploadSaved': true});
    } else if (stage == 'initiator-confirm') {
      await boot(fresh: true);
      await signin();
      await until(() => find.byType(PageAccessKeyDecode).evaluate().isNotEmpty);
      final cookie = await secure.read(key: AppString.sessionCookie.string);
      expect(cookie != null && cookie.startsWith(AppEnv.localSessionPrefix),
          isTrue);
      state['initiatingSessionHash'] =
          sha256.convert(utf8.encode(cookie!)).toString();
      await tap(find.text('Lost recovery phrase'));
      await until(() => find.byType(PageLostRecovery).evaluate().isNotEmpty);
      final confirm = find.descendant(
          of: find.byType(PageLostRecovery),
          matching: find.byType(FilledButton));
      await until(() => tester.widget<FilledButton>(confirm).onPressed != null);
      await tap(confirm);
      await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
      await tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await until(() => find.byType(PageRecoveryReset).evaluate().isNotEmpty);
      expect(find.byType(PageAccessKeyNotice).evaluate().isEmpty, isTrue);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      expect(await getMasterKey() == null, isTrue);
      expect((await secure.read(key: AppString.sessionCookie.string)) == cookie,
          isTrue);
      passed.addAll({
        'lostPhraseUiConfirmed': true,
        'waitingForVerifiedDeletion': true,
        'initiatorStayedSignedIn': true
      });
    } else if (stage == 'peer-discover') {
      expect(state['oldDeviceUuid'] is String, isTrue);
      await boot();
      await until(() => find.byType(PageSignin).evaluate().isNotEmpty);
      expect(await getMasterKey() == null, isTrue);
      expect(await secure.read(key: AppString.sessionCookie.string) == null,
          isTrue);
      expect(await ModelProfile.get() == null, isTrue);
      final db = await StorageSqlite.instance.database;
      for (final table in ['item_tasks', 'files', 'parts']) {
        expect((await db.query(table)).isEmpty, isTrue,
            reason: 'Retired local $table must be empty');
      }
      expect(await ModelSetting.getRaw('managed_upload:reset-native-pending'),
          isEmpty);
      expect(await ModelSetting.getRaw('managed_cleanup:reset-native-pending'),
          isEmpty);
      expect(await File(state['ownedPath'] as String).exists(), isFalse);
      expect(await File(state['encryptedPath'] as String).exists(), isFalse);
      for (final name in ['externalPath', 'originalPath']) {
        expect(
            sha256
                    .convert(await File(state[name] as String).readAsBytes())
                    .toString() ==
                state['plaintextHash'],
            isTrue);
      }
      expect(await SessionCleanup.instance.pending, isFalse);
      await signin();
      await until(() => find.byType(PageRecoveryReset).evaluate().isNotEmpty);
      expect(find.byType(PageAccessKeyDecode).evaluate().isEmpty, isTrue);
      expect(find.byType(PageAccessKeyNotice).evaluate().isEmpty, isTrue);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      passed.addAll({
        'startupRevocationClearedLocalData': true,
        'externalOriginalPreserved': true,
        'freshSigninSharesDeletionProgress': true
      });
    } else if (stage == 'peer-create') {
      await boot();
      final phrase = await generate();
      expect(await getDeviceUuid() != state['oldDeviceUuid'], isTrue);
      final bytes = List<int>.generate(64 * 1024 + 23, (i) => (i + 17) % 251);
      final item = await upload('reset-new-source', bytes);
      final model = (await ModelFile.get(item.fileHash!))!;
      expect(model.storageId == state['oldStorageId'], isTrue,
          reason: 'The new vault must reuse the retained connection');
      await download(
          item, File('${documents.path}/reset-new-source/fixture.bin'), bytes);
      state.addAll({
        'newPhrase': phrase,
        'newItemId': item.id,
        'newFileHash': item.fileHash
      });
      passed.addAll({
        'otherDeviceCreatedFirstKeys': true,
        'retainedProviderUploadDownloadPassed': true
      });
    } else if (stage == 'initiator-join') {
      await boot();
      await until(() => find.byType(PageAccessKeyDecode).evaluate().isNotEmpty);
      expect(find.byType(PageSignin).evaluate().isEmpty, isTrue);
      final cookie = await secure.read(key: AppString.sessionCookie.string);
      expect(
          cookie != null &&
              sha256.convert(utf8.encode(cookie)).toString() ==
                  state['initiatingSessionHash'],
          isTrue);
      final phrase = input['newPhrase'] as String;
      expect(bip39.validateMnemonic(phrase), isTrue);
      await tester.enterText(find.byType(TextFormField).first, phrase);
      await tap(find
          .descendant(
              of: find.byType(PageAccessKeyDecode),
              matching: find.byType(FilledButton))
          .first);
      await until(() => find.byType(PageExplorer).evaluate().isNotEmpty);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      expect(await SyncUtils.fetchMapChanges(), isTrue);
      expect(await ModelItem.get(input['newItemId'] as String) != null, isTrue);
      passed.addAll({
        'initiatorRetainedAuthentication': true,
        'firstCreatedPhraseRecovered': true,
        'newVaultMetadataDecrypted': true
      });
    }
    await stateFile.writeAsString(jsonEncode(state), flush: true);
    await resultFile.writeAsString(jsonEncode(passed), flush: true);
    debugPrint('Native reset journey stage $stage passed');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
