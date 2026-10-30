import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sodium/sodium_sumo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'temporary_directory.dart';
import 'native_privacy_fixture.dart';

/// Real files, SQLite and libsodium; only OS directory/key storage is replaced.
class SyncFixture {
  static const rootId = 'fixture-root';
  static const deviceId = 'fixture-device';
  static const paths = MethodChannel('plugins.flutter.io/path_provider');
  static const secure =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  static const access = MethodChannel('com.jeerovan.fife/channel_storage');

  final Directory directory;
  final Directory source;
  final SodiumSumo sodium;
  final Map<String, String> secrets = {
    AppString.masterKey.string:
        base64Encode(List<int>.generate(32, (i) => 31 - i)),
    AppString.fileHashKey.string:
        base64Encode(List<int>.generate(32, (i) => i)),
    AppString.jwtToken.string: 'unit-test-token',
  };
  final List<String> accessCalls = [];
  bool accessAllowed = true;
  Future<void> Function(String key)? beforeRead;
  Future<void> Function(String key, String? value)? afterRead;
  Future<void> Function(String key, String value)? beforeWrite;
  Future<void> Function(String key)? beforeDelete;
  final nativePrivacy = NativePrivacyFixture();

  SyncFixture._(this.directory, this.source, this.sodium);

  Future<Database> get db => StorageSqlite.instance.database;
  Future<ModelItem> get root async => (await ModelItem.get(rootId))!;

  static Future<SyncFixture> create() async {
    SessionCleanup.instance.resetForTesting();
    final directory = await Directory.systemTemp.createTemp('fife-sync-');
    final source = await Directory('${directory.path}/source').create();
    final fixture =
        SyncFixture._(directory, source, await SodiumSumoInit.init());
    fixture.nativePrivacy.install();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(secure, (call) async {
      final key = call.arguments?['key'] as String?;
      if (call.method == 'read') {
        await fixture.beforeRead?.call(key!);
        final value = fixture.secrets[key];
        await fixture.afterRead?.call(key!, value);
        return value;
      }
      if (call.method == 'readAll') {
        return Map<String, String>.of(fixture.secrets);
      }
      if (call.method == 'write') {
        await fixture.beforeWrite
            ?.call(key!, call.arguments['value'] as String);
        fixture.secrets[key!] = call.arguments['value'] as String;
      } else if (call.method == 'delete') {
        await fixture.beforeDelete?.call(key!);
        fixture.secrets.remove(key);
      } else if (call.method == 'deleteAll') {
        fixture.secrets.clear();
      } else if (call.method == 'containsKey') {
        return fixture.secrets.containsKey(key);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(access, (call) async {
      fixture.accessCalls.add(call.method);
      if (call.method == 'startAccessing') {
        return fixture.accessAllowed ? source.path : null;
      }
      return true;
    });
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final db = await fixture.db;
    for (final entry in {
      AppString.deviceHash.string: deviceId,
      AppString.deviceUuid.string: 'fixture-device-uuid',
    }.entries) {
      await db.insert('settings', {'id': entry.key, 'value': entry.value});
    }
    ModelSetting.settingJson = {};
    await db.insert(
        'profiles', {'id': 'fixture-user', 'email': 'fixture@example.test'});
    await db
        .insert('items', {'id': deviceId, 'name': deviceId, 'is_folder': 1});
    await db.insert('items', {
      'id': rootId,
      'parent_id': deviceId,
      'name': 'source',
      'path': source.path,
      'bookmark': 'fixture-bookmark',
      'is_folder': 1,
    });
    return fixture;
  }

  Future<File> write(String relativePath, List<int> bytes) async {
    final file = File('${source.path}/$relativePath');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<File> text(String relativePath, String value) =>
      write(relativePath, utf8.encode(value));

  Future<ReconciliationResult> scan() async =>
      ReconciliationService(sodium).reconcile(await root);

  Future<List<ModelItem>> items() async =>
      Future.wait((await (await db).query('items',
              where: 'root_id = ?', whereArgs: [rootId], orderBy: 'id'))
          .map(ModelItem.fromMap));

  Future<ModelItem> item(String relativePath) async {
    for (final item in await items()) {
      if (path.equals(await ModelItem.getPathForItem(item.id),
          path.join(source.path, relativePath))) {
        return item;
      }
    }
    throw StateError('Missing fixture item: $relativePath');
  }

  Future<void> markUploaded() async {
    final database = await db;
    await database.update('files', {'uploaded_at': 1});
    await database.delete('item_tasks');
    await database.delete('changes');
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final database = await db;
    return {
      for (final table in ['items', 'files', 'parts', 'item_tasks', 'changes'])
        table: await database.query(table, orderBy: 'id'),
    };
  }

  Future<void> dispose() async {
    SyncUtils().stopAutoSync();
    await TaskManager.stopBackgroundWakes();
    AppHttpClients.closeAll();
    // AppSetupState can still be unwinding a real session-marker probe after
    // its widget is disposed. Windows cannot delete those open SQLite mutexes.
    await SessionCleanup.instance.currentOperation
        ?.timeout(const Duration(seconds: 5));
    await StorageSqlite.instance.close();
    SessionCleanup.instance.resetForTesting();
    ModelSetting.clear();
    nativePrivacy.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [paths, secure, access]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await deleteTestDirectory(directory);
  }
}
