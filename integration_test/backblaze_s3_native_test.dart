import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/storage_channel.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

import 'support/apple_bookmark.dart';
import 'support/observed_transfers.dart';
import 'support/iphone_results.dart';
import 'support/native_test_install.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recordIphoneResults(binding, 'backblaze');

  testWidgets(
      'LAN Backblaze S3 modified multipart file, lost response and deletion',
      (tester) async {
    expect(Platform.isAndroid || Platform.isIOS || Platform.isMacOS, isTrue);
    await verifyNativeTestInstall();
    expect(AppEnv.localTestingBuild, isTrue);
    expect(AppEnv.localTestUserId.startsWith('fife-provider-local-'), isTrue);
    expect(AppEnv.effectiveApiBaseUrl, AppEnv.apiBaseUrl);
    final physicalPhone =
        Platform.isIOS && (await DeviceInfoPlugin().iosInfo).isPhysicalDevice;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                Center(child: Text('Testing local Backblaze S3 transfers')))));
    await addTrustedCertificates();
    if (physicalPhone) {
      // Give the owner time to allow iOS's first-use Local Network prompt.
      final endpoint = Uri.parse(AppEnv.effectiveApiBaseUrl);
      final elapsed = Stopwatch()..start();
      var reachable = false;
      int? errorCode;
      while (!reachable && elapsed.elapsed < const Duration(seconds: 90)) {
        try {
          final socket = await Socket.connect(endpoint.host, endpoint.port,
              timeout: const Duration(seconds: 3));
          socket.destroy();
          reachable = true;
        } on SocketException catch (error) {
          errorCode = error.osError?.errorCode;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      expect(reachable, isTrue,
          reason:
              'iPhone must reach the LAN backend (socket code $errorCode); allow Local Network and use the same Wi-Fi');
    }
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    expect(await SessionCleanup.instance.request(), isTrue);
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(
        AppString.deviceUuid.string, 'local-s3-emulator-device');
    await ModelSetting.set(AppString.deviceHash.string, 'local-s3-device-root');
    await (await ModelProfile.fromMap(
            {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
        .insert();
    final sodium = await SodiumSumoInit.init();
    final keys = CryptoUtils(sodium).generateKeys().getResult()!;
    final privateKeys =
        keys[AppString.privateKeys.string] as Map<String, dynamic>;
    final secure = SecureStorage();
    for (final entry in privateKeys.entries) {
      await secure.write(key: entry.key, value: entry.value as String);
    }
    final api = BackendApi();
    expect(localTesting(), isTrue);
    expect(AppEnv.localTestAuthToken.isNotEmpty, isTrue);
    final created = await api.post(
        endpoint: '/keys', jsonBody: keys[AppString.serverKeys.string]);
    final rawCode = created['message'];
    final safeCode = rawCode is num ||
            const ['Network Error', 'Unexpected Error', 'Server Error']
                .contains(rawCode) ||
            (rawCode is String && RegExp(r'^[a-z_]+$').hasMatch(rawCode))
        ? '$rawCode'
        : 'withheld';
    expect(created['success'] == 1, isTrue,
        reason:
            'Local backend must create the isolated test vault ($safeCode)');
    final registered = await BackendApi(deviceUuidProvider: () async => '')
        .post(endpoint: '/devices', jsonBody: {
      'device_uuid': 'local-s3-emulator-device',
      'title': Platform.isAndroid
          ? 'Emulator1 local S3 test'
          : 'iPhone local S3 test',
      'type': await getDeviceType(),
      'active': 1,
    });
    expect(registered['success'] == 1, isTrue,
        reason: 'Local backend must register the fixture device');

    final documents = await getApplicationDocumentsDirectory();
    final source =
        await Directory('${documents.path}/local-s3-fixture').create();
    String? bookmark;
    if (Platform.isIOS || Platform.isMacOS) {
      bookmark = createAppleTestBookmark(source.path);
      expect(ChannelStorage.hasUsableBookmark(bookmark), isTrue);
      final resolved = await ChannelStorage.startAccessing(bookmark);
      expect(resolved, isNotNull);
      expect(await Directory(resolved!).resolveSymbolicLinks(),
          await source.resolveSymbolicLinks());
      await ChannelStorage.stopAccessing(resolved);
    }
    final db = await StorageSqlite.instance.database;
    await db.insert('items',
        {'id': 'local-s3-device-root', 'name': 'Emulator1', 'is_folder': 1});
    await db.insert('items', {
      'id': 'local-s3-root',
      'parent_id': 'local-s3-device-root',
      'name': 'local-s3-fixture',
      'path': source.path,
      'bookmark': bookmark,
      'is_folder': 1
    });
    final recon = ReconciliationService(sodium);
    final observed = ObservedTransfers(http.Client());
    AppHttpClients.closeAll();
    try {
      await http.runWithClient(() async {
        Future<ModelItem> discover(List<int> bytes) async {
          await File('${source.path}/edited.bin')
              .writeAsBytes(bytes, flush: true);
          expect(
              (await recon.reconcile((await ModelItem.get('local-s3-root'))!))
                  .status,
              ReconciliationStatus.completed);
          final rows = await db.query('items',
              where: 'root_id = ? AND is_folder = 0',
              whereArgs: ['local-s3-root']);
          expect(rows.length, 1);
          expect(await SyncUtils.pushMapChanges(), isTrue,
              reason: 'Publish discovered metadata before allocating storage');
          return ModelItem.fromMap(rows.single);
        }

        Future<void> finishUpload(ModelItem item) async {
          for (var step = 0; step < 12; step++) {
            final task = await ModelItemTask.get(item.id);
            if (task == null) break;
            expect(task.state, TransferTaskState.pending);
            await TaskManager()
                .checkInitUpload(task)
                .timeout(const Duration(seconds: 60));
            expect(observed.providerFailureType,
                isNot(contains('CERTIFICATE_VERIFY_FAILED')),
                reason: 'Native cloud connections must verify certificates');
            if (observed.providerFailureType != null) {
              debugPrint('Local S3: transient upload error; retrying');
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          }
          expect(await ModelItemTask.get(item.id), isNull,
              reason: observed.rejectedInvariant ?? 'Upload must finish');
          expect((await ModelFile.get(item.fileHash!))!.uploadedAt,
              greaterThan(0));
          expect(await SyncUtils.pushMapChanges(), isTrue);
        }

        final original =
            await discover(utf8.encode('original local cloud fixture'));
        await finishUpload(original);
        expect(observed.uploads, greaterThanOrEqualTo(1));
        debugPrint('Local S3: initial encrypted file uploaded');
        final editedBytes =
            List<int>.generate(35 * 1024 * 1024 + 19, (index) => index % 251);
        final edited = await discover(editedBytes);
        expect(edited.id, original.id);
        expect(edited.fileHash != original.fileHash, isTrue);
        expect((await ModelFile.get(edited.fileHash!))!.parts, 2);
        observed.loseNextSuccess = true;
        for (var attempt = 0;
            attempt < 6 && observed.lostVersion == null;
            attempt++) {
          await TaskManager()
              .checkInitUpload((await ModelItemTask.get(edited.id))!)
              .timeout(const Duration(seconds: 90));
          expect(observed.providerFailureType,
              isNot(contains('CERTIFICATE_VERIFY_FAILED')));
        }
        expect(observed.lostVersion?.isNotEmpty, isTrue);
        debugPrint('Local S3: modified part committed; success response lost');
        expect((await ModelPart.get('${edited.fileHash}_1'))?.uploaded, 0);
        final attemptsAtCommit = observed.uploads;
        for (var attempt = 0; attempt < 6; attempt++) {
          if ((await ModelPart.get('${edited.fileHash}_1'))?.uploaded == 1) {
            break;
          }
          await TaskManager()
              .checkInitUpload((await ModelItemTask.get(edited.id))!)
              .timeout(const Duration(seconds: 60));
          expect(observed.uploads, attemptsAtCommit,
              reason: 'Recovery must not upload another committed version');
        }
        expect((await ModelPart.get('${edited.fileHash}_1'))?.uploaded, 1);
        await finishUpload(edited);
        debugPrint('Local S3: modified multipart file recovered and uploaded');
        expect(
            (await ModelPart.get('${edited.fileHash}_1'))?.data['fileId'] ==
                observed.lostVersion,
            isTrue);

        await File('${source.path}/edited.bin').delete();
        await ModelItemTask.addTask(edited.id, ItemTask.download.value);
        for (var step = 0; step < 12; step++) {
          final task = await ModelItemTask.get(edited.id);
          if (task == null) break;
          await TaskManager().checkInitDownload(task);
        }
        expect(await ModelItemTask.get(edited.id), isNull);
        final restored = await File('${source.path}/edited.bin').readAsBytes();
        expect(restored.length, editedBytes.length);
        expect(sha256.convert(restored) == sha256.convert(editedBytes), isTrue);
        debugPrint('Local S3: downloaded and decrypted bytes match');

        await File('${source.path}/edited.bin').delete();
        expect(
            (await recon.reconcile((await ModelItem.get('local-s3-root'))!))
                .status,
            ReconciliationStatus.completed);
        expect(await SyncUtils.pushMapChanges(), isTrue,
            reason: 'Filesystem deletion must preserve the uploaded file');
        final retained = (await ModelItem.get(edited.id))!;
        expect(retained.scanState, 0);
        expect(retained.archivedAt, 0,
            reason: 'Only an explicit archive action moves a file to Trash');
        final cloudCopy = (await ModelFile.get(edited.fileHash!))!;
        expect(cloudCopy.uploadedAt, greaterThan(0),
            reason: 'Removing a local source must retain its recoverable copy');

        // Explorer's archive action is permitted after the local source is gone.
        retained.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
        await retained.update(['archived_at']);
        expect(await SyncUtils.pushMapChanges(), isTrue);
        expect((await ModelItem.getArchived()).map((item) => item.id),
            contains(edited.id));
        final authorizedDownload = await BackendApi()
            .post(endpoint: '/b2/get-download-url', jsonBody: {
          'storage_id': cloudCopy.storageId,
          'file_id': '${edited.fileHash}_1',
        });
        expect(authorizedDownload['success'], 1);
        final cloudUrl = Uri.parse(authorizedDownload['data'] as String);
        Future<int> cloudStatus() => probeCloudStatus(cloudUrl);

        expect(await cloudStatus(), 206,
            reason: 'A trashed file must still be recoverable from S3');
        await retained.remove();
        expect(await ModelItem.get(edited.id), isNull);
        expect(await ModelFile.get(edited.fileHash!), isNull);
        expect(await SyncUtils.pushMapChanges(), isTrue,
            reason: 'Permanent deletion must remove the uploaded S3 versions');
        expect(await cloudStatus(), 404,
            reason: 'S3 must confirm the permanently deleted part is absent');
        debugPrint('Local S3: Trash retention and permanent deletion verified');
      }, () => observed);
    } finally {
      AppHttpClients.closeAll();
      observed.close();
      if (await source.exists()) await source.delete(recursive: true);
      expect(await SessionCleanup.instance.request(), isTrue);
    }
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(child: Text('Local Backblaze S3 tests passed')))));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
