@TestOn('mac-os')
library;

import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/synced_folder_access.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const channel = MethodChannel('com.jeerovan.fife/channel_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database db;
  late Directory selected;
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    selected = await Directory.systemTemp.createTemp('folder-recovery-');
    await File('${selected.path}/child.txt').writeAsString('survives recovery');
    SessionCleanup.instance.resetForTesting();
    ModelSetting.clear();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => selected.path);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    db = await StorageSqlite.instance.database;
    await db.insert('settings',
        {'id': AppString.deviceHash.string, 'value': 'local-device'});
    await db.insert(
        'items', {'id': 'local-device', 'name': 'device', 'is_folder': 1});
    await db.insert('items', {
      'id': 'root',
      'parent_id': 'local-device',
      'name': 'selected-root',
      'path': '/old-app-container/Documents/selected-root',
      'bookmark': 'old-bookmark',
      'is_folder': 1,
    });
    await db.insert('items', {
      'id': 'child',
      'parent_id': 'root',
      'root_id': 'root',
      'name': 'child.txt',
      'file_hash': 'unchanged-content-hash',
      'is_folder': 0,
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'pickDirectory':
          return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
        case 'startAccessing':
          return selected.path;
        case 'stopAccessing':
          return true;
        default:
          throw StateError('Unexpected storage call');
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await StorageSqlite.instance.close();
    SessionCleanup.instance.resetForTesting();
    ModelSetting.clear();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    await selected.delete(recursive: true);
  });

  Future<void> inDatabase(Future<void> Function(ModelItem root) action) async {
    await action((await ModelItem.get('root'))!);
  }

  Future<List<Map<String, Object?>>> items() async =>
      (await StorageSqlite.instance.executor).query('items', orderBy: 'id');

  void overridePicker(Future<dynamic> Function() pick) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickDirectory') return pick();
      if (call.method == 'startAccessing') return selected.path;
      if (call.method == 'stopAccessing') return true;
      throw StateError('Unexpected storage call');
    });
  }

  test('explicit recovery preserves root and child identity after path changes',
      () async {
    await inDatabase((root) async {
      final childBefore =
          (await items()).singleWhere((row) => row['id'] == 'child');
      final recovered = await SyncedFolderAccess.reselect(root);
      expect(recovered?.id, 'root');
      expect(recovered?.path, selected.path);
      expect(recovered?.bookmark, 'fresh-bookmark');
      expect(recovered?.name, root.name);
      expect((await items()).singleWhere((row) => row['id'] == 'child'),
          childBefore);
      expect(await File(await ModelItem.getPathForItem('child')).readAsString(),
          'survives recovery');
      expect((await items()).length, 3);
      expect(calls.map((c) => c.method),
          ['pickDirectory', 'startAccessing', 'stopAccessing']);
    });
  });

  test('picker cancellation leaves every metadata row unchanged', () async {
    overridePicker(() async => null);
    await inDatabase((root) async {
      final before = await items();
      expect(await SyncedFolderAccess.reselect(root), isNull);
      expect(await items(), before);
      expect(calls.map((c) => c.method), ['pickDirectory']);
    });
  });

  test('readable trash root cannot be reconnected or change vault metadata',
      () async {
    final trash =
        await Directory('${selected.path}/.Trash/root').create(recursive: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickDirectory') {
        return {'path': trash.path, 'bookmark': 'trash-bookmark'};
      }
      if (call.method == 'startAccessing') return trash.path;
      return true;
    });
    await inDatabase((root) async {
      final before = await items();
      expect(await SyncedFolderAccess.isAvailable(root), isFalse);
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(await trash.exists(), isTrue);
      expect(calls.map((c) => c.method), [
        'startAccessing',
        'stopAccessing',
        'pickDirectory',
        'startAccessing',
        'stopAccessing',
      ]);
    });
  });

  test('denied fresh bookmark cannot replace existing access or metadata',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickDirectory') {
        return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
      }
      throw PlatformException(code: 'ACCESS_DENIED');
    });
    await inDatabase((root) async {
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(calls.map((c) => c.method), ['pickDirectory', 'startAccessing']);
    });
  });

  test('missing selected directory releases access and preserves metadata',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickDirectory') {
        return {
          'path': '${selected.path}/missing',
          'bookmark': 'fresh-bookmark'
        };
      }
      if (call.method == 'startAccessing') return '${selected.path}/missing';
      return true;
    });
    await inDatabase((root) async {
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(calls.last.method, 'stopAccessing');
    });
  });

  test('recovery cannot merge a different already-selected root', () async {
    await db.insert('items', {
      'id': 'other-root',
      'parent_id': 'local-device',
      'name': 'other-root',
      'path': selected.path,
      'bookmark': 'other-bookmark',
      'is_folder': 1,
    });
    await inDatabase((root) async {
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'FOLDER_ALREADY_SELECTED')));
      expect(await items(), before);
      expect(calls.last.method, 'stopAccessing');
    });
  });

  test('a competing bookmark update is preserved while picker is open',
      () async {
    await inDatabase((root) async {
      overridePicker(() async {
        await ModelItem.updateBookmark('root', 'competing-bookmark');
        return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
      });
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      final current = (await ModelItem.get('root'))!;
      expect(current.bookmark, 'competing-bookmark');
      expect(current.path, root.path);
      expect((await items()).length, 3);
      expect(calls.last.method, 'stopAccessing');
    });
  });

  test('root archived while picker is open rejects the stale reconnect',
      () async {
    await inDatabase((root) async {
      overridePicker(() async {
        await db.update('items', {'archived_at': 123},
            where: 'id = ?', whereArgs: ['root']);
        return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
      });
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      final current = (await ModelItem.get('root'))!;
      expect(current.archivedAt, 123);
      expect(current.bookmark, 'old-bookmark');
      expect(await db.query('states'), isEmpty);
    });
  });

  test('root removed while picker is open cannot be recreated by completion',
      () async {
    await inDatabase((root) async {
      overridePicker(() async {
        await (await StorageSqlite.instance.executor)
            .delete('items', where: 'id = ?', whereArgs: ['root']);
        return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
      });
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await ModelItem.get('root'), isNull);
      expect(
          (await ModelItem.get('child'))!.fileHash, 'unchanged-content-hash');
      expect(calls.last.method, 'stopAccessing');
    });
  });

  test('changed device session prevents a late picker result from committing',
      () async {
    await inDatabase((root) async {
      final before = await items();
      overridePicker(() async {
        await (await StorageSqlite.instance.executor).update(
            'settings', {'value': 'new-device'},
            where: 'id = ?', whereArgs: [AppString.deviceHash.string]);
        return {'path': selected.path, 'bookmark': 'fresh-bookmark'};
      });
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(calls.last.method, 'stopAccessing');
    });
  });

  test('another device root cannot start permission recovery', () async {
    await inDatabase((root) async {
      root.parentId = 'other-device';
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(calls, isEmpty);
    });
  });

  test('available root balances access without opening the picker', () async {
    await inDatabase((root) async {
      expect(await SyncedFolderAccess.isAvailable(root), isTrue);
      expect(calls.map((c) => c.method), ['startAccessing', 'stopAccessing']);
    });
  });

  test('unresolvable root offers recovery without acquiring a path fallback',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'RESOLVE_ERROR');
    });
    await inDatabase((root) async {
      final before = await items();
      expect(await SyncedFolderAccess.isAvailable(root), isFalse);
      expect(await items(), before);
      expect(calls.map((c) => c.method), ['startAccessing']);
    });
  });

  test('unavailable directory releases access before offering recovery',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'startAccessing'
          ? '${selected.path}/missing'
          : true;
    });
    await inDatabase((root) async {
      expect(await SyncedFolderAccess.isAvailable(root), isFalse);
      expect(calls.map((c) => c.method), ['startAccessing', 'stopAccessing']);
    });
  });

  test('invalid picker bookmark cannot replace an existing root', () async {
    overridePicker(
        () async => {'path': selected.path, 'bookmark': 'sandboxed'});
    await inDatabase((root) async {
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(calls.map((c) => c.method), ['pickDirectory']);
    });
  });

  test('recovery directory cannot become the new source and be deleted',
      () async {
    final copy =
        await Directory('${selected.path}/FiFe/.downloads/root/version/source')
            .create(recursive: true);
    final original =
        await File('${copy.path}/child.txt').writeAsString('recovered');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickDirectory') {
        return {'path': copy.path, 'bookmark': 'fresh-bookmark'};
      }
      if (call.method == 'startAccessing') return copy.path;
      return true;
    });
    await inDatabase((root) async {
      final before = await items();
      await expectLater(
          SyncedFolderAccess.reselect(root), throwsA(isA<PlatformException>()));
      expect(await items(), before);
      expect(await original.readAsString(), 'recovered');
    });
  });
}
