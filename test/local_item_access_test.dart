import 'dart:io';
import 'dart:async';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const channel = MethodChannel('com.jeerovan.fife/channel_storage');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> withFixture(Future<void> Function() operation,
      {String bookmark = 'test-bookmark', String name = 'absent.txt'}) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await StorageSqlite.instance.initTables(db);
      await db.insert('settings',
          {'id': AppString.deviceHash.string, 'value': 'local-device'});
      await db.insert(
          'items', {'id': 'local-device', 'name': 'device', 'is_folder': 1});
      await db.insert('items', {
        'id': 'fixture-root',
        'parent_id': 'local-device',
        'name': 'fixture-root',
        'path': '/external/fixture-root',
        'is_folder': 1,
        'bookmark': bookmark,
      });
      await db.insert('items', {
        'id': 'fixture-file',
        'parent_id': 'fixture-root',
        'root_id': 'fixture-root',
        'name': name,
        'is_folder': 0,
        'file_hash': 'test-hash',
      });
      await StorageSqlite.runInDatabaseTransaction(db, operation);
    } finally {
      await db.close();
    }
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(secure, null);
  });

  test('denied upload source retains file metadata and queued task', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await StorageSqlite.instance.initTables(db);
    await db.insert('settings',
        {'id': AppString.deviceHash.string, 'value': 'local-device'});
    await db.insert(
        'items', {'id': 'local-device', 'name': 'device', 'is_folder': 1});
    await db.insert('items', {
      'id': 'fixture-root',
      'parent_id': 'local-device',
      'name': 'fixture-root',
      'path': '/external/fixture-root',
      'is_folder': 1,
      'bookmark': 'test-bookmark',
    });
    await db.insert('items', {
      'id': 'fixture-file',
      'parent_id': 'fixture-root',
      'root_id': 'fixture-root',
      'name': 'absent.txt',
      'is_folder': 0,
      'file_hash': 'test-hash',
    });
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'ACCESS_DENIED');
    });

    await StorageSqlite.runInDatabaseTransaction(db, () async {
      final task = await ModelItemTask.fromMap(
          {'id': 'fixture-file', 'task': ItemTask.upload.value});
      await task.insert();
      await expectLater(
          TaskManager().checkInitUpload(task),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'ACCESS_DENIED')));
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expect(await ModelItemTask.get('fixture-file'), isNotNull);
      expect(calls.map((call) => call.method), ['startAccessing']);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('access remains held across awaits and uses the moved root', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'startAccessing' ? '/resolved/moved-root' : true;
    });
    await withFixture(() async {
      final entered = Completer<void>();
      final resume = Completer<void>();
      final work = LocalItemAccess.withAccess('fixture-file', (itemPath) async {
        expect(itemPath, '/resolved/moved-root/absent.txt');
        entered.complete();
        await resume.future;
        expect(calls, ['startAccessing']);
        return 'completed';
      });
      await entered.future;
      expect(calls, ['startAccessing']);
      resume.complete();
      expect(await work, 'completed');
      expect(calls, ['startAccessing', 'stopAccessing']);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('trash bookmark never enters a file read or publication operation',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'startAccessing' ? '/provider/.Trash/root' : true;
    });
    await withFixture(() async {
      var entered = false;
      await expectLater(
          LocalItemAccess.withAccess('fixture-file', (_) async {
            entered = true;
          }),
          throwsA(isA<PlatformException>()));
      expect(entered, isFalse);
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expect(calls, ['startAccessing', 'stopAccessing']);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('failed file operation releases the resolved root exactly once',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'startAccessing' ? '/resolved/moved-root' : true;
    });
    await withFixture(() async {
      await expectLater(
          LocalItemAccess.withAccess<void>('fixture-file', (_) async {
            throw const FileSystemException('test interruption');
          }),
          throwsA(isA<FileSystemException>()));
      expect(calls.map((call) => call.method),
          ['startAccessing', 'stopAccessing']);
      expect(calls.last.arguments, {'path': '/resolved/moved-root'});
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('explicit release is idempotent', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'startAccessing' ? '/resolved/root' : true;
    });
    await withFixture(() async {
      final access = await LocalItemAccess.acquire('fixture-file');
      await access.release();
      await access.release();
      expect(calls, ['startAccessing', 'stopAccessing']);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('null or empty access never performs file work', () async {
    for (final resolved in [null, '']) {
      messenger.setMockMethodCallHandler(channel, (_) async => resolved);
      await withFixture(() async {
        await expectLater(
            LocalItemAccess.withAccess<void>('fixture-file', (_) async {
              fail('File work must not run without access');
            }),
            throwsA(isA<PlatformException>()
                .having((e) => e.code, 'code', 'ACCESS_DENIED')));
      });
    }
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('legacy bookmark never falls back to a persisted path', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Invalid bookmark must not reach the native channel');
    });
    await withFixture(() async {
      await expectLater(
          LocalItemAccess.acquire('fixture-file'),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'FOLDER_UNAVAILABLE')));
    }, bookmark: 'sandboxed');
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('child path cannot escape the selected root', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Escaping path must not acquire access');
    });
    await withFixture(() async {
      await expectLater(
          LocalItemAccess.acquire('fixture-file'),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'FOLDER_UNAVAILABLE')));
    }, name: '../outside.txt');
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('a file permission failure is not mistaken for source deletion',
      () async {
    final folder = await Directory.systemTemp.createTemp('fife-access-denied-');
    await File('${folder.path}/absent.txt').writeAsString('fixture');
    final locked = await Process.run('chmod', ['000', folder.path]);
    expect(locked.exitCode, 0);
    addTearDown(() async {
      await Process.run('chmod', ['700', folder.path]);
      await folder.delete(recursive: true);
    });
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'startAccessing' ? folder.path : true;
    });
    await withFixture(() async {
      final task = await ModelItemTask.fromMap(
          {'id': 'fixture-file', 'task': ItemTask.upload.value});
      await task.insert();
      await expectLater(TaskManager().checkInitUpload(task),
          throwsA(isA<FileSystemException>()));
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expect(await ModelItemTask.get('fixture-file'), isNotNull);
      expect(calls, ['startAccessing', 'stopAccessing']);
    });
  }, skip: !Platform.isMacOS);
}
