import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_file_viewer.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/managed_file_copies.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/synced_folder_access.dart';
import 'package:file_vault_bb/ui/item_file_opener.dart';
import 'package:file_vault_bb/ui/item_selection_actions.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'download_revocation_test.dart' show PausedRename;
import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

class _Viewer extends FileViewerPlatform {
  final paths = <String>[];
  @override
  Future<FileViewResult> open(String path) async {
    paths.add(path);
    return FileViewResult.opened;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late FileViewerPlatform originalViewer;
  setUp(() async {
    fixture = await SyncFixture.create();
    originalViewer = FileViewerPlatform.instance;
  });
  tearDown(() async {
    FileViewerPlatform.instance = originalViewer;
    await fixture.dispose();
  });

  Future<ModelItem> upload(String name, String content) async {
    await fixture.text(name, content);
    expect((await fixture.scan()).status, ReconciliationStatus.completed);
    final item = await fixture.item(name);
    for (var step = 0; step < 8; step++) {
      final task = await ModelItemTask.get(item.id);
      if (task == null) break;
      await TaskManager().checkInitUpload(task);
    }
    expect(await ModelItemTask.get(item.id), isNull);
    expect((await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
    return item;
  }

  Future<bool> act(ModelItem item, ItemSelectionAction action) async {
    final selected = ValueNotifier<Set<ModelItem>>({item});
    final actions = ItemSelectionActions(selected);
    try {
      await actions.refresh();
      expect(actions.allows(action), isTrue);
      return await actions.perform(action);
    } finally {
      actions.dispose();
      selected.dispose();
    }
  }

  Future<void> finishDownload(String id) async {
    for (var step = 0; step < 8; step++) {
      final task = await ModelItemTask.get(id);
      if (task == null) break;
      expect(task.state, isNot(TransferTaskState.blocked));
      await TaskManager().checkInitDownload(task);
    }
    expect(await ModelItemTask.get(id), isNull);
  }

  test('selected disconnected file downloads after restart and opens its copy',
      () async {
    await TransferApi().run(() async {
      final item = await upload('nested/deeper/read.txt', 'cloud backup');
      fixture.accessAllowed = false;
      final rootBefore = await (await fixture.db)
          .query('items', where: 'id = ?', whereArgs: [SyncFixture.rootId]);
      final source = File('${fixture.source.path}/nested/deeper/read.txt');
      await source.delete();
      expect(await act(item, ItemSelectionAction.download), isTrue);
      final destination = (await ManagedFileCopies.downloadPath(item.id))!;
      expect(destination, endsWith('/source/nested/deeper/read.txt'));
      expect(p.isWithin(await ModelItem.getPathForItem('fife'), destination),
          isTrue);
      // The production action creates the intent; no test seeds its destination.
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      expect(await ManagedFileCopies.downloadPath(item.id), destination);
      await finishDownload(item.id);
      expect(await File(destination).readAsString(), 'cloud backup');
      expect(await source.exists(), isFalse);
      expect(await SyncedFolderAccess.isAvailable(await fixture.root), isFalse);
      expect(
          await (await fixture.db)
              .query('items', where: 'id = ?', whereArgs: [SyncFixture.rootId]),
          rootBefore);
      expect(
          await LocalItemAccess.withReadableAccess(
              item.id, (path) => File(path).readAsString()),
          'cloud backup');
      await expectLater(
          LocalItemAccess.acquire(item.id), throwsA(isA<PlatformException>()),
          reason: 'Upload/source access must not use the recovery copy');
      final viewer = _Viewer();
      FileViewerPlatform.instance = viewer;
      final opener = ItemFileOpener();
      expect(await opener.open(item.id, canPresent: () => true),
          ItemOpenResult.opened);
      expect(viewer.paths, [destination]);
      opener.dispose();
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('root download queues backed-up descendants and skips archived trees',
      () async {
    await TransferApi().run(() async {
      final first = await upload('nested/one.txt', 'one');
      final second = await upload('two.txt', 'two');
      final archived = await upload('archived/hidden.txt', 'excluded');
      final db = await fixture.db;
      final archivedFolder = await fixture.item('archived');
      await db.update('items', {'archived_at': 10},
          where: 'id = ?', whereArgs: [archivedFolder.id]);
      await db.insert('items', {
        'id': 'unbacked',
        'parent_id': SyncFixture.rootId,
        'name': 'unbacked.txt',
        'file_hash': null,
      });
      await db.insert('items', {
        'id': 'empty',
        'parent_id': first.parentId,
        'name': 'empty',
        'is_folder': 1,
      });
      fixture.accessAllowed = false;
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      expect(await ModelItemTask.get(archived.id), isNull);
      expect(await ModelItemTask.get('unbacked'), isNull);
      final firstPath = (await ManagedFileCopies.downloadPath(first.id))!;
      final secondPath = (await ManagedFileCopies.downloadPath(second.id))!;
      expect(p.dirname(p.dirname(firstPath)), p.dirname(secondPath));
      expect(await Directory(p.join(p.dirname(firstPath), 'empty')).exists(),
          isTrue);
      for (final item in [first, second]) {
        await finishDownload(item.id);
      }
      expect(await File(firstPath).readAsString(), 'one');
      expect(await File(secondPath).readAsString(), 'two');
      expect(await File('${fixture.source.path}/nested/one.txt').readAsString(),
          'one',
          reason: 'Downloading must not change the external original');
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      expect(await ModelItemTask.get(first.id), isNull);
      expect(await ManagedFileCopies.existingPath(first.id), firstPath);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'explicit reconnect deletes the whole managed folder without comparing originals',
      () async {
    await TransferApi().run(() async {
      final item = await upload('nested/file.txt', 'backed up version');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      final copy = (await ManagedFileCopies.existingPath(item.id))!;
      final rootCopies =
          Directory(p.dirname(p.dirname(p.dirname(p.dirname(copy)))));
      await File('${rootCopies.path}/unreferenced-old-version.txt')
          .writeAsString('old copy');
      await fixture.text('nested/file.txt', 'different external content');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SyncFixture.access, (call) async {
        if (call.method == 'pickDirectory') {
          return {'path': fixture.source.path, 'bookmark': 'reconnected'};
        }
        if (call.method == 'startAccessing') return fixture.source.path;
        return true;
      });
      expect(await SyncedFolderAccess.reselect(await fixture.root), isNotNull);
      expect(await rootCopies.exists(), isFalse);
      expect(
          await File('${fixture.source.path}/nested/file.txt').readAsString(),
          'different external content');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('subfolder archive clears only its copies and preserves siblings',
      () async {
    await TransferApi().run(() async {
      final child = await upload('nested/deeper/file.txt', 'archived original');
      final sibling = await upload('sibling/file.txt', 'sibling original');
      fixture.accessAllowed = false;
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      await finishDownload(child.id);
      await finishDownload(sibling.id);
      final copy = (await ManagedFileCopies.existingPath(child.id))!;
      final siblingCopy = (await ManagedFileCopies.existingPath(sibling.id))!;
      final subtree = Directory(p.dirname(p.dirname(copy)));
      await File('${subtree.path}/old-unreferenced.txt')
          .writeAsString('old copy');
      fixture.accessAllowed = true;
      final changed = await upload('nested/deeper/file.txt', 'new original');
      fixture.accessAllowed = false;
      expect(await act(changed, ItemSelectionAction.download), isTrue);
      await finishDownload(changed.id);
      final newerCopy = (await ManagedFileCopies.existingPath(changed.id))!;
      expect(newerCopy, isNot(copy));
      expect(await File(copy).exists(), isTrue);
      final nested = await fixture.item('nested');
      expect(await act(nested, ItemSelectionAction.archive), isTrue);
      expect(await subtree.exists(), isFalse);
      expect(await File(newerCopy).exists(), isFalse);
      expect(await File(siblingCopy).readAsString(), 'sibling original');
      expect((await fixture.root).archivedAt, 0);
      expect((await ModelItem.get(nested.id))!.archivedAt, greaterThan(0));
      expect(
          await File('${fixture.source.path}/nested/deeper/file.txt')
              .readAsString(),
          'new original');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'subfolder archive survives reconnect and skips changed and new source files',
      () async {
    await TransferApi().run(() async {
      final child = await upload('nested/old.txt', 'archived version');
      final sibling = await upload('sibling/live.txt', 'sibling version');
      final nested = await fixture.item('nested');
      fixture.accessAllowed = false;
      expect(await act(nested, ItemSelectionAction.archive), isTrue);
      await fixture.text('nested/old.txt', 'changed while excluded');
      await fixture.text('nested/new.txt', 'new while excluded');
      await fixture.text('sibling/live.txt', 'sibling changed');
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      fixture.accessAllowed = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SyncFixture.access, (call) async {
        if (call.method == 'pickDirectory') {
          return {'path': fixture.source.path, 'bookmark': 'fresh'};
        }
        if (call.method == 'startAccessing') return fixture.source.path;
        return true;
      });
      expect(await SyncedFolderAccess.reselect(await fixture.root), isNotNull);
      expect((await fixture.scan()).status, ReconciliationStatus.completed);
      expect((await ModelItem.get(nested.id))!.archivedAt, greaterThan(0));
      expect((await ModelItem.get(child.id))!.fileHash, child.fileHash);
      expect(await ModelItemTask.get(child.id), isNull);
      expect(
          (await ModelItem.getAllInFolder(await ModelItem.get(nested.id)))
              .map((e) => e.name),
          ['old.txt']);
      expect(await ModelItemTask.get(sibling.id), isNotNull);
      await ManagedFileCopies.restoreFolder((await ModelItem.get(nested.id))!);
      expect((await fixture.scan()).status, ReconciliationStatus.completed);
      expect((await ModelItem.get(child.id))!.fileHash, isNot(child.fileHash));
      expect(await ModelItemTask.get(child.id), isNotNull);
      expect((await fixture.item('nested/new.txt')).fileHash, isNotNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'subfolder archived during a scan cannot be reactivated by its old snapshot',
      () async {
    await TransferApi().run(() async {
      final child = await upload('nested/file.txt', 'old version');
      final nested = await fixture.item('nested');
      await fixture.text('nested/file.txt', 'changed version');
      final entered = Completer<void>(), release = Completer<void>();
      fixture.beforeRead = (key) async {
        if (key == AppString.fileHashKey.string && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final scanning = fixture.scan();
      try {
        await entered.future.timeout(const Duration(seconds: 10));
        fixture.accessAllowed = false;
        expect(await act(nested, ItemSelectionAction.archive), isTrue);
        fixture.beforeRead = null;
        release.complete();
        expect((await scanning).status, ReconciliationStatus.busy);
        expect((await ModelItem.get(child.id))!.fileHash, child.fileHash);
        expect(await ModelItemTask.get(child.id), isNull);
        fixture.accessAllowed = true;
        expect((await fixture.scan()).status, ReconciliationStatus.completed);
        expect((await ModelItem.get(nested.id))!.archivedAt, greaterThan(0));
        expect((await ModelItem.get(child.id))!.fileHash, child.fileHash);
      } finally {
        fixture.beforeRead = null;
        if (!release.isCompleted) release.complete();
        await scanning;
      }
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('subfolder archive cancels only its in-flight download', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var first = true;
    final api = TransferApi()
      ..beforeDownloadResponse = () async {
        if (!first) return;
        first = false;
        entered.complete();
        await release.future;
      };
    await api.run(() async {
      final child = await upload('nested/late.txt', 'archived original');
      final sibling = await upload('sibling.txt', 'keep sibling');
      fixture.accessAllowed = false;
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      final childCopy = (await ManagedFileCopies.downloadPath(child.id))!;
      final siblingCopy = (await ManagedFileCopies.downloadPath(sibling.id))!;
      final downloading =
          TaskManager().checkInitDownload((await ModelItemTask.get(child.id))!);
      try {
        await entered.future.timeout(const Duration(seconds: 10));
        expect(
            await act(
                await fixture.item('nested'), ItemSelectionAction.archive),
            isTrue);
        expect(await ModelItemTask.get(child.id), isNull);
        expect(await ModelItemTask.get(sibling.id), isNotNull);
        await finishDownload(sibling.id);
        release.complete();
        await downloading.timeout(const Duration(seconds: 10));
        expect(await File(childCopy).exists(), isFalse);
        expect(await File(siblingCopy).readAsString(), 'keep sibling');
        expect(
            await File('${fixture.source.path}/nested/late.txt').readAsString(),
            'archived original');
      } finally {
        if (!release.isCompleted) release.complete();
        await downloading;
      }
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('subfolder cleanup retries before Restore and preserves sibling copies',
      () async {
    await TransferApi().run(() async {
      final child = await upload('nested/file.txt', 'original');
      final sibling = await upload('sibling.txt', 'sibling');
      fixture.accessAllowed = false;
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      await finishDownload(child.id);
      await finishDownload(sibling.id);
      final childCopy = (await ManagedFileCopies.existingPath(child.id))!;
      final siblingCopy = (await ManagedFileCopies.existingPath(sibling.id))!;
      final downloads = Directory(
          p.join(await ModelItem.getPathForItem('fife'), '.downloads'));
      final held = await downloads.rename('${downloads.path}.held');
      await Link(downloads.path).create(held.path);
      final folder = await fixture.item('nested');
      expect(await act(folder, ItemSelectionAction.archive), isFalse);
      await expectLater(ManagedFileCopies.restoreFolder(folder),
          throwsA(isA<PlatformException>()));
      expect((await ModelItem.get(folder.id))!.archivedAt, greaterThan(0));
      await Link(downloads.path).delete();
      await held.rename(downloads.path);
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      await SyncUtils().reconFolders(caller: 'subfolder-cleanup-retry');
      expect(await File(childCopy).exists(), isFalse);
      expect(await File(siblingCopy).readAsString(), 'sibling');
      await ManagedFileCopies.restoreFolder(folder);
      expect((await ModelItem.get(folder.id))!.archivedAt, 0);
      expect(await act(child, ItemSelectionAction.download), isTrue);
      await finishDownload(child.id);
      expect(
          await File((await ManagedFileCopies.existingPath(child.id))!)
              .readAsString(),
          'original');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('archive removes already downloaded copies and all old versions',
      () async {
    await TransferApi().run(() async {
      final item = await upload('nested/file.txt', 'external original');
      fixture.accessAllowed = false;
      expect(
          await act(await fixture.root, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      final copy = (await ManagedFileCopies.existingPath(item.id))!;
      final rootCopies =
          Directory(p.dirname(p.dirname(p.dirname(p.dirname(copy)))));
      await File('${rootCopies.path}/unreferenced-old-version.txt')
          .writeAsString('old copy');
      expect(
          await act(await fixture.root, ItemSelectionAction.archive), isTrue);
      expect(await rootCopies.exists(), isFalse);
      expect((await fixture.root).archivedAt, greaterThan(0));
      expect(
          await File('${fixture.source.path}/nested/file.txt').readAsString(),
          'external original');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'restored permission without explicit Reconnect keeps queued destination',
      () async {
    await TransferApi().run(() async {
      final item = await upload('file.txt', 'backed up version');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      final destination = await ManagedFileCopies.downloadPath(item.id);
      // Represents source access restored while the transfer is pending.
      fixture.accessAllowed = true;
      await fixture.text('file.txt', 'new external content, not scanned yet');
      await finishDownload(item.id);
      expect(await ManagedFileCopies.existingPath(item.id), destination);
      expect(await File(destination!).readAsString(), 'backed up version');
      expect(await File('${fixture.source.path}/file.txt').readAsString(),
          'new external content, not scanned yet');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('changed content creates a new copy without overwriting the old version',
      () async {
    await TransferApi().run(() async {
      final before = await upload('version.txt', 'old version');
      fixture.accessAllowed = false;
      expect(await act(before, ItemSelectionAction.download), isTrue);
      await finishDownload(before.id);
      final oldPath = (await ManagedFileCopies.existingPath(before.id))!;
      fixture.accessAllowed = true;
      final after = await upload('version.txt', 'new version');
      expect(after.id, before.id);
      fixture.accessAllowed = false;
      expect(await ManagedFileCopies.existingPath(after.id), isNull);
      expect(await act(after, ItemSelectionAction.download), isTrue);
      await finishDownload(after.id);
      final newPath = (await ManagedFileCopies.existingPath(after.id))!;
      expect(newPath, isNot(oldPath));
      expect(await File(oldPath).readAsString(), 'old version');
      expect(await File(newPath).readAsString(), 'new version');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('failed transfer retries the same destination without touching source',
      () async {
    final api = TransferApi()..downloadStatuses.add(500);
    await api.run(() async {
      final item = await upload('retry.txt', 'retry bytes');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      final destination = await ManagedFileCopies.downloadPath(item.id);
      await TaskManager()
          .checkInitDownload((await ModelItemTask.get(item.id))!);
      expect(await ModelItemTask.get(item.id), isNotNull);
      expect(await File(destination!).exists(), isFalse);
      await finishDownload(item.id);
      expect(await ManagedFileCopies.existingPath(item.id), destination);
      expect(await File(destination).readAsString(), 'retry bytes');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('archive excludes source scans and drops pending child transfers',
      () async {
    await TransferApi().run(() async {
      final item = await upload('archive.txt', 'keep external original');
      final root = await fixture.root;
      fixture.accessAllowed = false;
      expect(await act(root, ItemSelectionAction.download), isTrue);
      final destination = await ManagedFileCopies.downloadPath(item.id);
      final oldTask = (await ModelItemTask.get(item.id))!;
      expect(await act(root, ItemSelectionAction.archive), isTrue);
      fixture.accessAllowed = true;
      expect(await ModelItem.getAllSyncedFolders(), isEmpty);
      expect(
          (await ReconciliationService(fixture.sodium).reconcile(root)).status,
          ReconciliationStatus.unavailable);
      expect(await ModelItemTask.get(item.id), isNull);
      await TaskManager().checkInitDownload(oldTask);
      expect(await ModelItemTask.get(item.id), isNull);
      expect(await File(destination!).exists(), isFalse);
      await ModelItemTask.addTask(item.id, ItemTask.upload.value);
      await TaskManager().checkInitUpload((await ModelItemTask.get(item.id))!);
      expect(await ModelItemTask.get(item.id), isNull);
      expect((await fixture.root).archivedAt, greaterThan(0));
      expect(await File('${fixture.source.path}/archive.txt').readAsString(),
          'keep external original');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  for (final reconnect in [false, true]) {
    test(
        '${reconnect ? "Reconnect" : "Archive"} prevents an in-flight download recreating copies or writing originals',
        () async {
      final entered = Completer<void>(), release = Completer<void>();
      final api = TransferApi()
        ..beforeDownloadResponse = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
      await api.run(() async {
        final item = await upload('nested/late.txt', 'queued cloud content');
        await File('${fixture.source.path}/nested/late.txt').delete();
        fixture.accessAllowed = false;
        expect(await act(item, ItemSelectionAction.download), isTrue);
        final destination = (await ManagedFileCopies.downloadPath(item.id))!;
        final oldTask = (await ModelItemTask.get(item.id))!;
        final downloading = TaskManager().checkInitDownload(oldTask);
        try {
          await entered.future.timeout(const Duration(seconds: 10));
          if (reconnect) {
            final messenger = TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(SyncFixture.access,
                (call) async {
              if (call.method == 'pickDirectory') {
                return {'path': fixture.source.path, 'bookmark': 'fresh'};
              }
              if (call.method == 'startAccessing') return fixture.source.path;
              return true;
            });
            expect(await SyncedFolderAccess.reselect(await fixture.root),
                isNotNull);
          } else {
            expect(await act(await fixture.root, ItemSelectionAction.archive),
                isTrue);
          }
          expect(await ModelItemTask.get(item.id), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await downloading.timeout(const Duration(seconds: 10));
        }
        expect(await File(destination).exists(), isFalse);
        expect(await File('${fixture.source.path}/nested/late.txt').exists(),
            isFalse);
        expect(await ManagedFileCopies.existingPath(item.id), isNull);
        expect(await ModelItemTask.get(item.id), isNull);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);
  }

  for (final subtree in [false, true]) {
    test(
        '${subtree ? "subfolder" : "root"} archive waits for a publishing copy then removes it',
        () async {
      final entered = Completer<void>(), release = Completer<void>();
      await IOOverrides.runZoned(
          () async {
            await TransferApi().run(() async {
              final filename =
                  subtree ? 'nested/publishing.txt' : 'publishing.txt';
              final item = await upload(filename, 'external source');
              final archivedFolder =
                  subtree ? await fixture.item('nested') : await fixture.root;
              fixture.accessAllowed = false;
              expect(await act(item, ItemSelectionAction.download), isTrue);
              final copy = (await ManagedFileCopies.downloadPath(item.id))!;
              final downloading = TaskManager()
                  .checkInitDownload((await ModelItemTask.get(item.id))!);
              Future<bool>? archiving;
              var finished = false;
              try {
                await entered.future.timeout(const Duration(seconds: 10));
                archiving = act(archivedFolder, ItemSelectionAction.archive)
                    .then((value) {
                  finished = true;
                  return value;
                });
                final watch = Stopwatch()..start();
                while (!await ManagedFileCopies.cleanupPending(
                        archivedFolder.id) &&
                    watch.elapsed < const Duration(seconds: 5)) {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                }
                expect(
                    await ManagedFileCopies.cleanupPending(archivedFolder.id),
                    isTrue);
                expect(finished, isFalse);
                release.complete();
                await downloading.timeout(const Duration(seconds: 10));
                expect(await archiving, isTrue);
                expect(await File(copy).exists(), isFalse);
                expect(
                    await File('${fixture.source.path}/$filename')
                        .readAsString(),
                    'external source');
              } finally {
                if (!release.isCompleted) release.complete();
                await downloading;
                if (archiving != null) await archiving;
              }
            });
          },
          fseGetType: (path, followLinks) => Zone.root
              .run(() => FileSystemEntity.type(path, followLinks: followLinks)),
          createFile: (path) {
            final real = Zone.root.run(() => File(path));
            return path.endsWith('/assembled.partial')
                ? PausedRename(real, entered, release)
                : real;
          });
    }, skip: !Platform.isMacOS && !Platform.isIOS);
  }

  test(
      'blocked archive cleanup persists and normal sync retries it after restart',
      () async {
    await TransferApi().run(() async {
      final item = await upload('nested/failure.txt', 'preserve original');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      final copy = (await ManagedFileCopies.existingPath(item.id))!;
      final rootCopies = p.dirname(p.dirname(p.dirname(p.dirname(copy))));
      // Use a real unsafe filesystem boundary rather than a mocked delete.
      final downloads = Directory(p.dirname(rootCopies));
      final held = await downloads.rename('${downloads.path}.held');
      await Link(downloads.path).create(held.path);
      expect(
          await act(await fixture.root, ItemSelectionAction.archive), isFalse);
      expect(
          await ManagedFileCopies.cleanupPending(SyncFixture.rootId), isTrue);
      expect(await File(copy).exists(), isTrue);
      expect((await fixture.root).archivedAt, greaterThan(0));
      await Link(downloads.path).delete();
      await held.rename(downloads.path);
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      await StorageSqlite.initialize(ExecutionMode.mainApp);
      // Exercise the ordinary sync entry point, including its offline/no-auth
      // early exits. No test calls the cleanup retry method directly.
      await SyncUtils().reconFolders(caller: 'cleanup-regression');
      expect(await Directory(rootCopies).exists(), isFalse);
      expect(
          await ManagedFileCopies.cleanupPending(SyncFixture.rootId), isFalse);
      expect(
          await File('${fixture.source.path}/nested/failure.txt')
              .readAsString(),
          'preserve original');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'a new explicit download after archive restoration is not permanently cancelled',
      () async {
    await TransferApi().run(() async {
      final item = await upload('restore.txt', 'retained cloud backup');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      expect(
          await act(await fixture.root, ItemSelectionAction.archive), isTrue);
      final root = await fixture.root;
      root.archivedAt = 0;
      await root.update(['archived_at']);
      expect(await ManagedFileCopies.existingPath(item.id), isNull);
      expect(await act(item, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      final copy = (await ManagedFileCopies.existingPath(item.id))!;
      expect(await File(copy).readAsString(), 'retained cloud backup');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('canceling reconnect preserves downloaded copies and queued work',
      () async {
    await TransferApi().run(() async {
      final item = await upload('cancel.txt', 'downloaded content');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      await finishDownload(item.id);
      final copy = (await ManagedFileCopies.existingPath(item.id))!;
      final before = await (await fixture.db).query('states');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SyncFixture.access, (_) async => null);
      expect(await SyncedFolderAccess.reselect(await fixture.root), isNull);
      expect(await File(copy).readAsString(), 'downloaded content');
      expect(await (await fixture.db).query('states'), before);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('a replaced managed directory cannot redirect plaintext outside FiFe',
      () async {
    await TransferApi().run(() async {
      final item = await upload('link.txt', 'private test bytes');
      fixture.accessAllowed = false;
      expect(await act(item, ItemSelectionAction.download), isTrue);
      final destination = (await ManagedFileCopies.downloadPath(item.id))!;
      final outside =
          await Directory('${fixture.directory.path}/outside').create();
      await Directory(p.dirname(destination)).create(recursive: true);
      await Directory(p.dirname(destination)).delete(recursive: true);
      await Link(p.dirname(destination)).create(outside.path);
      await expectLater(
          finishDownload(item.id), throwsA(isA<PlatformException>()));
      expect(await outside.list().toList(), isEmpty);
      expect(await ModelItemTask.get(item.id), isNotNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('logout removes managed copies and retains external originals',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('purchases_flutter'), (_) async => false);
    try {
      await TransferApi().run(() async {
        final item = await upload('keep.txt', 'external and backup');
        fixture.accessAllowed = false;
        expect(await act(item, ItemSelectionAction.download), isTrue);
        await finishDownload(item.id);
        final destination = (await ManagedFileCopies.existingPath(item.id))!;
        expect(await SessionCleanup.instance.request(), isTrue);
        expect(await File(destination).exists(), isFalse);
        expect(await ModelItem.get(item.id), isNull);
        expect(await (await fixture.db).query('states'), isEmpty);
        expect(await File('${fixture.source.path}/keep.txt').readAsString(),
            'external and backup');
      });
    } finally {
      messenger.setMockMethodCallHandler(
          const MethodChannel('purchases_flutter'), null);
    }
  }, skip: !Platform.isMacOS && !Platform.isIOS);
}
