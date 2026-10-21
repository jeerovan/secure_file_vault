import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_managed_upload.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());
  test('concurrent sync starts share a pending cleanup request', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ModelSetting.set('managed_cleanup:$id',
        jsonEncode({'id': id, 'receipt': 'private-receipt'}));
    final entered = Completer<void>(), release = Completer<void>();
    var reports = 0;
    await http.runWithClient(() async {
      final first = TaskManager.init();
      await entered.future;
      final second = TaskManager.init();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final observed = reports;
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(observed, 1);
      await Future.wait([first, second]).timeout(const Duration(seconds: 2));
      expect(await ModelSetting.getRaw('managed_cleanup:$id'), isNotEmpty);
    },
        () => MockClient((request) async {
              reports++;
              if (!entered.isCompleted) entered.complete();
              await release.future;
              return http.Response(
                  jsonEncode({
                    'success': 1,
                    'data': {
                      'protocol': 'managed-v1',
                      'id': id,
                      'state': 'cleanup_pending'
                    }
                  }),
                  202);
            }));
  });
  test('revocation during cleanup reporting settles the sync dispatcher',
      () async {
    expect(await SessionCleanup.instance.resume(), isTrue);
    const id = '11111111-1111-4111-8111-111111111111';
    await ModelSetting.set('managed_cleanup:$id',
        jsonEncode({'id': id, 'receipt': 'private-receipt'}));
    final entered = Completer<void>(), release = Completer<void>();
    await http.runWithClient(() async {
      final syncing = TaskManager.init();
      await entered.future.timeout(const Duration(seconds: 2));
      try {
        expect(await SessionCleanup.instance.request(), isTrue);
      } finally {
        release.complete();
      }
      await syncing.timeout(const Duration(seconds: 2));
      expect(fixture.secrets, isEmpty);
      expect(await ModelItemTask.fetchNextWakeAt(), isNull);
      // The stopped dispatcher must not strand a later session's startup.
      await TaskManager.init().timeout(const Duration(seconds: 2));
    },
        () => MockClient((request) async {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              return http.Response(
                  jsonEncode({
                    'success': 1,
                    'data': {
                      'protocol': 'managed-v1',
                      'id': id,
                      'state': 'cleanup_pending'
                    }
                  }),
                  202);
            }));
  });
  Future<ModelItem> discover(List<int> bytes) async {
    await fixture.write('managed.bin', bytes);
    await fixture.scan();
    return fixture.item('managed.bin');
  }

  Future<void> finish(ModelItem item) async {
    for (var i = 0; i < 8; i++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null) break;
      await TaskManager().checkInitUpload(task);
    }
    expect(await ModelItemTask.get(item.id), isNull);
    expect((await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
  }

  Future<void> restore(ModelItem item) async {
    await File('${fixture.source.path}/managed.bin').delete();
    await ModelItemTask.addTask(item.id, ItemTask.download.value);
    for (var i = 0; i < 8; i++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null) break;
      await TaskManager().checkInitDownload(task);
    }
    expect(await ModelItemTask.get(item.id), isNull);
  }

  for (final provider in [1, 2, 3, 4, 5, 6]) {
    test(
        'provider $provider uses managed finalization for initial and modified files',
        () async {
      final api = TransferApi(providerId: provider, managed: true);
      await api.run(() async {
        final initial = await discover(utf8.encode('initial bytes'));
        api.afterManagedPut = () async {
          final current = await fixture.item('managed.bin');
          expect((await ModelPart.get('${current.fileHash}_1'))?.uploaded, 0);
        };
        await finish(initial);
        final edited =
            utf8.encode('modified bytes through managed finalization');
        final current = await discover(edited);
        await finish(current);
        expect(current.fileHash, isNot(initial.fileHash));
        expect(api.objects.length, 2);
        expect(
            api.requests.where((r) => r.url.path.endsWith('/get-upload-url')),
            isEmpty);
        expect(
            api.requests
                .where((r) => r.url.path.endsWith('/uploads/complete'))
                .length,
            2);
        final part = (await ModelPart.get('${current.fileHash}_1'))!;
        expect(part.data, isNot(contains('receipt')));
        await restore(current);
        expect(await File('${fixture.source.path}/managed.bin').readAsBytes(),
            edited);
      });
    });
  }
  test('temporary allocation failure preserves a managed upload for retry',
      () async {
    final api = TransferApi(managed: true)
      ..selectionFailure = {'success': -1, 'message': 'Network Error'};
    await api.run(() async {
      final item =
          await discover(utf8.encode('retry after allocation failure'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(api.uploadBodies, isEmpty);
      expect((await ModelFile.get(item.fileHash!))!.storageId, isNull);
      expect(
          (await ModelItemTask.get(item.id))!.state, TransferTaskState.pending);
      api.selectionFailure = null;
      await finish(item);
      expect(api.uploadBodies.length, 1);
      await restore(item);
      expect(await File('${fixture.source.path}/managed.bin').readAsString(),
          'retry after allocation failure');
    });
  });
  for (final lost in ['upload', 'completion', 'pending']) {
    test(
        '$lost response loss preserves the ciphertext and never uploads it twice',
        () async {
      final api = TransferApi(providerId: 2, managed: true);
      if (lost == 'upload') api.loseNextUploadResponse = true;
      if (lost == 'completion') api.loseNextCompletionResponse = true;
      if (lost == 'pending') api.completionStatuses.add(503);
      await api.run(() async {
        final current = await discover(utf8.encode('durable retry bytes'));
        await TaskManager()
            .checkInitUpload((await ModelItemTask.get(current.id))!);
        final before = (await ModelPart.get('${current.fileHash}_1'))!;
        expect(before.uploaded, 0);
        final artifact =
            File('${fixture.directory.path}/${current.fileHash}_1.crypt.ready');
        expect(await artifact.exists(), isTrue);
        final bytes = await artifact.readAsBytes();
        await finish(current);
        final after = (await ModelPart.get('${current.fileHash}_1'))!;
        expect(after.cipher, before.cipher);
        expect(after.nonce, before.nonce);
        expect(api.uploadBodies.length, 1);
        expect(api.uploadBodies.single, bytes);
        expect(api.managedRecords.length, 1);
        await restore(current);
        expect(await File('${fixture.source.path}/managed.bin').readAsString(),
            'durable retry bytes');
      });
    });
  }
  test('a rejected part retries with the same ID, keys and encrypted bytes',
      () async {
    final api = TransferApi(managed: true)..uploadStatuses.add(403);
    await api.run(() async {
      final item = await discover(utf8.encode('retry after expired signature'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      final before = (await ModelPart.get('${item.fileHash}_1'))!;
      await finish(item);
      final after = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(before.cipher, after.cipher);
      expect(api.managedRecords.length, 1);
      expect(api.uploadBodies.length, 2);
      expect(api.uploadBodies[0], api.uploadBodies[1]);
    });
  });
  test(
      'completion restores a missing local part with server keys and its object location',
      () async {
    final api = TransferApi(managed: true);
    await api.run(() async {
      final item =
          await discover(utf8.encode('recover accepted server metadata'));
      api.afterManagedPut =
          () async => (await ModelPart.get('${item.fileHash}_1'))!.delete();
      await finish(item);
      final accepted = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(accepted.data['managedObjectKey'], contains('~'));
      expect(accepted.data['managedUploadId'], api.managedRecords.keys.single);
      expect((await ModelFile.get(item.fileHash!))!.parts, 1);
      expect(
          (await StorageSqlite.instance.getAll(Tables.settings.string))
              .where((r) => (r['id'] as String).startsWith('managed_cleanup:')),
          isEmpty);
      await restore(item);
      expect(await File('${fixture.source.path}/managed.bin').readAsString(),
          'recover accepted server metadata');
    });
  });
  test(
      'older managed completion without metadata retains a cleanup outbox for a missing local part',
      () async {
    final api = TransferApi(managed: true)..includeManagedMetadata = false;
    await api.run(() async {
      final item = await discover(utf8.encode('orphaned local metadata'));
      api.afterManagedPut =
          () async => (await ModelPart.get('${item.fileHash}_1'))!.delete();
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      final settings =
          await StorageSqlite.instance.getAll(Tables.settings.string);
      expect(
          settings
              .where((r) => (r['id'] as String).startsWith('managed_cleanup:'))
              .length,
          1);
      await ManagedUploadClient().drainCleanup();
      expect(
          (await StorageSqlite.instance.getAll(Tables.settings.string))
              .where((r) => (r['id'] as String).startsWith('managed_cleanup:'))
              .length,
          1);
      api.deletionVerified = true;
      await ManagedUploadClient().drainCleanup();
      expect(
          (await StorageSqlite.instance.getAll(Tables.settings.string))
              .where((r) => (r['id'] as String).startsWith('managed_cleanup:')),
          isEmpty);
      expect(api.objects, isEmpty);
      expect(await File('${fixture.source.path}/managed.bin').readAsString(),
          'orphaned local metadata');
    });
  });
  test(
      'legacy fallback marks its direct upload for mixed-version metadata sync',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final item = await discover(utf8.encode('legacy compatibility'));
      await finish(item);
      final part = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(part.data['legacyUpload'], true);
      expect(part.data, isNot(contains('managedObjectKey')));
      expect(part.data, isNot(contains('managedUploadId')));
    });
  });
  test('managed upload restores an edited file split into two encrypted parts',
      () async {
    final api = TransferApi(providerId: 2, managed: true);
    await api.run(() async {
      await finish(await discover(utf8.encode('small original')));
      final edited = List<int>.generate(35 * 1024 * 1024 + 19, (i) => i % 251);
      final item = await discover(edited);
      await finish(item);
      expect((await ModelFile.get(item.fileHash!))!.parts, 2);
      expect(await ModelPart.getPartsUploadedForFileHash(item.fileHash!, 2), 2);
      await restore(item);
      expect(await File('${fixture.source.path}/managed.bin').readAsBytes(),
          edited);
    });
  });
  test(
      'a competing local encryption attempt adopts accepted keys and removes its stale pending change',
      () async {
    final api = TransferApi(managed: true);
    await api.run(() async {
      final item = await discover(utf8.encode('already safely uploaded'));
      await finish(item);
      final file = (await ModelFile.get(item.fileHash!))!;
      final part = (await ModelPart.get('${item.fileHash}_1'))!;
      api.existingFile = {
        '6': file.id,
        '7': file.itemCount,
        '8': file.parts,
        '9': file.uploadedAt,
        '10': file.providerId,
        '11': file.storageId,
        '12': file.data,
        '13': file.updatedAt
      };
      api.existingPart = {
        '6': file.id,
        '7': 1,
        '8': part.size,
        '9': part.cipher,
        '10': part.nonce,
        '11': part.data,
        '12': part.updatedAt,
        '14': 1
      };
      await part.delete();
      file.uploadedAt = 0;
      await file.update(['uploaded_at']);
      await ModelItemTask.addTask(item.id, ItemTask.upload.value);
      await finish(item);
      final accepted = (await ModelPart.get(part.id))!;
      expect(accepted.cipher, part.cipher);
      expect(accepted.nonce, part.nonce);
      expect(api.uploadBodies.length, 1);
      expect(
          await StorageSqlite.instance
              .getWithId(Tables.changes.string, 'parts|${part.id}'),
          isEmpty);
      await restore(item);
      expect(await File('${fixture.source.path}/managed.bin').readAsString(),
          'already safely uploaded');
    });
  });
}
