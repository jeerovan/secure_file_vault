import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_item_task.dart';
import '../models/model_state.dart';
import '../services/service_session_cleanup.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import 'storage_sqlite.dart';
import 'archived_sync_folders.dart';

class ManagedCopyTransfer {
  const ManagedCopyTransfer(this.generations);
  final Map<String, String> generations;
}

/// Explicit recovery copies never become synchronization sources. The local
/// intent survives restart; paths are rebuilt under the current app container.
class ManagedFileCopies {
  static String _key(String id) => 'managed_copy:$id';
  static String _cleanupKey(String rootId) => 'managed_copy_cleanup:$rootId';

  static Future<ModelItem?> _root(String id) async {
    final rows = await ModelItem.getPathRowsForItem(id);
    final device = await getDeviceHash();
    final index = rows.indexWhere((row) => row['id'] == device);
    if (index < 0 || index + 1 >= rows.length) return null;
    final root = await ModelItem.get(rows[index + 1]['id'] as String);
    return root != null && root.isFolder && root.parentId == device
        ? root
        : null;
  }

  static Future<bool> cleanupPending(String rootId) async {
    final value = await ModelState.get(_cleanupKey(rootId));
    return value.isNotEmpty && (jsonDecode(value) as Map)['pending'] == true;
  }

  static Future<ManagedCopyTransfer?> captureTransfer(String id) async {
    final root = await _root(id);
    if (root == null) return null;
    final rows = await ModelItem.getPathRowsForItem(id);
    final start = rows.indexWhere((row) => row['id'] == root.id);
    final generations = <String, String>{};
    for (final row in rows.skip(start)) {
      final key = _cleanupKey(row['id'] as String);
      final value = await ModelState.get(key);
      if (value.isNotEmpty && (jsonDecode(value) as Map)['pending'] == true) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
      generations[key] = value;
    }
    return ManagedCopyTransfer(generations);
  }

  static Future<void> checkTransfer(ManagedCopyTransfer? transfer) async {
    if (transfer == null) return;
    for (final entry in transfer.generations.entries) {
      if (await ModelState.get(entry.key) != entry.value) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
    }
  }

  /// Call in the same account transaction as reconnect/archive. The durable
  /// generation invalidates old workers even after cleanup has completed.
  static Future<void> prepareRootCleanup(ModelItem root) async {
    if (!root.isFolder || root.parentId != await getDeviceHash()) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    await prepareFolderCleanup(root);
  }

  static Future<void> prepareFolderCleanup(ModelItem folder) async {
    final root = await _root(folder.id);
    if (!folder.isFolder || root == null) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    final identity = await _identity(folder);
    final names = List<String>.from(identity['names'] as List);
    final db = await StorageSqlite.instance.executor;
    final descendants = await db.rawQuery('''
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM items WHERE id = ?
        UNION SELECT items.id FROM items JOIN subtree ON items.parent_id = subtree.id
      ) SELECT id FROM subtree
    ''', [folder.id]);
    final ids = descendants.map((row) => row['id'] as String).toSet();
    final prefixes = <List<String>>[names];
    for (final record in await _rootRecords(root.id)) {
      final id = (record['id'] as String).substring('managed_copy:'.length);
      final value = jsonDecode(record['value'] as String) as Map;
      final oldNames = List<String>.from(value['names'] as List);
      if (ids.contains(id) && oldNames.length >= names.length) {
        prefixes.add(oldNames.take(names.length).toList());
      }
      if (folder.id == root.id || _withinNames(oldNames, names)) {
        ids.add(id);
      }
    }
    await ModelState.set(
        _cleanupKey(folder.id),
        jsonEncode({
          'root': root.id,
          'scope': folder.id,
          'ids': ids.toList(),
          'prefixes': prefixes,
          'generation': const Uuid().v4(),
          'pending': true,
        }));
    for (final id in ids) {
      final task = await ModelItemTask.get(id);
      if (task?.task == ItemTask.download.value) await task!.delete();
    }
  }

  static bool _withinNames(List<String> names, List<String> prefix) =>
      names.length >= prefix.length &&
      List.generate(prefix.length, (i) => names[i] == prefix[i])
          .every((v) => v);

  static bool _inScope(Map marker, Map<String, Object?> record) {
    if (marker['scope'] == null || marker['scope'] == marker['root']) {
      return true;
    }
    final id = (record['id'] as String).substring('managed_copy:'.length);
    if ((marker['ids'] as List).contains(id)) return true;
    final names = List<String>.from(
        (jsonDecode(record['value'] as String) as Map)['names'] as List);
    return (marker['prefixes'] as List).any(
        (prefix) => _withinNames(names, List<String>.from(prefix as List)));
  }

  static Future<List<Map<String, Object?>>> _rootRecords(String rootId) async {
    final db = await StorageSqlite.instance.executor;
    final rows = await db
        .query('states', where: 'id GLOB ?', whereArgs: ['managed_copy:*']);
    return rows
        .where((row) =>
            (jsonDecode(row['value'] as String) as Map)['root'] == rootId)
        .toList();
  }

  static Future<void> finishRootCleanup(String scopeId) async {
    final key = _cleanupKey(scopeId);
    final marker = await ModelState.get(key);
    if (marker.isEmpty || (jsonDecode(marker) as Map)['pending'] != true) {
      return;
    }
    final cleanup = jsonDecode(marker) as Map;
    final rootId = cleanup['root'] as String;
    // Serialize deletion with final plaintext publication across engines.
    // Never hold the account write transaction while waiting for this gate.
    await SessionCleanup.instance.withPublication(() async {
      if (await ModelState.get(key) != marker) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
      final base = await ModelItem.getPathForItem('fife');
      final downloads = p.join(base, '.downloads');
      for (final parent in [base, downloads]) {
        if (await FileSystemEntity.type(parent, followLinks: false) ==
            FileSystemEntityType.link) {
          throw PlatformException(code: 'ACCESS_DENIED');
        }
      }
      final token = base64UrlEncode(utf8.encode(rootId)).replaceAll('=', '');
      if (token.isEmpty) throw PlatformException(code: 'FOLDER_UNAVAILABLE');
      final namespace = p.join(downloads, token);
      if (cleanup['scope'] == null || cleanup['scope'] == rootId) {
        await SessionCleanup.removeOwnedPath(namespace);
      } else {
        if (await FileSystemEntity.type(namespace, followLinks: false) ==
            FileSystemEntityType.link) {
          throw PlatformException(code: 'ACCESS_DENIED');
        }
        if (!await Directory(namespace).exists()) return;
        await for (final version
            in Directory(namespace).list(followLinks: false)) {
          if (version is! Directory) {
            if (version is Link) throw PlatformException(code: 'ACCESS_DENIED');
            continue;
          }
          for (final prefix in cleanup['prefixes'] as List) {
            final record = {
              'root': rootId,
              'copy': p.basename(version.path),
              'names': prefix
            };
            final target = await _path(record);
            await SessionCleanup.removeOwnedPath(target);
          }
        }
      }
    });
    await StorageSqlite.instance.runInTransaction(() async {
      if (await ModelState.get(key) != marker) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
      for (final record in await _rootRecords(rootId)) {
        if (!_inScope(cleanup, record)) continue;
        // An old worker must not mistake removed intent for permission to
        // publish to the external source. A new explicit request replaces this.
        final cancelled =
            jsonDecode(record['value'] as String) as Map<String, dynamic>;
        cancelled['pending'] = false;
        cancelled['cancelled'] = true;
        await ModelState.set(record['id'] as String, jsonEncode(cancelled));
      }
      final completed = jsonDecode(marker) as Map<String, dynamic>;
      completed['pending'] = false;
      await ModelState.set(key, jsonEncode(completed));
    });
  }

  static Future<void> resumeCleanup() async {
    final db = await StorageSqlite.instance.executor;
    final rows = await db.query('states',
        where: 'id GLOB ?', whereArgs: ['managed_copy_cleanup:*']);
    for (final row in rows) {
      final marker = jsonDecode(row['value'] as String) as Map;
      if (marker['pending'] == true) {
        await finishRootCleanup((marker['scope'] ?? marker['root']) as String);
      }
    }
  }

  static Future<bool> hasArchivedAncestor(String id) async {
    final rows = await ModelItem.getPathRowsForItem(id);
    if (rows.isEmpty) return true;
    final db = await StorageSqlite.instance.executor;
    final archived = await db.query('items',
        columns: ['id'],
        where:
            'archived_at > 0 AND id IN (${List.filled(rows.length, '?').join(',')})',
        whereArgs: rows.map((row) => row['id']).toList(),
        limit: 1);
    return archived.isNotEmpty;
  }

  static Future<ModelItem?> localRoot(String id) async {
    final root = await _root(id);
    return root != null &&
            root.archivedAt == 0 &&
            !await cleanupPending(root.id) &&
            !await _hasPendingAncestor(id) &&
            !await hasArchivedAncestor(id)
        ? root
        : null;
  }

  static Future<bool> _hasPendingAncestor(String id) async {
    for (final row in await ModelItem.getPathRowsForItem(id)) {
      if (await cleanupPending(row['id'] as String)) return true;
    }
    return false;
  }

  static Future<void> restoreFolder(ModelItem item) async {
    await finishRootCleanup(item.id);
    await StorageSqlite.instance.runInTransaction(() async {
      if (await cleanupPending(item.id)) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
      final current = await ModelItem.get(item.id);
      if (current == null) return;
      current.archivedAt = 0;
      await current.update(['archived_at']);
      await ArchivedSyncFolders.clear(item.id);
    });
  }

  static Future<bool> hasBackup(ModelItem item) async {
    final hash = item.fileHash;
    if (item.isFolder || hash == null) return false;
    final file = await ModelFile.get(hash);
    return file != null && file.uploadedAt > 0;
  }

  static Future<Map<String, dynamic>> _identity(ModelItem item) async {
    final root = await localRoot(item.id);
    if (root == null) throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    final rows = await ModelItem.getPathRowsForItem(item.id);
    final start = rows.indexWhere((row) => row['id'] == root.id);
    final names = rows.skip(start).map((row) => row['name'] as String).toList();
    if (rows.map((row) => row['id']).toSet().length != rows.length ||
        names.any((name) =>
            name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains('\\') ||
            name.contains('\u0000'))) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    return {'root': root.id, 'hash': item.fileHash, 'names': names};
  }

  static Future<Map<String, dynamic>?> _record(String id) async {
    final value = await ModelState.get(_key(id));
    if (value.isEmpty) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw PlatformException(code: 'INVALID_DOWNLOAD_DESTINATION');
    }
    return decoded;
  }

  static bool _matches(
          Map<String, dynamic> record, Map<String, dynamic> identity) =>
      record['root'] == identity['root'] &&
      record['hash'] == identity['hash'] &&
      listEquals(record['names'] as List?, identity['names'] as List?);

  static Future<String> _path(Map<String, dynamic> record) async {
    final root = record['root'] as String;
    final copy = record['copy'] as String;
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(copy)) {
      throw PlatformException(code: 'INVALID_DOWNLOAD_DESTINATION');
    }
    final base = await ModelItem.getPathForItem('fife');
    final rootToken = base64UrlEncode(utf8.encode(root)).replaceAll('=', '');
    final names = List<String>.from(record['names'] as List);
    if (names.isEmpty ||
        names.any((name) =>
            name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains('\\') ||
            name.contains('\u0000'))) {
      throw PlatformException(code: 'ACCESS_DENIED');
    }
    final copyBase = p.join(base, '.downloads', rootToken, copy);
    final target = p.joinAll([copyBase, ...names]);
    if (!p.isWithin(copyBase, target)) {
      throw PlatformException(code: 'ACCESS_DENIED');
    }
    var current = base;
    for (final part in ['.', ...p.split(p.relative(target, from: base))]) {
      current = p.normalize(p.join(current, part));
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw PlatformException(code: 'ACCESS_DENIED');
      }
    }
    return target;
  }

  static Future<String?> existingPath(String id) async {
    final record = await _record(id);
    final item = record == null ? null : await ModelItem.get(id);
    if (record == null ||
        record['cancelled'] == true ||
        item == null ||
        item.isFolder ||
        !_matches(record, await _identity(item))) {
      return null;
    }
    final target = await _path(record);
    return await File(target).exists() ? target : null;
  }

  static Future<String?> downloadPath(String id) async {
    final record = await _record(id);
    if (record?['cancelled'] == true) {
      throw PlatformException(code: 'DOWNLOAD_CANCELLED');
    }
    if (record == null || record['pending'] != true) return null;
    final item = await ModelItem.get(id);
    if (item == null || !_matches(record, await _identity(item))) {
      throw PlatformException(code: 'DOWNLOAD_DESTINATION_CHANGED');
    }
    return _path(record);
  }

  static Future<void> complete(String id, String publishedPath) async {
    final record = await _record(id);
    if (record != null &&
        record['cancelled'] != true &&
        await _path(record) == publishedPath) {
      record['pending'] = false;
      await ModelState.set(_key(id), jsonEncode(record));
    }
  }

  static Future<void> useSourceForDownload(String id) async {
    final record = await _record(id);
    if (record?['cancelled'] == true) {
      await ModelState.delete(_key(id));
      return;
    }
    if (record != null && record['pending'] == true) {
      record['pending'] = false;
      await ModelState.set(_key(id), jsonEncode(record));
    }
  }

  static Future<void> requestTree(ModelItem selected) async {
    final transfer = await captureTransfer(selected.id);
    final pending = [selected];
    final seen = <String>{};
    final files = <ModelItem>[];
    final folders = <ModelItem>[];
    while (pending.isNotEmpty) {
      final item = pending.removeLast();
      if (!seen.add(item.id)) {
        throw PlatformException(code: 'INVALID_FOLDER_TREE');
      }
      if (item.archivedAt != 0) continue;
      if (item.isFolder) {
        folders.add(item);
        pending.addAll(await ModelItem.getAllInFolder(item));
      } else if (await hasBackup(item)) {
        files.add(item);
      }
    }
    final copy = const Uuid().v4();
    final directories = <String, Map<String, dynamic>>{};
    // Resolve/validate every path before scheduling any work.
    for (final folder in folders) {
      final record = {...await _identity(folder), 'copy': copy};
      await _path(record);
      directories[folder.id] = record;
    }
    final records = <String, Map<String, dynamic>>{};
    for (final item in files) {
      final identity = await _identity(item);
      final previous = await _record(item.id);
      final record = previous != null && _matches(previous, identity)
          ? previous
          : {...identity, 'copy': copy};
      await _path(record);
      if (await existingPath(item.id) != null) continue;
      records[item.id] = {...record, 'pending': true, 'cancelled': false};
    }
    await SessionCleanup.instance.withPublication(() async {
      await checkTransfer(transfer);
      for (final entry in directories.entries) {
        final current = await ModelItem.get(entry.key);
        if (current == null ||
            !_matches(entry.value, await _identity(current))) {
          throw PlatformException(code: 'DOWNLOAD_DESTINATION_CHANGED');
        }
        await Directory(await _path(entry.value)).create(recursive: true);
      }
    });
    await StorageSqlite.instance.runInTransaction(() async {
      await checkTransfer(transfer);
      for (final entry in records.entries) {
        final current = await ModelItem.get(entry.key);
        if (current == null ||
            !_matches(entry.value, await _identity(current))) {
          throw PlatformException(code: 'DOWNLOAD_DESTINATION_CHANGED');
        }
        await ModelState.set(_key(entry.key), jsonEncode(entry.value));
        await ModelItemTask.addTask(entry.key, ItemTask.download.value);
      }
    });
  }
}
