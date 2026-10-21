import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_logger.dart';
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

import 'support/observed_transfers.dart';
import 'support/apple_bookmark.dart';
import 'support/iphone_results.dart';
import 'support/native_test_install.dart';

void main() {
  registerProviderNativeTests();
}

void registerProviderNativeTests({
  bool reportResults = true,
  Duration transferTimeout = const Duration(seconds: 90),
  Duration suiteTimeout = const Duration(minutes: 20),
}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (reportResults) recordIphoneResults(binding, 's3-providers');
  testWidgets(
      'LAN S3 providers preserve modified multipart bytes across retries',
      (tester) async {
    expect(Platform.isAndroid || Platform.isIOS || Platform.isMacOS, isTrue);
    await verifyNativeTestInstall();
    expect(AppEnv.localTestingBuild, isTrue);
    expect(AppEnv.localTestUserId.startsWith('fife-provider-local-'), isTrue);
    expect(AppEnv.effectiveApiBaseUrl, AppEnv.apiBaseUrl);
    final inputs =
        jsonDecode(const String.fromEnvironment('FIFE_NATIVE_PROVIDER_INPUTS'))
            as List;
    // Each registration has higher priority than the preceding storage. The
    // application's normal allocation path must select that provider.
    expect(inputs.map((input) => input['id']).toList(),
        anyOf(orderedEquals([3, 4, 5, 6]), orderedEquals([2, 3, 4, 5, 6])));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(child: Text('Testing local provider transfers')))));
    await addTrustedCertificates();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    expect(await SessionCleanup.instance.resume(), isTrue);
    expect(await SessionCleanup.instance.request(), isTrue);
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(
        AppString.deviceUuid.string, 'local-s3-providers-device');
    await ModelSetting.set(
        AppString.deviceHash.string, 'local-s3-providers-root');
    await (await ModelProfile.fromMap(
            {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
        .insert();
    final sodium = await SodiumSumoInit.init();
    final keys = CryptoUtils(sodium).generateKeys().getResult()!;
    final secure = SecureStorage();
    for (final entry
        in (keys[AppString.privateKeys.string] as Map<String, dynamic>)
            .entries) {
      await secure.write(key: entry.key, value: entry.value as String);
    }
    final api = BackendApi();
    expect(
        (await api.post(
                endpoint: '/keys',
                jsonBody: keys[AppString.serverKeys.string]))['success'] ==
            1,
        isTrue,
        reason: 'A fresh disposable server identity is required');
    expect(
        (await BackendApi(deviceUuidProvider: () async => '')
                .post(endpoint: '/devices', jsonBody: {
              'device_uuid': 'local-s3-providers-device',
              'title': 'Native provider acceptance',
              'type': await getDeviceType(),
              'active': 1
            }))['success'] ==
            1,
        isTrue);
    final db = await StorageSqlite.instance.database;
    await db.insert('items', {
      'id': 'local-s3-providers-root',
      'name': 'Provider tests',
      'is_folder': 1
    });
    final documents = await getApplicationDocumentsDirectory();
    final source =
        await Directory('${documents.path}/provider-fixture').create();
    try {
      const selected = String.fromEnvironment('FIFE_NATIVE_PROVIDER_FILTER');
      expect(selected.isEmpty || inputs.any((raw) => raw['name'] == selected),
          isTrue,
          reason: 'The filter must select a configured provider');
      for (final raw in inputs) {
        final input = Map<String, dynamic>.from(raw as Map);
        final name = input['name'] as String;
        if (selected.isNotEmpty && selected != name) continue;
        final providerId = input['id'] as int;
        final fields = Map<String, dynamic>.from(input['fields'] as Map);
        final registration = await BackendApi()
            .post(endpoint: '/$name/add-account', jsonBody: fields);
        final safeCode = registration['message'] is num
            ? '${registration['message']}'
            : 'unavailable';
        expect(registration['success'] == 1, isTrue,
            reason:
                '$name registration must verify the configured credentials (safe code $safeCode)');
        final directory = await Directory('${source.path}/$name').create();
        String? bookmark;
        if (Platform.isIOS || Platform.isMacOS) {
          bookmark = createAppleTestBookmark(directory.path);
          expect(ChannelStorage.hasUsableBookmark(bookmark), isTrue);
          final resolved = await ChannelStorage.startAccessing(bookmark);
          expect(resolved, isNotNull);
          expect(await Directory(resolved!).resolveSymbolicLinks(),
              await directory.resolveSymbolicLinks());
          await ChannelStorage.stopAccessing(resolved);
        }
        final rootId = 'local-provider-$name';
        await db.insert('items', {
          'id': rootId,
          'parent_id': 'local-s3-providers-root',
          'name': name,
          'path': directory.path,
          'bookmark': bookmark,
          'is_folder': 1
        });
        final recon = ReconciliationService(sodium);
        final observed = ObservedTransfers(http.Client(),
            endpointHost: input['host'] as String);
        var phase = 'initial-upload';
        String? activeItem;
        final elapsed = Stopwatch()..start();
        final progress = <Map<String, int?>>[];
        var sampling = false;
        final sample = Timer.periodic(const Duration(seconds: 1), (_) async {
          if (sampling || activeItem == null) return;
          sampling = true;
          try {
            final task = await ModelItemTask.get(activeItem!);
            if (progress.isEmpty ||
                progress.last['percent'] != task?.progress) {
              progress.add({
                'ms': elapsed.elapsedMilliseconds,
                'percent': task?.progress
              });
            }
          } catch (_) {
            // Sampling may race cancellation; retain the transfer's original
            // failure rather than emit a later diagnostic-only exception.
          } finally {
            sampling = false;
          }
        });
        try {
          await http.runWithClient(() async {
            Future<ModelItem> discover(List<int> bytes) async {
              await File('${directory.path}/edited.bin')
                  .writeAsBytes(bytes, flush: true);
              expect(
                  (await recon.reconcile((await ModelItem.get(rootId))!))
                      .status,
                  ReconciliationStatus.completed);
              final rows = await db.query('items',
                  where: 'root_id = ? AND is_folder = 0', whereArgs: [rootId]);
              expect(rows.length, 1);
              expect(await SyncUtils.pushMapChanges(), isTrue);
              return ModelItem.fromMap(rows.single);
            }

            Future<void> finish(ModelItem item) async {
              activeItem = item.id;
              for (var step = 0; step < 14; step++) {
                final task = await ModelItemTask.get(item.id);
                if (task == null) break;
                expect(task.state, TransferTaskState.pending);
                await TaskManager()
                    .checkInitUpload(task)
                    .timeout(transferTimeout);
                expect(observed.providerFailureType,
                    isNot(contains('CERTIFICATE_VERIFY_FAILED')));
                if (observed.providerFailureType != null) {
                  await Future<void>.delayed(const Duration(seconds: 1));
                }
              }
              expect(await ModelItemTask.get(item.id), isNull,
                  reason: '$name upload must finish');
              final model = (await ModelFile.get(item.fileHash!))!;
              expect(model.providerId, providerId,
                  reason: 'The normal allocation path must select $name');
              expect(model.uploadedAt, greaterThan(0));
              expect(await SyncUtils.pushMapChanges(), isTrue);
            }

            final original =
                await discover(utf8.encode('original fixture for $name'));
            await finish(original);
            final bytes = List<int>.generate(
                35 * 1024 * 1024 + 19, (index) => (index + providerId) % 251);
            final edited = await discover(bytes);
            phase = 'modified-upload';
            expect(edited.id, original.id);
            expect(edited.fileHash, isNot(original.fileHash));
            expect((await ModelFile.get(edited.fileHash!))!.parts, 2);
            observed.rejectNextUpload = true;
            // Allocation/authorization can legitimately need another pass.
            // Exercise the injected rejection only once transport is reached.
            for (var attempt = 0;
                attempt < 6 && observed.rejectNextUpload;
                attempt++) {
              final task = await ModelItemTask.get(edited.id);
              expect(task, isNotNull);
              expect(task!.state, TransferTaskState.pending);
              await TaskManager()
                  .checkInitUpload(task)
                  .timeout(transferTimeout);
              if (observed.rejectNextUpload) {
                await Future<void>.delayed(const Duration(seconds: 1));
              }
            }
            expect(observed.rejectNextUpload, isFalse,
                reason: '$name must reach the controlled upload rejection');
            final part = (await ModelPart.get('${edited.fileHash}_1'))!;
            expect(part.uploaded, 0);
            final temp = await getTemporaryDirectory();
            final artifact =
                File('${temp.path}/${edited.fileHash}_1.crypt.ready');
            expect(await artifact.exists(), isTrue);
            final artifactHash = await sha1.bind(artifact.openRead()).first;
            if (providerId == 2) {
              observed.loseNextSuccess = true;
              await TaskManager()
                  .checkInitUpload((await ModelItemTask.get(edited.id))!);
              expect(observed.lostSuccess, isTrue);
              expect(
                  (await ModelPart.get('${edited.fileHash}_1'))?.uploaded, 0);
              final attempts = observed.uploads;
              for (var retry = 0;
                  retry < 6 &&
                      (await ModelPart.get('${edited.fileHash}_1'))?.uploaded !=
                          1;
                  retry++) {
                await TaskManager()
                    .checkInitUpload((await ModelItemTask.get(edited.id))!);
                expect(observed.uploads, attempts,
                    reason:
                        'Managed completion must recover the accepted part without uploading it again');
              }
              expect(
                  (await ModelPart.get('${edited.fileHash}_1'))?.uploaded, 1);
            }
            await finish(edited);
            expect((await ModelPart.get('${edited.fileHash}_1'))?.cipher,
                part.cipher,
                reason: 'A rejected URL must retain the prepared ciphertext');
            expect((await ModelPart.get('${edited.fileHash}_1'))?.data['sha1'],
                artifactHash.toString());
            expect(await artifact.exists(), isFalse);
            expect(observed.rejectedInvariant, isNull);
            expect(observed.managedUploads, observed.uploads);
            expect(observed.uploads, greaterThanOrEqualTo(4));
            phase = 'download';
            await File('${directory.path}/edited.bin').delete();
            await ModelItemTask.addTask(edited.id, ItemTask.download.value);
            for (var step = 0; step < 14; step++) {
              final task = await ModelItemTask.get(edited.id);
              if (task == null) break;
              await TaskManager()
                  .checkInitDownload(task)
                  .timeout(transferTimeout);
            }
            expect(await ModelItemTask.get(edited.id), isNull);
            final restored =
                await File('${directory.path}/edited.bin').readAsBytes();
            expect(restored.length, bytes.length);
            expect(sha256.convert(restored), sha256.convert(bytes));
            await File('${directory.path}/edited.bin').delete();
            expect(
                (await recon.reconcile((await ModelItem.get(rootId))!)).status,
                ReconciliationStatus.completed);
            expect(await SyncUtils.pushMapChanges(), isTrue);
            final retained = (await ModelItem.get(edited.id))!;
            expect(retained.scanState, 0);
            expect(retained.archivedAt, 0);
            retained.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
            await retained.update(['archived_at']);
            expect(await SyncUtils.pushMapChanges(), isTrue);
            expect((await ModelItem.getArchived()).map((item) => item.id),
                contains(edited.id));
            final cloudCopy = (await ModelFile.get(edited.fileHash!))!;
            final download = await BackendApi()
                .post(endpoint: '/$name/get-download-url', jsonBody: {
              'storage_id': cloudCopy.storageId,
              'file_id': '${edited.fileHash}_1',
            });
            expect(download['success'], 1);
            final cloudUrl = Uri.parse(download['data'] as String);
            Future<int> cloudStatus() => probeCloudStatus(cloudUrl);

            expect(await cloudStatus(), 206,
                reason: 'A trashed $name file remains recoverable');
            await retained.remove();
            phase = 'permanent-delete';
            expect(await SyncUtils.pushMapChanges(), isTrue);
            expect(await ModelItem.get(edited.id), isNull);
            expect(await cloudStatus(), 404,
                reason: '$name must confirm that the deleted part is absent');
            debugPrint(
                'Local $name: edited multipart upload, retry, decryption, Trash and deletion passed');
          }, () => observed);
        } catch (_) {
          // Keep only fixed stage names, counters and the application's already
          // sanitized log. Never export signed URLs, keys or raw assertions.
          final log = File('${documents.path}/FiFe/Temp/app_logs.txt');
          final detail = {
            'provider': name,
            'phase': phase,
            'elapsedMs': elapsed.elapsedMilliseconds,
            'uploadAttempts': observed.uploads,
            'progress': progress,
            'appLog': await log.exists()
                ? AppLogger.sanitize((await log.readAsLines())
                    .reversed
                    .take(150)
                    .toList()
                    .reversed
                    .join('\n'))
                : '',
          };
          await File('${documents.path}/fife-native-provider-diagnostics.json')
              .writeAsString(jsonEncode(detail), flush: true);
          debugPrint('Provider failure stage: $name/$phase; '
              '${observed.uploads} upload attempts; progress=$progress');
          rethrow;
        } finally {
          sample.cancel();
          AppHttpClients.closeAll();
          observed.close();
        }
      }
    } finally {
      if (await source.exists()) await source.delete(recursive: true);
      expect(await SessionCleanup.instance.request(), isTrue);
    }
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Text('Provider tests passed')))));
  }, timeout: Timeout(suiteTimeout));
}
