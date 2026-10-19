import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<ModelItem> discover(String name, List<int> bytes) async {
    await fixture.write(name, bytes);
    expect((await fixture.scan()).status, ReconciliationStatus.completed);
    return fixture.item(name);
  }

  Future<void> finishUpload(ModelItem item) async {
    for (var step = 0; step < 8; step++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null) break;
      expect(task.state, TransferTaskState.pending);
      await TaskManager().checkInitUpload(task);
    }
    expect(await ModelItemTask.get(item.id), isNull);
    expect((await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
  }

  Future<void> download(ModelItem item) async {
    await ModelItemTask.addTask(item.id, ItemTask.download.value);
    for (var step = 0; step < 8; step++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null || task.state == TransferTaskState.blocked) break;
      await TaskManager().checkInitDownload(task);
    }
  }

  for (final provider in [1, 2, 3, 4, 5, 6]) {
    test('provider $provider uploads edits and restores the latest bytes',
        () async {
      final api = TransferApi(providerId: provider);
      await api.run(() async {
        final originalBytes = utf8.encode('original version');
        final editedBytes = utf8.encode('modified version');
        final original = await discover('edit.txt', originalBytes);
        await finishUpload(original);
        final oldObjectIds = api.objects.keys.toSet();
        expect(oldObjectIds.length, 1);
        expect(api.objects.values.single, isNot(originalBytes));

        final current = await discover('edit.txt', editedBytes);
        expect(current.id, original.id);
        expect(current.fileHash, isNot(original.fileHash));
        await finishUpload(current);
        expect(api.objects.length, 2);
        expect(api.objects.keys.toSet(), containsAll(oldObjectIds));
        expect((await ModelFile.get(original.fileHash!))?.itemCount, 0);

        await File('${fixture.source.path}/edit.txt').delete();
        await download(current);
        expect(await ModelItemTask.get(current.id), isNull);
        final restored =
            await File('${fixture.source.path}/edit.txt').readAsBytes();
        expect(restored, editedBytes);
        expect(sha256.convert(restored), sha256.convert(editedBytes));
        expect((await ModelItem.get(current.id))?.fileHash, current.fileHash);
      });
    });
  }

  test('multipart edited file restores every part in order', () async {
    final api = TransferApi();
    await api.run(() async {
      final original = await discover('large.bin', List.filled(1024, 65));
      await finishUpload(original);
      final bytes = List<int>.generate(35 * 1024 * 1024 + 19, (i) => i % 251);
      final current = await discover('large.bin', bytes);
      expect((await ModelFile.get(current.fileHash!))?.parts, 2);
      await finishUpload(current);
      expect(
          await ModelPart.getPartsUploadedForFileHash(current.fileHash!, 2), 2);
      await File('${fixture.source.path}/large.bin').delete();
      await download(current);
      expect(await ModelItemTask.get(current.id), isNull);
      expect(
          await File('${fixture.source.path}/large.bin').readAsBytes(), bytes);
    });
  });

  for (final bytes in [
    <int>[],
    [0],
    List<int>.filled(4097, 255)
  ]) {
    test(
        'edited ${bytes.length}-byte version restores with its correct part count',
        () async {
      final api = TransferApi();
      await api.run(() async {
        final original = await discover('edit.bin', [1, 2, 3]);
        await finishUpload(original);
        final current = await discover('edit.bin', bytes);
        await finishUpload(current);
        expect((await ModelFile.get(current.fileHash!))?.parts,
            bytes.isEmpty ? 0 : 1);
        await File('${fixture.source.path}/edit.bin').delete();
        await download(current);
        expect(await ModelItemTask.get(current.id), isNull);
        expect(
            await File('${fixture.source.path}/edit.bin').readAsBytes(), bytes);
      });
    });
  }

  test('a source edit after discovery blocks stale upload then recovers',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final original = await discover('race.txt', utf8.encode('version A'));
      await fixture.text('race.txt', 'version B');
      await TaskManager()
          .checkInitUpload((await ModelItemTask.get(original.id))!);
      final blocked = (await ModelItemTask.get(original.id))!;
      expect(blocked.state, TransferTaskState.blocked);
      expect(blocked.lastError, 'upload_source_changed');
      expect(api.objects, isEmpty);
      final current = await discover('race.txt', utf8.encode('version B'));
      await finishUpload(current);
      expect(api.objects.length, 1);
    });
  });

  test('failed upload retries reuse exactly the same encrypted artifact',
      () async {
    final api = TransferApi()..uploadStatuses.add(503);
    await api.run(() async {
      final item = await discover('retry.txt', utf8.encode('durable source'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(api.objects, isEmpty);
      final failedPart = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(failedPart.uploaded, 0);
      await finishUpload(item);
      expect(api.uploadBodies.length, 2);
      expect(api.uploadBodies[0], api.uploadBodies[1]);
      final uploaded = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(uploaded.cipher, failedPart.cipher);
      expect(uploaded.nonce, failedPart.nonce);
      expect(uploaded.uploaded, 1);
    });
  });

  test(
      'B2 lost success response is recovered without uploading another version',
      () async {
    final api = TransferApi(providerId: 2)..loseNextUploadResponse = true;
    await api.run(() async {
      final item = await discover('lost.txt', utf8.encode('commit survived'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(api.objects.length, 1);
      expect((await ModelPart.get('${item.fileHash}_1'))?.uploaded, 0);
      await finishUpload(item);
      expect(api.uploadBodies.length, 1);
      expect(
          api.requests.any((r) => r.url.path.endsWith('/find-uploaded-file')),
          isTrue);
      expect((await ModelPart.get('${item.fileHash}_1'))?.uploaded, 1);
    });
  });

  for (final status in [403, 503]) {
    test('download HTTP $status retains metadata and succeeds after recovery',
        () async {
      final api = TransferApi();
      await api.run(() async {
        final bytes = utf8.encode('recover after failed download');
        final item = await discover('download.txt', bytes);
        await finishUpload(item);
        await File('${fixture.source.path}/download.txt').delete();
        api.downloadStatuses.add(status);
        await ModelItemTask.addTask(item.id, ItemTask.download.value);
        await TaskManager()
            .checkInitDownload((await ModelItemTask.get(item.id))!);
        expect(await File('${fixture.source.path}/download.txt').exists(),
            isFalse);
        expect(await ModelItem.get(item.id), isNotNull);
        expect(await ModelFile.get(item.fileHash!), isNotNull);
        expect(await ModelItemTask.get(item.id), isNotNull);
        expect((await ModelItemTask.get(item.id))?.state,
            isNot(TransferTaskState.blocked));
        await download(item);
        expect(await ModelItemTask.get(item.id), isNull);
        expect(await File('${fixture.source.path}/download.txt').readAsBytes(),
            bytes);
      });
    });
  }

  for (final corruption in [
    'checksum',
    'ciphertext',
    'wrapped key',
    'plaintext hash'
  ]) {
    test('$corruption corruption cannot publish unverified plaintext',
        () async {
      final api = TransferApi();
      await api.run(() async {
        final bytes = utf8.encode('authenticated content for verification');
        final item = await discover('verify.txt', bytes);
        await finishUpload(item);
        final part = (await ModelPart.get('${item.fileHash}_1'))!;
        final originalPart = part.toMap();
        final goodCiphertext = List<int>.of(api.objects.values.single);
        if (corruption == 'checksum' || corruption == 'ciphertext') {
          final damaged = List<int>.of(goodCiphertext);
          damaged[damaged.length - 1] ^= 1;
          api.objects['${item.fileHash}_1'] = damaged;
          if (corruption == 'ciphertext') {
            part.data['sha1'] = sha1.convert(damaged).toString();
            await part.update(['data']);
          }
        } else if (corruption == 'wrapped key') {
          final damaged = base64Decode(part.cipher!);
          damaged[0] ^= 1;
          part.cipher = base64Encode(damaged);
          await part.update(['cipher']);
        } else {
          // Ciphertext and its MAC remain valid; final plaintext metadata is wrong.
          await (await fixture.db).update('items', {'size': bytes.length + 1},
              where: 'id = ?', whereArgs: [item.id]);
        }
        await File('${fixture.source.path}/verify.txt').delete();
        await download(item);
        expect(
            await File('${fixture.source.path}/verify.txt').exists(), isFalse);
        expect(await ModelItemTask.get(item.id), isNotNull);
        expect(await ModelItem.get(item.id), isNotNull);
        api.objects['${item.fileHash}_1'] = goodCiphertext;
        await (await fixture.db).update('parts', originalPart,
            where: 'id = ?', whereArgs: [part.id]);
        await (await fixture.db).update('items', {'size': bytes.length},
            where: 'id = ?', whereArgs: [item.id]);
        await download(item);
        expect(await ModelItemTask.get(item.id), isNull);
        expect(await File('${fixture.source.path}/verify.txt').readAsBytes(),
            bytes);
      });
    });
  }

  test('download preserves an externally edited destination and can retry',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final item =
          await discover('conflict.txt', utf8.encode('backed up version'));
      await finishUpload(item);
      final source =
          await fixture.text('conflict.txt', 'new unsynced local edit');
      await download(item);
      expect(await source.readAsString(), 'new unsynced local edit');
      expect((await ModelItemTask.get(item.id))?.lastError,
          'destination_conflict');
      await source.rename('${fixture.source.path}/saved-local-edit.txt');
      await download(item);
      expect(await ModelItemTask.get(item.id), isNull);
      expect(await source.readAsString(), 'backed up version');
      expect(
          await File('${fixture.source.path}/saved-local-edit.txt')
              .readAsString(),
          'new unsynced local edit');
    });
  });

  test('edit during encryption cannot upload a mixed or outdated artifact',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final item = await discover('edit.txt', utf8.encode('before'));
      var reads = 0;
      fixture.beforeRead = (key) async {
        if (key == AppString.fileHashKey.string && ++reads == 2) {
          await fixture.text('edit.txt', 'after!');
        }
      };
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect((await ModelItemTask.get(item.id))?.lastError,
          'upload_source_changed');
      expect(api.uploadBodies, isEmpty);
      expect(
          await File(
                  '${fixture.directory.path}/${item.fileHash}_1.crypt.ready.partial')
              .exists(),
          isFalse);
      fixture.beforeRead = null;
      final current = await discover('edit.txt', utf8.encode('after!'));
      await finishUpload(current);
      expect(api.objects.length, 1);
    });
  });

  test('full bucket blocks upload and retries when capacity becomes available',
      () async {
    final api = TransferApi()
      ..selectionFailure = {'success': 0, 'message': '4'};
    await api.run(() async {
      final item = await discover('capacity.txt', utf8.encode('keep pending'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect((await ModelItemTask.get(item.id))?.lastError, 'storage_full');
      expect(await ModelState.get(AppString.storageFull.string), 'yes');
      expect(api.objects, isEmpty);
      api.selectionFailure = null;
      await fixture.scan();
      await finishUpload(item);
      expect(await ModelState.get(AppString.storageFull.string), 'no');
    });
  });

  test('temporary storage-selection failure retains the source and queue',
      () async {
    final api = TransferApi()
      ..selectionFailure = {'success': -1, 'message': 'Network Error'};
    await api.run(() async {
      final item = await discover('offline.txt', utf8.encode('still here'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(
          (await ModelItemTask.get(item.id))?.state, TransferTaskState.pending);
      expect((await ModelFile.get(item.fileHash!))?.storageId, isNull);
      expect(await File('${fixture.source.path}/offline.txt').readAsString(),
          'still here');
      api.selectionFailure = null;
      await finishUpload(item);
    });
  });

  test('missing master key cannot publish a part and recovers when unlocked',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final item = await discover('locked.txt', utf8.encode('encrypted only'));
      final key = fixture.secrets.remove(AppString.masterKey.string)!;
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(api.objects, isEmpty);
      expect(await ModelPart.get('${item.fileHash}_1'), isNull);
      expect(await ModelItemTask.get(item.id), isNotNull);
      fixture.secrets[AppString.masterKey.string] = key;
      await finishUpload(item);
    });
  });

  test('damaged cached upload artifact is regenerated before retry', () async {
    final api = TransferApi()..uploadStatuses.add(503);
    await api.run(() async {
      final item = await discover('retry.txt', utf8.encode('original bytes'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      final previous = (await ModelPart.get('${item.fileHash}_1'))!;
      final artifact =
          File('${fixture.directory.path}/${item.fileHash}_1.crypt.ready');
      expect(await artifact.exists(), isTrue);
      await artifact.writeAsString('corrupt ciphertext', mode: FileMode.append);
      await finishUpload(item);
      final current = (await ModelPart.get('${item.fileHash}_1'))!;
      expect(current.cipher, isNot(previous.cipher));
      expect(current.uploaded, 1);
      expect(await artifact.exists(), isFalse);
      await File('${fixture.source.path}/retry.txt').delete();
      await download(item);
      expect(await File('${fixture.source.path}/retry.txt').readAsString(),
          'original bytes');
    });
  });

  test('permanent upload rejection retains source and reports a blocked task',
      () async {
    final api = TransferApi()..uploadStatuses.add(413);
    await api.run(() async {
      final item =
          await discover('too-large.txt', utf8.encode('source preserved'));
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(
          (await ModelItemTask.get(item.id))?.state, TransferTaskState.blocked);
      expect((await ModelItemTask.get(item.id))?.lastError, 'upload_otherHttp');
      expect(await File('${fixture.source.path}/too-large.txt').readAsString(),
          'source preserved');
      expect(api.objects, isEmpty);
    });
  });

  test(
      'multipart download resumes after a committed part without downloading it twice',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final bytes =
          List<int>.generate(35 * 1024 * 1024 + 1, (i) => (i * 7) % 251);
      final item = await discover('resume.bin', bytes);
      await finishUpload(item);
      await File('${fixture.source.path}/resume.bin').delete();
      await ModelItemTask.addTask(item.id, ItemTask.download.value);
      await TaskManager()
          .checkInitDownload((await ModelItemTask.get(item.id))!);
      expect(await ModelItemTask.get(item.id), isNotNull);
      expect(await File('${fixture.source.path}/resume.bin').exists(), isFalse);
      expect(api.downloadedIds, ['${item.fileHash}_1']);
      await download(item);
      expect(api.downloadedIds, ['${item.fileHash}_1', '${item.fileHash}_2']);
      expect(await ModelItemTask.get(item.id), isNull);
      expect(
          await File('${fixture.source.path}/resume.bin').readAsBytes(), bytes);
    });
  });

  test(
      'same-basename concurrent downloads cannot mix their plaintext or staging',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final first =
          await discover('first/report.txt', utf8.encode('first report'));
      final second =
          await discover('second/report.txt', utf8.encode('second report'));
      await finishUpload(first);
      await finishUpload(second);
      await File('${fixture.source.path}/first/report.txt').delete();
      await File('${fixture.source.path}/second/report.txt').delete();
      await Future.wait([download(first), download(second)]);
      expect(await ModelItemTask.get(first.id), isNull);
      expect(await ModelItemTask.get(second.id), isNull);
      expect(
          await File('${fixture.source.path}/first/report.txt').readAsString(),
          'first report');
      expect(
          await File('${fixture.source.path}/second/report.txt').readAsString(),
          'second report');
    });
  });

  test('a replaced parent symlink cannot redirect a download outside its root',
      () async {
    final api = TransferApi();
    await api.run(() async {
      final item =
          await discover('nested/report.txt', utf8.encode('cloud backup'));
      await finishUpload(item);
      await Directory('${fixture.source.path}/nested').delete(recursive: true);
      final outside =
          await Directory('${fixture.directory.path}/outside').create();
      await Link('${fixture.source.path}/nested').create(outside.path);
      Object? failure;
      try {
        await download(item);
      } catch (error) {
        failure = error;
      }
      expect(await File('${outside.path}/report.txt').exists(), isFalse,
          reason: 'Download publication must stay inside the selected root');
      expect(failure, isA<PlatformException>());
      expect(await ModelItemTask.get(item.id), isNotNull);
      expect(await ModelItem.get(item.id), isNotNull);
      await Link('${fixture.source.path}/nested').delete();
      await download(item);
      expect(
          await File('${fixture.source.path}/nested/report.txt').readAsString(),
          'cloud backup');
    });
  }, skip: Platform.isWindows);
}
