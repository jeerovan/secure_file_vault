import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  const storage = MethodChannel('com.jeerovan.fife/channel_storage');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // BLAKE2b-256 of empty bytes with the fixed test key 0..31.
  const emptyHash = 'TlHnqRP8gBN9pSiA_syhdb-B4RfVxoEm3Cd0AzUX6g0';
  late Directory directory;
  late Database db;
  late List<String> accessCalls;

  setUp(() async {
    SessionCleanup.instance.resetForTesting();
    directory = await Directory.systemTemp.createTemp('fife-empty-download-');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StorageSqlite.instance.initTables(db);
    await db.insert('settings',
        {'id': AppString.deviceHash.string, 'value': 'local-device'});
    await db.insert(
        'items', {'id': 'local-device', 'name': 'device', 'is_folder': 1});
    await db.insert('items', {
      'id': 'fixture-root',
      'parent_id': 'local-device',
      'name': 'fixture-root',
      'path': '/old/fixture-root',
      'is_folder': 1,
      'bookmark': 'test-bookmark',
    });
    await db.insert('items', {
      'id': 'fixture-file',
      'parent_id': 'fixture-root',
      'root_id': 'fixture-root',
      'name': 'empty.txt',
      'is_folder': 0,
      'file_hash': emptyHash,
      'size': 0,
    });
    await db.insert('files', {'id': emptyHash, 'parts': 0, 'uploaded_at': 1});
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(
        secure,
        (call) async => call.arguments['key'] == AppString.fileHashKey.string
            ? base64Encode(List<int>.generate(32, (i) => i))
            : null);
    accessCalls = [];
    messenger.setMockMethodCallHandler(storage, (call) async {
      accessCalls.add(call.method);
      return call.method == 'startAccessing'
          ? '${directory.path}/restored'
          : true;
    });
  });

  tearDown(() async {
    SessionCleanup.instance.resetForTesting();
    for (final channel in [storage, secure, paths]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> download() async {
    final task = await ModelItemTask.fromMap(
        {'id': 'fixture-file', 'task': ItemTask.download.value});
    await task.insert();
    await TaskManager().checkInitDownload(task);
  }

  void expectBookmarkAccessReleased() {
    // Publication revalidates its destination while the original lease is
    // held. Nested access is valid, but every acquired lease must be released.
    expect(accessCalls, contains('startAccessing'));
    var active = 0;
    for (final method in accessCalls) {
      expect(method, isIn(['startAccessing', 'stopAccessing']));
      active += method == 'startAccessing' ? 1 : -1;
      expect(active, greaterThanOrEqualTo(0));
    }
    expect(active, 0,
        reason: 'A completed/blocked download must not leak access');
  }

  test('zero-part empty file restores verified bytes and completes its task',
      () async {
    await StorageSqlite.runInDatabaseTransaction(db, () async {
      await download();
      expect(await ModelItemTask.get('fixture-file'), isNull);
      final restored = File('${directory.path}/restored/empty.txt');
      expect(await restored.exists(), isTrue);
      expect(await restored.readAsBytes(), isEmpty);
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expectBookmarkAccessReleased();
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('zero parts cannot restore a nonempty file or a negative manifest',
      () async {
    for (final values in [
      (parts: 0, size: 1),
      (parts: -1, size: 0),
    ]) {
      await db.update('items', {'size': values.size},
          where: 'id = ?', whereArgs: ['fixture-file']);
      await db.update('files', {'parts': values.parts});
      await StorageSqlite.runInDatabaseTransaction(db, () async {
        await download();
        final task = await ModelItemTask.get('fixture-file');
        expect(task?.state, TransferTaskState.blocked);
        expect(task?.lastError, 'invalid_part_count');
        expect(await File('${directory.path}/restored/empty.txt').exists(),
            isFalse);
        expect(await ModelItem.get('fixture-file'), isNotNull);
        await task!.delete();
      });
    }
    expect(accessCalls, isEmpty);
  });

  test('empty file hash mismatch never publishes or completes', () async {
    await db.update('items', {'file_hash': 'wrong-test-hash'},
        where: 'id = ?', whereArgs: ['fixture-file']);
    await db.update('files', {'id': 'wrong-test-hash'});
    await StorageSqlite.runInDatabaseTransaction(db, () async {
      await download();
      final task = await ModelItemTask.get('fixture-file');
      expect(task?.state, TransferTaskState.blocked);
      expect(task?.lastError, 'download_integrity_mismatch');
      expect(
          await File('${directory.path}/restored/empty.txt').exists(), isFalse);
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expect(accessCalls, isEmpty);
    });
  });

  test('empty download preserves conflicting destination bytes', () async {
    final destination = File('${directory.path}/restored/empty.txt');
    await destination.parent.create(recursive: true);
    await destination.writeAsString('keep existing bytes');
    await StorageSqlite.runInDatabaseTransaction(db, () async {
      await download();
      final task = await ModelItemTask.get('fixture-file');
      expect(task?.state, TransferTaskState.blocked);
      expect(task?.lastError, 'destination_conflict');
      expect(await destination.readAsString(), 'keep existing bytes');
      expectBookmarkAccessReleased();
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('empty download cannot publish through denied bookmark access',
      () async {
    messenger.setMockMethodCallHandler(storage, (_) async {
      throw PlatformException(code: 'ACCESS_DENIED');
    });
    await StorageSqlite.runInDatabaseTransaction(db, () async {
      await expectLater(
          download(),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'ACCESS_DENIED')));
      expect(await ModelItemTask.get('fixture-file'), isNotNull);
      expect(await ModelItem.get('fixture-file'), isNotNull);
      expect(
          await File('${directory.path}/restored/empty.txt').exists(), isFalse);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);
}
