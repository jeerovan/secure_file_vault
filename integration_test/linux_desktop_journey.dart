import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/storage/managed_file_copies.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sodium/sodium_sumo.dart';

import '../test/support/transfer_api.dart';
import 'support/native_http_overrides.dart';

/// Seeds a backed-up synthetic source before launching the real application.
/// Missing-folder detection, selection, downloads, native picker and archive
/// are triggered only through the actual UI. No real account/cloud is accessed.
Future<void> main() async {
  final runtime = Platform.environment['FIFE_LINUX_TEST_ROOT'];
  if (!Platform.isLinux ||
      runtime == null ||
      !RegExp(r'runtime-[a-f0-9]{16}$').hasMatch(runtime) ||
      !File(path.join(runtime, 'synthetic-fixture.marker')).existsSync() ||
      Platform.environment['XDG_DATA_HOME'] != path.join(runtime, 'xdg') ||
      !AppEnv.localTestingBuild ||
      AppEnv.localTestAuthToken.isEmpty ||
      AppEnv.effectiveApiBaseUrl != 'https://backend.example.test') {
    throw StateError('Explicit isolated Linux fixture required');
  }
  // The Linux plugin namespaces keyring entries with its compiled application
  // ID. Reject a product binary before any fixture keys are written.
  final plugin = File(path.join(path.dirname(Platform.resolvedExecutable),
      'lib', 'libflutter_secure_storage_linux_plugin.so'));
  if (!latin1
      .decode(await plugin.readAsBytes())
      .contains('com.jeerovan.fife.NativeTest\u0000')) {
    throw StateError('Isolated native keyring identity required');
  }
  final api = _RecoveryApi();
  HttpOverrides.global = NativeFixtureHttpOverrides(api.handle, allowedHosts: {
    'backend.example.test',
    'bucket.example.test',
    '127.0.0.1',
    'one.one.one.one',
    'icanhazip.com',
    'ajax.googleapis.com',
    'captive.apple.com'
  });
  await api.run(() async {
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.ensureSemantics();
    PathProviderPlatform.instance = _Paths(runtime);
    for (final name in ['roaming', 'support', 'documents', 'temp']) {
      await Directory(path.join(runtime, name)).create(recursive: true);
    }
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final bucket = File(path.join(runtime, 'synthetic-bucket.json'));
    const rootId = 'linux-recovery-root', deviceId = 'linux-recovery-device';
    final source = Directory(path.join(runtime, 'Recovery source'));
    final moved = Directory(path.join(runtime, 'Reconnected source'));
    final db = await StorageSqlite.instance.executor;
    if (await ModelProfile.get() == null) {
      await (await ModelProfile.fromMap(
              {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
          .insert();
      for (final entry in {
        AppString.signedIn: 'yes',
        AppString.onboarding: 'yes',
        AppString.localTesting: 'yes',
        AppString.deviceUuid: 'linux-recovery-fixture',
        AppString.deviceHash: deviceId
      }.entries) {
        await ModelSetting.set(entry.key.string, entry.value);
      }
      for (final key in [
        AppString.masterKey,
        AppString.fileHashKey,
        AppString.accessKey
      ]) {
        await SecureStorage().write(
            key: key.string, value: base64Encode(List<int>.filled(32, 0)));
      }
      await ModelItem.ensureVaultRoot();
      await db.insert('items', {
        'id': deviceId,
        'parent_id': 'fife',
        'name': 'Linux fixture',
        'archived_at': 0,
        'is_folder': 1
      });
      await db.insert('items', {
        'id': rootId,
        'parent_id': deviceId,
        'name': 'Recovery source',
        'path': source.path,
        'bookmark': 'sandboxed',
        'archived_at': 0,
        'is_folder': 1
      });
      final file = File(path.join(source.path, 'Nested', 'recovery.txt'));
      await file.parent.create(recursive: true);
      await file.writeAsString('Synthetic Linux recovery original.');
      final scan = await ReconciliationService(await SodiumSumoInit.init())
          .reconcile((await ModelItem.get(rootId))!);
      if (!scan.succeeded) throw StateError('Fixture backup scan failed');
      final files = await db.query('items',
          where: 'root_id = ? AND is_folder = 0', whereArgs: [rootId]);
      for (final row in files) {
        for (var n = 0; n < 8; n++) {
          final task = await ModelItemTask.get(row['id'] as String);
          if (task == null) break;
          await TaskManager().checkInitUpload(task);
        }
        if (await ModelItemTask.get(row['id'] as String) != null) {
          throw StateError('Fixture backup upload failed');
        }
      }
      await bucket.writeAsString(
          jsonEncode(api.objects.map((k, v) => MapEntry(k, base64Encode(v)))));
      await source.rename(moved.path);
    } else {
      final saved =
          jsonDecode(await bucket.readAsString()) as Map<String, dynamic>;
      api.objects
          .addAll(saved.map((k, v) => MapEntry(k, base64Decode(v as String))));
    }
    var observing = false;
    final knownCopies = <String, String>{};
    Future<void> observe() async {
      if (observing) return;
      observing = true;
      try {
        final root = await ModelItem.get(rootId);
        final rows = await db.query('items',
            where: 'root_id = ? AND is_folder = 0', whereArgs: [rootId]);
        final copies = <Map<String, Object?>>[];
        for (final row in rows) {
          final id = row['id'] as String;
          String? copy;
          var copyUnavailable = false;
          try {
            copy = await ManagedFileCopies.existingPath(id);
          } on PlatformException catch (error) {
            // Archiving an ancestor intentionally invalidates copy identity.
            // Observe the old physical path below instead of crashing the
            // test observer during that valid product transition.
            if (error.code != 'FOLDER_UNAVAILABLE') rethrow;
            copyUnavailable = true;
          }
          if (copy != null) knownCopies[id] = copy;
          copies.add({
            'id': id,
            'archived': row['archived_at'],
            'managedCopy': copy,
            'copyIdentityUnavailable': copyUnavailable,
            'previousCopyExists': knownCopies[id] != null &&
                await File(knownCopies[id]!).exists(),
            'copyMatches':
                copy == null ? false : await _matchesOriginal(File(copy)),
            'pending': await ModelItemTask.get(id) != null
          });
        }
        await File(path.join(runtime, 'recovery-evidence.json')).writeAsString(
            jsonEncode({
              'pid': pid,
              'syntheticDataOnly': true,
              'rootId': root?.id,
              'rootPath': root?.path,
              'rootArchived': root?.archivedAt,
              'folders': await db.query('items',
                  columns: ['id', 'name', 'archived_at'],
                  where: 'root_id = ? AND is_folder = 1',
                  whereArgs: [rootId]),
              'missingSourceStillAbsent': !await source.exists(),
              'externalOriginalPreserved': await _matchesOriginal(
                  File(path.join(moved.path, 'Nested', 'recovery.txt'))),
              'copies': copies
            }),
            flush: true);
      } finally {
        observing = false;
      }
    }

    await observe();
    Timer.periodic(const Duration(seconds: 1), (_) => unawaited(observe()));
    await application.main();
    await Completer<void>().future;
  });
}

Future<bool?> _matchesOriginal(File file) async {
  try {
    return await file.readAsString() == 'Synthetic Linux recovery original.';
  } on FileSystemException {
    // Permission-loss tests and cleanup races can make a probe unreadable.
    // Null is explicitly unverified, never a successful preservation claim.
    return null;
  }
}

class _RecoveryApi extends TransferApi {
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'HEAD') return http.Response('', 200);
    if (request.url.host == '127.0.0.1') {
      final bytes = objects[request.url.pathSegments.last];
      return bytes == null
          ? http.Response('', 404)
          : http.Response.bytes(bytes, 200);
    }
    if (request.url.path.endsWith('/devices')) {
      return super.json({
        'success': 1,
        'data': {'active': 1}
      });
    }
    if (request.url.path.endsWith('/sync')) {
      return super.json({'success': 1, 'data': {}});
    }
    return super.handle(request);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async =>
      path.join(root, 'support');
  @override
  Future<String> getApplicationDocumentsPath() async =>
      path.join(root, 'documents');
  @override
  Future<String> getTemporaryPath() async => path.join(root, 'temp');
  @override
  Future<String> getDownloadsPath() async => path.join(root, 'documents');
}
