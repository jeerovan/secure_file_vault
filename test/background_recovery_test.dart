import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const storage = MethodChannel('com.jeerovan.fife/channel_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late List<String> access;
  SyncBudget? cancelOnHash;
  SyncBudget? cancelOnAccess;
  const emptyHash = 'TlHnqRP8gBN9pSiA_syhdb-B4RfVxoEm3Cd0AzUX6g0';

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('fife-background-recovery-');
    access = [];
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(secure, (call) async {
      if (call.arguments['key'] == AppString.fileHashKey.string) {
        cancelOnHash?.cancel('expiration');
        return base64Encode(List<int>.generate(32, (i) => i));
      }
      return null;
    });
    messenger.setMockMethodCallHandler(storage, (call) async {
      access.add(call.method);
      if (call.method == 'startAccessing') {
        cancelOnAccess?.cancel('expiration');
        return directory.path;
      }
      return null;
    });
    await StorageSqlite.initialize(ExecutionMode.backgroundWorker);
    final db = await StorageSqlite.instance.database;
    await db.insert(
        'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
    await db.insert('items',
        {'id': 'device', 'is_folder': 1, 'name': 'device', 'archived_at': 0});
    await db.insert('items', {
      'id': 'root',
      'is_folder': 1,
      'name': 'root',
      'parent_id': 'device',
      'path': directory.path,
      'bookmark': 'fixture-bookmark',
      'archived_at': 0,
    });
    await db.insert('items', {
      'id': 'file',
      'name': 'empty.txt',
      'parent_id': 'root',
      'root_id': 'root',
      'file_hash': emptyHash,
      'size': 0,
      'archived_at': 0,
      'scan_state': 1,
    });
    await db.insert('files', {'id': emptyHash, 'parts': 0, 'uploaded_at': 1});
    await db.update('items', {'updated_at': 42});
  });

  tearDown(() async {
    cancelOnHash?.dispose();
    cancelOnAccess?.dispose();
    cancelOnHash = null;
    cancelOnAccess = null;
    await TaskManager.stopBackgroundWakes();
    await StorageSqlite.instance.close();
    for (final channel in [paths, secure, storage]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await directory.delete(recursive: true);
  });

  test(
      'expiration while hashing releases access and preserves the last complete scan',
      () async {
    await File('${directory.path}/empty.txt')
        .writeAsString('editor replacement');
    final root = (await ModelItem.get('root'))!;
    final before = (await ModelItem.get('file'))!.toMap();
    final budget =
        SyncBudget(deadline: DateTime.now().add(const Duration(seconds: 20)));
    cancelOnHash = budget;
    final sodium = await SodiumSumoInit.init();
    final result =
        await budget.run(() => ReconciliationService(sodium).reconcile(root));
    expect(result.status, ReconciliationStatus.partial);
    expect((await ModelItem.get('file'))!.toMap(), before);
    expect(
        await StorageSqlite.instance.getAll(Tables.itemTasks.string), isEmpty);
    expect(await StorageSqlite.instance.getAll(Tables.states.string), isEmpty);
    expect(access, ['startAccessing', 'stopAccessing']);
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('readable trashed root is unavailable without changing backup or queue',
      () async {
    final trash = await Directory('${directory.path}/.Trash/root')
        .create(recursive: true);
    await File('${trash.path}/new.txt').writeAsString('must not upload');
    messenger.setMockMethodCallHandler(storage, (call) async {
      access.add(call.method);
      return call.method == 'startAccessing' ? trash.path : null;
    });
    final db = await StorageSqlite.instance.database;
    final before = await db.query('items', orderBy: 'id');
    final filesBefore = await db.query('files');
    final task = await ModelItemTask.fromMap(
        {'id': 'file', 'task': ItemTask.upload.value});
    await task.insert();
    final tasksBefore = await db.query(Tables.itemTasks.string);
    final result = await ReconciliationService(await SodiumSumoInit.init())
        .reconcile((await ModelItem.get('root'))!);
    expect(result.status, ReconciliationStatus.unavailable);
    expect(result.scannedItems, 0);
    expect(await db.query('items', orderBy: 'id'), before);
    expect(await db.query('files'), filesBefore);
    expect(await db.query(Tables.itemTasks.string), tasksBefore);
    expect(await db.query(Tables.states.string), isEmpty);
    expect(access, ['startAccessing', 'stopAccessing']);
    expect(
        await File('${trash.path}/new.txt').readAsString(), 'must not upload');
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test(
      'expiration before publication keeps download pending without consuming retry attempts',
      () async {
    final task = await ModelItemTask.fromMap({
      'id': 'file',
      'task': ItemTask.download.value,
      'attempt_count': 5,
    });
    await task.insert();
    final budget =
        SyncBudget(deadline: DateTime.now().add(const Duration(seconds: 20)));
    cancelOnAccess = budget;
    await budget.run(() => TaskManager().dispatchTask('file'));
    final pending = (await ModelItemTask.get('file'))!;
    expect(pending.state, TransferTaskState.pending);
    expect(pending.attemptCount, 5);
    expect(pending.nextAttemptAt, 0);
    expect(pending.lastError, 'background_expiration');
    expect(await File('${directory.path}/empty.txt').exists(), isFalse);
    expect(await ModelItem.get('file'), isNotNull);
    expect(await StorageSqlite.instance.getAll(Tables.states.string), isEmpty);
    expect(access, ['startAccessing', 'stopAccessing']);

    cancelOnAccess = null;
    budget.dispose();
    await TaskManager().checkInitDownload(pending);
    expect(await ModelItemTask.get('file'), isNull);
    expect(await File('${directory.path}/empty.txt').readAsBytes(), isEmpty);
    expect(access, [
      'startAccessing',
      'stopAccessing',
      'startAccessing',
      'startAccessing',
      'stopAccessing',
      'stopAccessing',
    ]); // Publication revalidates its destination while the first lease is held.
  }, skip: !Platform.isMacOS && !Platform.isIOS);
}
