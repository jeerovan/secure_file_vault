import 'dart:async';
import 'dart:convert' hide json;
import 'dart:io';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/remote_file_copies.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/ui/item_selection_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

class RefreshApi extends TransferApi {
  final List<Map<String, dynamic>> itemPages = [];

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'HEAD') return http.Response('', 200);
    if (request.url.path.endsWith('/devices')) {
      return json({
        'success': 1,
        'data': {'active': 1}
      });
    }
    if (request.url.path.endsWith('/sync') && request.method == 'POST') {
      return json({'success': 1});
    }
    if (request.url.path.endsWith('/sync') && request.method == 'GET') {
      return json({
        'success': 1,
        'data': {
          if (itemPages.isNotEmpty) 'items': [itemPages.removeAt(0)],
        },
      });
    }
    return super.handle(request);
  }
}

/// Fail the actual final publication syscall, after full download/verification.
class FailedReplacement extends Fake implements File {
  FailedReplacement(this.file);
  final File file;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      file.openRead(start, end);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
  @override
  Future<File> rename(String destination) async =>
      throw const FileSystemException('Injected publication failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<ModelItem> upload(List<int> bytes) async {
    await fixture.write('source.txt', bytes);
    await fixture.scan();
    final item = await fixture.item('source.txt');
    for (var attempt = 0; attempt < 8; attempt++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null) break;
      await TaskManager().checkInitUpload(task);
    }
    expect(await ModelItemTask.get(item.id), isNull);
    expect((await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
    return item;
  }

  Future<ModelItem> seedLegacyRemoteCopy(ModelItem source, List<int> bytes,
      {bool downloaded = true, String name = 'copy.txt'}) async {
    final db = await fixture.db;
    await db.insert('items', {
      'id': 'remote-device',
      'parent_id': 'fife',
      'name': 'Other device',
      'is_folder': 1,
    });
    await db.insert('items', {
      'id': 'remote-root',
      'parent_id': 'remote-device',
      'name': 'Remote folder',
      'is_folder': 1,
    });
    final item = await ModelItem.fromMap({
      'id': 'remote-copy',
      'parent_id': 'remote-root',
      'root_id': 'remote-root',
      'name': name,
      'file_hash': source.fileHash,
      'size': bytes.length,
      'updated_at': 1,
    });
    await db.insert('items', item.toMap());
    final file = File(await ModelItem.getPathForItem(item.id));
    if (downloaded) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    return item;
  }

  Future<void> receive(RefreshApi api, ModelItem remote, ModelItem latest,
      {int version = 2,
      bool fetch = true,
      Map<String, dynamic> attributes = const {}}) async {
    final crypto = CryptoUtils(fixture.sodium);
    final plain = {
      ...remote.toMap(),
      'file_hash': latest.fileHash,
      'size': latest.size,
      'updated_at': version,
      'deleted': 0,
      ...attributes,
    };
    final encrypted = crypto.getEncryptedBytesMap(
      Uint8List.fromList(utf8.encode(jsonEncode(plain))),
      base64Decode(fixture.secrets[AppString.masterKey.string]!),
    );
    api.itemPages.add({
      '1': version,
      '3': version,
      '7': encrypted[AppString.textCipher.string],
      '8': encrypted[AppString.textNonce.string],
      '9': encrypted[AppString.keyCipher.string],
      '10': encrypted[AppString.keyNonce.string],
      '11': version,
    });
    if (fetch) expect(await SyncUtils.fetchMapChanges(), isTrue);
  }

  Future<void> action(String id, ItemSelectionAction action) async {
    final selection = ValueNotifier({(await ModelItem.get(id))!});
    final actions = ItemSelectionActions(selection);
    try {
      await actions.refresh();
      expect(actions.allows(action), isTrue);
      expect(await actions.perform(action), isTrue);
    } finally {
      actions.dispose();
      selection.dispose();
    }
  }

  Future<void> waitFor(Future<bool> Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for automatic retry');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // Queue removal precedes the worker's staging cleanup/lease release. Join
    // that running dispatcher before the fixture closes its database/server.
    await TaskManager.init();
  }

  test(
      'normal task startup refreshes an existing remote copy after metadata sync',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final oldBytes = utf8.encode('initial downloaded version');
      final newBytes = utf8.encode('latest version from the source device');
      final original = await upload(oldBytes);
      // An already-downloaded pre-upgrade copy is the initial condition. The
      // fixture does not supply a refresh marker or queue the changed file.
      final remote = await seedLegacyRemoteCopy(original, oldBytes);
      final cache = File(await ModelItem.getPathForItem(remote.id));
      final latest = await upload(newBytes);
      await receive(api, remote, latest);
      expect(await cache.readAsBytes(), oldBytes);
      expect(await ModelItemTask.get(remote.id), isNull);

      api.beforeDownloadResponse = () async {
        expect(await cache.readAsBytes(), oldBytes,
            reason: 'The old copy remains readable until verified publication');
      };
      await TaskManager.init();

      expect(await cache.readAsBytes(), newBytes);
      expect(await ModelItemTask.get(remote.id), isNull);
      expect(await File('${fixture.source.path}/source.txt').readAsBytes(),
          newBytes);
    });
  });

  test('normal Sync entry point refreshes a copy and repeated sync is idle',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('previous');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final latest = utf8.encode('replaced'); // Same size, different content.
      await receive(api, remote, await upload(latest), fetch: false);
      // Auth is a fixture precondition (no signedIn flag/Neon cookie). The
      // actual sync entry point must fetch metadata and start its own queue.
      expect(
          await SyncUtils().triggerSync(caller: 'RemoteRefreshTest'), isTrue);
      final cache = File(await ModelItem.getPathForItem(remote.id));
      expect(await cache.readAsBytes(), latest);
      final downloads = api.downloadedIds.length;
      expect(await SyncUtils().triggerSync(), isTrue);
      expect(api.downloadedIds.length, downloads);
      expect(await ModelItemTask.get(remote.id), isNull);
    });
  });

  test(
      'never-downloaded files stay absent; explicit download subscribes to later changes',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('initial');
      final remote =
          await seedLegacyRemoteCopy(await upload(old), old, downloaded: false);
      final cache = File(await ModelItem.getPathForItem(remote.id));
      await TaskManager.init();
      expect(await cache.exists(), isFalse);
      expect(api.downloadedIds, isEmpty);
      await action(remote.id, ItemSelectionAction.download);
      await TaskManager.init();
      expect(await cache.readAsBytes(), old);
      final latest = utf8.encode('new source bytes');
      await receive(api, remote, await upload(latest));
      await TaskManager.init();
      expect(await cache.readAsBytes(), latest);
    });
  });

  for (final corrupt in [false, true]) {
    test(
        '${corrupt ? "corrupted" : "unavailable"} download preserves old bytes and retries after SQLite reopen',
        () async {
      final api = RefreshApi();
      await api.run(() async {
        final old = utf8.encode('keep until verified');
        final remote = await seedLegacyRemoteCopy(await upload(old), old);
        final cache = File(await ModelItem.getPathForItem(remote.id));
        final latest = utf8.encode('verified replacement');
        await receive(api, remote, await upload(latest));
        if (corrupt) {
          api.alterDownload = (bytes) => [...bytes]..[0] ^= 1;
        } else {
          api.downloadStatuses.add(503);
        }
        await TaskManager.init();
        expect(await cache.readAsBytes(), old);
        expect((await ModelItemTask.get(remote.id))!.state,
            TransferTaskState.retryWaiting);
        await TaskManager.stopBackgroundWakes();
        await StorageSqlite.instance.close();
        await StorageSqlite.initialize(ExecutionMode.mainApp);
        api.alterDownload = null;
        await TaskManager.init(); // No queue/intent repair or fake retry clock.
        await waitFor(() async => await ModelItemTask.get(remote.id) == null);
        expect(await cache.readAsBytes(), latest);
      });
    });
  }

  test(
      'newer metadata during download prevents stale publication and automatically wins',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final middle = await upload(utf8.encode('middle'));
      final latestBytes = utf8.encode('latest');
      final latest = await upload(latestBytes);
      await receive(api, remote, middle);
      final cache = File(await ModelItem.getPathForItem(remote.id));
      final zone = Zone.current;
      var attempts = 0;
      api.beforeDownloadResponse = () => zone.run(() async {
            expect(await cache.readAsBytes(), old);
            if (attempts++ == 0) await receive(api, remote, latest, version: 3);
          });
      await TaskManager.init();
      expect(attempts, 2);
      expect(await cache.readAsBytes(), latestBytes);
      expect(await ModelItemTask.get(remote.id), isNull);
    });
  });

  for (final folder in [false, true]) {
    test(
        'deleting ${folder ? "folder" : "file"} copy during refresh prevents resurrection; explicit redownload works',
        () async {
      final api = RefreshApi();
      await api.run(() async {
        final old = utf8.encode('old');
        final remote = await seedLegacyRemoteCopy(await upload(old), old);
        final latest = utf8.encode('latest source');
        await receive(api, remote, await upload(latest));
        final cache = File(await ModelItem.getPathForItem(remote.id));
        final zone = Zone.current;
        api.beforeDownloadResponse = () => zone.run(() async {
              await action(folder ? 'remote-root' : remote.id,
                  ItemSelectionAction.deleteLocal);
            });
        await TaskManager.init();
        expect(await cache.exists(), isFalse);
        expect(await ModelItemTask.get(remote.id), isNull);
        api.beforeDownloadResponse = null;
        await TaskManager.init();
        expect(await cache.exists(), isFalse);
        expect(await File('${fixture.source.path}/source.txt').readAsBytes(),
            latest);
        await action(remote.id, ItemSelectionAction.download);
        await TaskManager.init();
        expect(await cache.readAsBytes(), latest);
      });
    });
  }

  test('empty replacement is verified and published over the old content',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('nonempty');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      await receive(api, remote, await upload([]));
      await TaskManager.init();
      expect(await File(await ModelItem.getPathForItem(remote.id)).length(), 0);
      expect(await ModelItemTask.get(remote.id), isNull);
    });
  });

  test(
      'a valid long filename can be replaced without exceeding the filesystem name limit',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old');
      final name = '${List.filled(240, 'x').join()}.txt';
      final remote =
          await seedLegacyRemoteCopy(await upload(old), old, name: name);
      final latest = utf8.encode('latest');
      await receive(api, remote, await upload(latest));
      await TaskManager.init();
      expect(
          await File(await ModelItem.getPathForItem(remote.id)).readAsBytes(),
          latest);
      expect(await ModelItemTask.get(remote.id), isNull);
    });
  });

  test(
      'archiving source during refresh retains previous bytes and stops obsolete work',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final latest = await upload(utf8.encode('new'));
      await receive(api, remote, latest);
      final zone = Zone.current;
      api.beforeDownloadResponse = () => zone.run(() async {
            await receive(api, remote, latest,
                version: 3, attributes: {'archived_at': 5});
          });
      await TaskManager.init();
      expect(
          await File(await ModelItem.getPathForItem(remote.id)).readAsBytes(),
          old);
      expect(await ModelItemTask.get(remote.id), isNull);
    });
  });

  test(
      'final replacement failure leaves old copy intact and automatic retry succeeds',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old saved file');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final latest = utf8.encode('new verified file');
      await receive(api, remote, await upload(latest));
      final cache = File(await ModelItem.getPathForItem(remote.id));
      var failReplacement = true;
      await IOOverrides.runZoned(() async {
        await TaskManager.init();
        expect(await cache.readAsBytes(), old);
        expect((await ModelItemTask.get(remote.id))!.state,
            TransferTaskState.retryWaiting);
        expect(
            await cache.parent
                .list()
                .where((file) => file.path.endsWith('.fife-partial'))
                .toList(),
            isEmpty);
        failReplacement = false;
        await waitFor(() async => await ModelItemTask.get(remote.id) == null);
        expect(await cache.readAsBytes(), latest);
      }, createFile: (path) {
        final file = Zone.root.run(() => File(path));
        return failReplacement && path.endsWith('.fife-partial')
            ? FailedReplacement(file)
            : file;
      });
    });
  });

  for (final table in ['files', 'parts']) {
    test(
        'delayed $table metadata preserves the old copy and resumes automatically',
        () async {
      final api = RefreshApi();
      await api.run(() async {
        final old = utf8.encode('old');
        final remote = await seedLegacyRemoteCopy(await upload(old), old);
        final latestBytes = utf8.encode('eventually available');
        final latest = await upload(latestBytes);
        final db = await fixture.db;
        final id = table == 'files' ? latest.fileHash! : '${latest.fileHash}_1';
        final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
        expect(rows, hasLength(1));
        await db.delete(table, where: 'id = ?', whereArgs: [id]);
        await receive(api, remote, latest);
        await TaskManager.init();
        final cache = File(await ModelItem.getPathForItem(remote.id));
        expect(await cache.readAsBytes(), old);
        expect(
            (await ModelItemTask.get(remote.id))!.lastError,
            table == 'files'
                ? 'missing_file_metadata'
                : 'missing_part_metadata');
        // Simulate the delayed server page; do not alter the retry/intent queue.
        await db.insert(table, rows.single);
        await waitFor(() async => await ModelItemTask.get(remote.id) == null);
        expect(await cache.readAsBytes(), latestBytes);
      });
    });
  }

  test(
      'source rename keeps old copy readable until replacement and retires the old path',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final oldCache = File(await ModelItem.getPathForItem(remote.id));
      await TaskManager.init(); // Normal startup adopts the pre-upgrade copy.
      final latest = utf8.encode('renamed and modified');
      await receive(api, remote, await upload(latest),
          attributes: {'name': 'renamed.txt'});
      final zone = Zone.current;
      api.beforeDownloadResponse = () => zone.run(() async {
            expect(
                await LocalItemAccess.withReadableAccess(
                    remote.id, (path) => File(path).readAsBytes()),
                old);
          });
      await TaskManager.init();
      expect(
          await File(await ModelItem.getPathForItem(remote.id)).readAsBytes(),
          latest);
      expect(await oldCache.exists(), isFalse);
    });
  });

  test(
      'removing a copy also removes a replacement left by an interrupted process',
      () async {
    final api = RefreshApi();
    await api.run(() async {
      final bytes = utf8.encode('saved');
      final remote = await seedLegacyRemoteCopy(await upload(bytes), bytes);
      await TaskManager.init();
      final cache = File(await ModelItem.getPathForItem(remote.id));
      final record =
          jsonDecode(await ModelState.get('remote_copy:${remote.id}')) as Map;
      // Persisted filesystem state of a process killed before its rename.
      final partial = File(RemoteFileCopies.replacementPath(
          cache.path, record['generation'] as String));
      await partial.writeAsString('incomplete replacement');
      final sibling = File('${cache.parent.path}/unrelated.txt');
      await sibling.writeAsString('keep');
      await action(remote.id, ItemSelectionAction.deleteLocal);
      await TaskManager.init();
      expect(await cache.exists(), isFalse);
      expect(await partial.exists(), isFalse);
      expect(await sibling.readAsString(), 'keep');
    });
  });

  test('copy removed outside FiFe during refresh is not recreated', () async {
    final api = RefreshApi();
    await api.run(() async {
      final old = utf8.encode('old');
      final remote = await seedLegacyRemoteCopy(await upload(old), old);
      final cache = File(await ModelItem.getPathForItem(remote.id));
      await receive(api, remote, await upload(utf8.encode('new')));
      api.beforeDownloadResponse = () async => cache.delete();
      await TaskManager.init();
      expect(await cache.exists(), isFalse);
      expect(await ModelItemTask.get(remote.id), isNull);
      api.beforeDownloadResponse = null;
      await TaskManager.init();
      expect(await cache.exists(), isFalse);
    });
  });

  test(
      'account revocation during refresh clears owned copies and does not publish late data',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('purchases_flutter'), (_) async => false);
    try {
      expect(await SessionCleanup.instance.resume(), isTrue);
      final api = RefreshApi();
      await api.run(() async {
        final old = utf8.encode('private old copy');
        final remote = await seedLegacyRemoteCopy(await upload(old), old);
        final latest = utf8.encode('private new copy');
        await receive(api, remote, await upload(latest));
        final cache = File(await ModelItem.getPathForItem(remote.id));
        final zone = Zone.current;
        final cleanup = Completer<bool>();
        api.beforeDownloadResponse = () => zone.run(() async {
              cleanup.complete(await SessionCleanup.instance.request());
            });
        try {
          await TaskManager.init();
        } on SessionInvalidated {
          // The running dispatcher's caller also loses access on revocation.
        }
        expect(
            await cleanup.future.timeout(const Duration(seconds: 10)), isTrue);
        expect(await cache.exists(), isFalse);
        expect(await ModelItem.get(remote.id), isNull);
        expect(await ModelItemTask.get(remote.id), isNull);
        expect(await File('${fixture.source.path}/source.txt').readAsBytes(),
            latest);
      });
    } finally {
      messenger.setMockMethodCallHandler(
          const MethodChannel('purchases_flutter'), null);
    }
  });
}
