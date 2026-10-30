import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/managed_file_copies.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/synced_folder_access.dart';
import 'package:file_vault_bb/ui/item_selection_actions.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

class _Picker extends FilePickerPlatform {
  String? selected;
  String? initial;
  Future<void> Function()? beforeReturn;
  @override
  Future<String?> getDirectoryPath(
      {String? dialogTitle,
      String? initialDirectory,
      AndroidOptions androidOptions = const AndroidOptions(),
      WindowsOptions windowsOptions = const WindowsOptions(),
      LinuxOptions linuxOptions = const LinuxOptions(),
      WebOptions webOptions = const WebOptions()}) async {
    initial = initialDirectory;
    await beforeReturn?.call();
    return selected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Windows disconnected source', () {
    late SyncFixture fixture;
    late FilePickerPlatform originalPicker;
    late _Picker picker;
    setUp(() async {
      fixture = await SyncFixture.create();
      originalPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker = _Picker();
    });
    tearDown(() async {
      FilePickerPlatform.instance = originalPicker;
      await fixture.dispose();
    });

    Future<ModelItem> upload(String name, String content) async {
      await fixture.text(name, content);
      expect((await fixture.scan()).status, ReconciliationStatus.completed);
      final item = await fixture.item(name);
      for (var n = 0; n < 8; n++) {
        final task = await ModelItemTask.get(item.id);
        if (task == null) break;
        await TaskManager().checkInitUpload(task);
      }
      expect(await ModelItemTask.get(item.id), isNull);
      expect((await ModelFile.get(item.fileHash!))!.uploadedAt, greaterThan(0));
      return item;
    }

    Future<Directory> disconnect() =>
        fixture.source.rename('${fixture.source.path}-moved');
    Future<Set<ItemSelectionAction>> actions(ModelItem item) async {
      final selection = ValueNotifier<Set<ModelItem>>({item});
      final policy = ItemSelectionActions(selection);
      try {
        await policy.refresh();
        return ItemSelectionAction.values.where(policy.allows).toSet();
      } finally {
        policy.dispose();
        selection.dispose();
      }
    }

    Future<bool> act(ModelItem item, ItemSelectionAction action) async {
      final selection = ValueNotifier<Set<ModelItem>>({item});
      final policy = ItemSelectionActions(selection);
      try {
        return await policy.perform(action);
      } finally {
        policy.dispose();
        selection.dispose();
      }
    }

    Future<void> download(String id) async {
      for (var n = 0; n < 8; n++) {
        final task = await ModelItemTask.get(id);
        if (task == null) break;
        expect(task.state, isNot(TransferTaskState.blocked));
        await TaskManager().checkInitDownload(task);
      }
      expect(await ModelItemTask.get(id), isNull);
    }

    test(
        'available source needs no Apple bookmark; missing root cannot be source access',
        () async {
      final root = await fixture.root;
      root.bookmark = 'sandboxed';
      await root.update(['bookmark']);
      expect(await SyncedFolderAccess.isAvailable(root), isTrue);
      final moved = await disconnect();
      expect(await SyncedFolderAccess.isAvailable(root), isFalse);
      await expectLater(
          LocalItemAccess.acquire(root.id), throwsA(isA<PlatformException>()));
      expect((await fixture.scan()).status, ReconciliationStatus.unavailable);
      await moved.rename(fixture.source.path);
      expect(await SyncedFolderAccess.isAvailable(root), isTrue);
      expect(fixture.accessCalls, isEmpty);
    });

    test('missing root and nested items expose only safe recovery actions',
        () async {
      await TransferApi().run(() async {
        final file = await upload('nested/file.txt', 'original');
        final folder = await fixture.item('nested');
        await disconnect();
        expect(await actions(await fixture.root), {
          ItemSelectionAction.reconnect,
          ItemSelectionAction.download,
          ItemSelectionAction.archive
        });
        expect(await actions(folder),
            {ItemSelectionAction.download, ItemSelectionAction.archive});
        expect(await actions(file), {ItemSelectionAction.download});
      });
    });

    test(
        'normal file Download survives restart and never recreates the missing source',
        () async {
      await TransferApi().run(() async {
        final file = await upload('nested/deep/file.txt', 'preserved original');
        final moved = await disconnect();
        expect(await act(file, ItemSelectionAction.download), isTrue);
        final destination = (await ManagedFileCopies.downloadPath(file.id))!;
        expect(p.split(destination).skip(p.split(destination).length - 4),
            ['source', 'nested', 'deep', 'file.txt']);
        expect(p.isWithin(await ModelItem.getPathForItem('fife'), destination),
            isTrue);
        await StorageSqlite.instance.close();
        ModelSetting.clear();
        await StorageSqlite.initialize(ExecutionMode.mainApp);
        await download(file.id);
        expect(await File(destination).readAsString(), 'preserved original');
        expect(await fixture.source.exists(), isFalse);
        expect(
            await File(p.join(moved.path, 'nested/deep/file.txt'))
                .readAsString(),
            'preserved original');
        expect(
            await LocalItemAccess.withReadableAccess(
                file.id, (path) => File(path).readAsString()),
            'preserved original');
        expect(await actions(file), isEmpty,
            reason: 'Already recovered files must not queue another download');
      });
    });

    test('reconnect keeps metadata identity and deletes all old managed copies',
        () async {
      await TransferApi().run(() async {
        final file = await upload('nested/file.txt', 'backup');
        final moved = await disconnect();
        expect(await act(await fixture.root, ItemSelectionAction.download),
            isTrue);
        await download(file.id);
        final copy = (await ManagedFileCopies.existingPath(file.id))!;
        final copies =
            Directory(p.dirname(p.dirname(p.dirname(p.dirname(copy)))));
        await File(p.join(copies.path, 'untracked.txt'))
            .writeAsString('old copy');
        await File(p.join(moved.path, 'nested/file.txt'))
            .writeAsString('different current source');
        picker.selected = moved.path;
        final root = await fixture.root;
        final recovered = await SyncedFolderAccess.reselect(root);
        expect(recovered?.id, root.id);
        expect(recovered?.path, moved.path);
        expect(recovered?.bookmark, 'sandboxed');
        expect(picker.initial, isNull,
            reason: 'Do not open a picker on an unavailable drive');
        expect(await copies.exists(), isFalse);
        expect((await ModelItem.get(file.id))!.fileHash, file.fileHash);
        expect(
            await File(await ModelItem.getPathForItem(file.id)).readAsString(),
            'different current source');
      });
    });

    test(
        'cancel, missing destination, duplicate path and stale picker preserve the old root',
        () async {
      final root = await fixture.root;
      final moved = await disconnect();
      final before = await fixture.snapshot();
      expect(await SyncedFolderAccess.reselect(root), isNull);
      expect(await fixture.snapshot(), before);
      picker.selected = p.join(moved.path, 'missing');
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await fixture.snapshot(), before);
      await (await fixture.db).insert('items', {
        'id': 'other-root',
        'parent_id': SyncFixture.deviceId,
        'name': 'other',
        'path': moved.path,
        'is_folder': 1
      });
      picker.selected = moved.path.toUpperCase();
      await expectLater(
          SyncedFolderAccess.reselect(root),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'FOLDER_ALREADY_SELECTED')));
      await (await fixture.db)
          .delete('items', where: 'id = ?', whereArgs: ['other-root']);
      picker.selected = moved.path;
      picker.beforeReturn =
          () => ModelItem.updateBookmark(root.id, 'changed-while-picking');
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect((await fixture.root).path, root.path);
      expect((await fixture.root).bookmark, 'changed-while-picking');
    });

    test(
        'reconnect rejects managed copies and invalidates an in-flight download',
        () async {
      final entered = Completer<void>(), release = Completer<void>();
      final api = TransferApi()
        ..beforeDownloadResponse = () async {
          entered.complete();
          await release.future;
        };
      await api.run(() async {
        final file = await upload('nested/late.txt', 'backup');
        final moved = await disconnect();
        expect(await act(file, ItemSelectionAction.download), isTrue);
        final destination = (await ManagedFileCopies.downloadPath(file.id))!;
        await Directory(p.dirname(destination)).create(recursive: true);
        picker.selected = p.dirname(destination);
        final root = await fixture.root;
        await expectLater(SyncedFolderAccess.reselect(root),
            throwsA(isA<PlatformException>()));
        expect((await fixture.root).path, root.path);
        expect(await ModelItemTask.get(file.id), isNotNull);
        final pending = TaskManager()
            .checkInitDownload((await ModelItemTask.get(file.id))!);
        try {
          await entered.future.timeout(const Duration(seconds: 10));
          await File(p.join(moved.path, 'nested/late.txt'))
              .writeAsString('new original');
          picker.selected = moved.path;
          expect((await SyncedFolderAccess.reselect(root))?.id, root.id);
          release.complete();
          await pending.timeout(const Duration(seconds: 10));
          expect(await File(destination).exists(), isFalse);
          expect(await ModelItemTask.get(file.id), isNull);
          expect(
              await File(p.join(moved.path, 'nested/late.txt')).readAsString(),
              'new original');
        } finally {
          if (!release.isCompleted) release.complete();
          await pending;
        }
      });
    });

    test('root removed while the picker is open cannot be recreated', () async {
      final root = await fixture.root;
      final moved = await disconnect();
      picker.selected = moved.path;
      picker.beforeReturn = () async {
        await (await fixture.db)
            .delete('items', where: 'id = ?', whereArgs: [root.id]);
      };
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await ModelItem.get(root.id), isNull);
      expect(await moved.exists(), isTrue);
    });

    test(
        'archiving nested recovery cancels late publication and preserves siblings and originals',
        () async {
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      final api = TransferApi()
        ..beforeDownloadResponse = () async {
          if (first) {
            first = false;
            entered.complete();
            await release.future;
          }
        };
      await api.run(() async {
        final child = await upload('nested/late.txt', 'external original');
        final sibling = await upload('sibling.txt', 'sibling');
        final folder = await fixture.item('nested');
        final moved = await disconnect();
        expect(await act(await fixture.root, ItemSelectionAction.download),
            isTrue);
        final childCopy = (await ManagedFileCopies.downloadPath(child.id))!;
        final pending = TaskManager()
            .checkInitDownload((await ModelItemTask.get(child.id))!);
        try {
          await entered.future.timeout(const Duration(seconds: 10));
          expect(await act(folder, ItemSelectionAction.archive), isTrue);
          expect(await ModelItemTask.get(child.id), isNull);
          expect(await ModelItemTask.get(sibling.id), isNotNull);
          release.complete();
          await pending.timeout(const Duration(seconds: 10));
          await download(sibling.id);
          expect(await File(childCopy).exists(), isFalse);
          expect(
              await File((await ManagedFileCopies.existingPath(sibling.id))!)
                  .readAsString(),
              'sibling');
          expect(
              await File(p.join(moved.path, 'nested/late.txt')).readAsString(),
              'external original');
          expect(await act(await fixture.root, ItemSelectionAction.archive),
              isTrue);
          expect(await ManagedFileCopies.existingPath(sibling.id), isNull);
          expect(await moved.exists(), isTrue);
        } finally {
          if (!release.isCompleted) release.complete();
          await pending;
        }
      });
    });
  }, skip: !Platform.isWindows);
}
