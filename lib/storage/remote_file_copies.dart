import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/model_item.dart';
import '../models/model_item_task.dart';
import '../models/model_state.dart';
import '../services/service_session_cleanup.dart';
import '../services/service_sync_budget.dart';
import '../services/service_logger.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import 'local_item_access.dart';
import 'managed_file_copies.dart';
import 'storage_sqlite.dart';

class RemoteCopyTransfer {
  const RemoteCopyTransfer(this.id, this.generation, this.hash, this.size);
  final String id;
  final String generation;
  final String hash;
  final int size;
}

/// Downloaded remote copies are subscriptions to the source version. Intent is
/// account-scoped, survives restart, and is distinct from external source files
/// and the explicit recovery copies of disconnected local folders.
class RemoteFileCopies {
  static final _logger = AppLogger(prefixes: ['Remote copies']);
  static String _key(String id) => 'remote_copy:$id';

  // A valid source name may already be at the filesystem's name-length limit.
  // Keep replacement names independent of it while staying on the same volume.
  static String replacementPath(String location, String generation) =>
      p.join(p.dirname(location), '.$generation.fife-partial');

  static Future<Map<String, dynamic>?> _record(String id) async {
    final value = await ModelState.get(_key(id));
    return value.isEmpty ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  static Future<bool> isRemote(String id) async {
    final rows = await ModelItem.getPathRowsForItem(id);
    final device = await getDeviceHash();
    return rows.length >= 3 && !rows.any((row) => row['id'] == device);
  }

  static Future<String> _relative(String location) async =>
      p.relative(location, from: await ModelItem.getPathForItem('fife'));

  static Future<String> _path(String relative) async {
    final root = await ModelItem.getPathForItem('fife');
    final location = p.normalize(p.join(root, relative));
    if (p.isAbsolute(relative) || !p.isWithin(root, location)) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    await LocalItemAccess.validateManagedPath(root, location);
    return location;
  }

  /// Also used by preview after a source rename while its replacement is pending.
  static Future<String?> existingPath(String id) async {
    final record = await _record(id);
    if (record == null ||
        record['cancelled'] == true ||
        record['path'] == null) {
      return null;
    }
    final location = await _path(record['path'] as String);
    return await File(location).exists() ? location : null;
  }

  static Future<Map<String, dynamic>> _newRecord(String id) async => {
        'generation': const Uuid().v4(),
        'ancestors': (await ModelItem.getPathRowsForItem(id))
            .map((row) => row['id'])
            .toList(),
      };

  /// A new explicit download can opt back in after local deletion.
  static Future<void> request(String id) async {
    if (!await isRemote(id)) return;
    await resumeCleanup();
    await StorageSqlite.instance.runInTransaction(() async {
      final record = await _record(id);
      if (record == null || record['cancelled'] == true) {
        await ModelState.set(_key(id), jsonEncode(await _newRecord(id)));
      }
      await ModelItemTask.addTask(id, ItemTask.download.value);
    });
  }

  /// Called by the normal dispatcher, including foreground/background startup.
  /// Legacy copies are hashed once: current metadata may already describe a
  /// newer version, so it cannot establish which bytes were downloaded earlier.
  static Future<void> reconcile(Future<String?> Function(File) hashFile) async {
    await resumeCleanup();
    final db = await StorageSqlite.instance.executor;
    final rows = await db.query('items',
        columns: ['id'], where: 'is_folder = 0 AND archived_at = 0');
    for (final row in rows) {
      SyncBudget.check();
      final id = row['id'] as String;
      if (!await isRemote(id) ||
          await ManagedFileCopies.hasArchivedAncestor(id)) {
        continue;
      }
      final item = await ModelItem.get(id);
      if (item?.fileHash == null) continue;
      LocalItemAccess? access;
      try {
        access = await LocalItemAccess.acquire(id);
        var record = await _record(id);
        if (record?['cancelled'] == true) continue;
        if (record == null) {
          final file = File(access.itemPath);
          if (!await file.exists()) continue;
          final hash = await hashFile(file);
          if (hash == null) continue;
          final adopted = {
            ...await _newRecord(id),
            'path': await _relative(file.path),
            'hash': hash
          };
          await StorageSqlite.instance.runInTransaction(() async {
            if (await _record(id) == null) {
              await ModelState.set(_key(id), jsonEncode(adopted));
            }
          });
          record = await _record(id);
        }
        if (record == null ||
            record['cancelled'] == true ||
            record['path'] == null) {
          continue;
        }
        if (await existingPath(id) == null) {
          // External removal of an app-owned copy also ends its subscription.
          await cancelTree(id);
          continue;
        }
        if (record['hash'] != item!.fileHash ||
            record['path'] != await _relative(access.itemPath)) {
          await StorageSqlite.instance.runInTransaction(() async {
            final current = await _record(id);
            final currentItem = await ModelItem.get(id);
            if (current?['generation'] == record!['generation'] &&
                current?['cancelled'] != true &&
                currentItem?.fileHash != null) {
              // Keep retry backoff/terminal failures. A newer source version
              // may re-enable a failed attempt for the previous version.
              final task = await ModelItemTask.get(id);
              if (task == null || current!['target'] != currentItem!.fileHash) {
                current!['target'] = currentItem!.fileHash;
                await ModelState.set(_key(id), jsonEncode(current));
                await ModelItemTask.addTask(id, ItemTask.download.value);
              }
            }
          });
        }
        await retirePrevious(id);
      } on FileSystemException {
        _logger
            .warning('Remote copy unavailable; retaining its previous version');
      } on PlatformException {
        _logger.warning('Remote copy access refused');
      } finally {
        await access?.release();
      }
    }
  }

  static Future<RemoteCopyTransfer?> capture(ModelItem item) async {
    if (!await isRemote(item.id)) return null;
    return StorageSqlite.instance.runInTransaction(() async {
      var record = await _record(item.id);
      if (record?['cancelled'] == true) {
        throw PlatformException(code: 'DOWNLOAD_CANCELLED');
      }
      // Supports persisted initial download queues from previous releases.
      if (record == null) {
        record = await _newRecord(item.id);
        await ModelState.set(_key(item.id), jsonEncode(record));
      }
      return RemoteCopyTransfer(
          item.id, record['generation'] as String, item.fileHash!, item.size);
    });
  }

  static Future<void> check(RemoteCopyTransfer? transfer) async {
    if (transfer == null) return;
    final record = await _record(transfer.id);
    if (record?['generation'] != transfer.generation ||
        record?['cancelled'] == true ||
        await ModelItemTask.get(transfer.id) == null ||
        !await isRemote(transfer.id) ||
        await ManagedFileCopies.hasArchivedAncestor(transfer.id)) {
      throw PlatformException(code: 'DOWNLOAD_CANCELLED');
    }
    final item = await ModelItem.get(transfer.id);
    if (record!['path'] is String && await existingPath(transfer.id) == null) {
      throw PlatformException(code: 'DOWNLOAD_CANCELLED');
    }
    if (item?.fileHash != transfer.hash || item?.size != transfer.size) {
      throw PlatformException(code: 'DOWNLOAD_SUPERSEDED');
    }
  }

  static Future<bool> mayReplace(
      RemoteCopyTransfer transfer, String location) async {
    await check(transfer);
    final record = (await _record(transfer.id))!;
    return record['path'] == await _relative(location);
  }

  /// Called in the account transaction, after publication released its gate.
  static Future<void> complete(
      RemoteCopyTransfer? transfer, String location) async {
    if (transfer == null) return;
    await check(transfer);
    final record = (await _record(transfer.id))!;
    final relative = await _relative(location);
    if (record['path'] != null && record['path'] != relative) {
      record['retired'] = {
        ...List<String>.from(record['retired'] ?? []),
        record['path'] as String
      }.toList();
    }
    record['hash'] = transfer.hash;
    record['path'] = relative;
    record['ancestors'] = (await ModelItem.getPathRowsForItem(transfer.id))
        .map((row) => row['id'])
        .toList();
    await ModelState.set(_key(transfer.id), jsonEncode(record));
  }

  static Future<void> stopCancelled(RemoteCopyTransfer? transfer) async {
    if (transfer == null) return;
    await StorageSqlite.instance.runInTransaction(() async {
      if ((await _record(transfer.id))?['generation'] == transfer.generation) {
        final task = await ModelItemTask.get(transfer.id);
        if (task?.task == ItemTask.download.value) await task!.delete();
      }
    });
  }

  /// Persist cancellation before waiting on publication; workers cannot revive
  /// this intent, even if a user immediately requests another download.
  static Future<void> cancelTree(String id) async {
    await StorageSqlite.instance.runInTransaction(() async {
      final db = await StorageSqlite.instance.executor;
      final descendants = await db.rawQuery('''
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM items WHERE id = ?
          UNION SELECT items.id FROM items JOIN subtree ON items.parent_id = subtree.id
        ) SELECT id FROM subtree
      ''', [id]);
      final ids = descendants.map((row) => row['id'] as String).toSet()
        ..add(id);
      final records = await db
          .query('states', where: 'id GLOB ?', whereArgs: ['remote_copy:*']);
      for (final row in records) {
        final record = jsonDecode(row['value'] as String) as Map;
        if ((record['ancestors'] as List?)?.contains(id) == true) {
          ids.add((row['id'] as String).substring('remote_copy:'.length));
        }
      }
      for (final child in ids) {
        final record = await _record(child) ?? await _newRecord(child);
        // A process can die after copying a verified replacement beside the
        // destination. Retain its exact path when retiring this generation.
        final currentPath = await ModelItem.getPathForItem(child);
        final paths = <String>{
          if (record['path'] is String) record['path'] as String,
          if (currentPath.isNotEmpty) await _relative(currentPath),
        };
        record['discardedCandidates'] = {
          ...List<String>.from(record['discardedCandidates'] ?? []),
          for (final location in paths)
            replacementPath(location, record['generation'] as String),
        }.toList();
        record['generation'] = const Uuid().v4();
        record['cancelled'] = true;
        await ModelState.set(_key(child), jsonEncode(record));
        final task = await ModelItemTask.get(child);
        if (task?.task == ItemTask.download.value) await task!.delete();
      }
    });
  }

  static Future<void> deleteLocal(ModelItem item, String location) async {
    // Save the cleanup intent in the same transaction as cancellation. A crash
    // between cancellation and filesystem deletion must resume that deletion.
    final key = 'remote_copy_cleanup:${item.id}';
    await StorageSqlite.instance.runInTransaction(() async {
      await cancelTree(item.id);
      await ModelState.set(
          key,
          jsonEncode({
            'path': await _relative(location),
            'folder': item.isFolder,
            'generation': const Uuid().v4(),
          }));
    });
    await resumeCleanup();
  }

  static Future<void> resumeCleanup() async {
    final db = await StorageSqlite.instance.executor;
    final markers = await db.query('states',
        where: 'id GLOB ?', whereArgs: ['remote_copy_cleanup:*']);
    for (final marker in markers) {
      final value = jsonDecode(marker['value'] as String) as Map;
      await SessionCleanup.instance.withPublication(() async {
        if (await ModelState.get(marker['id'] as String) != marker['value']) {
          return;
        }
        final location = await _path(value['path'] as String);
        if (value['folder'] == true) {
          if (await Directory(location).exists()) {
            await Directory(location).delete(recursive: true);
          }
        } else if (await File(location).exists()) {
          await File(location).delete();
        }
      });
      await StorageSqlite.instance.runInTransaction(() async {
        if (await ModelState.get(marker['id'] as String) == marker['value']) {
          await ModelState.delete(marker['id'] as String);
        }
      });
    }
    final records = await db
        .query('states', where: 'id GLOB ?', whereArgs: ['remote_copy:*']);
    for (final row in records) {
      final record = jsonDecode(row['value'] as String) as Map;
      final candidates = List<String>.from(record['discardedCandidates'] ?? []);
      if (candidates.isEmpty) continue;
      await SessionCleanup.instance.withPublication(() async {
        for (final relative in candidates) {
          final file = File(await _path(relative));
          if (await file.exists()) await file.delete();
        }
      });
      await StorageSqlite.instance.runInTransaction(() async {
        final key = row['id'] as String;
        if (await ModelState.get(key) == row['value']) {
          record.remove('discardedCandidates');
          await ModelState.set(key, jsonEncode(record));
        }
      });
    }
  }

  /// A source rename may leave the prior copy at a different relative path.
  /// Retire it only after publishing the replacement, and never delete a path
  /// that has since become another item's current destination.
  static Future<void> retirePrevious(String id) async {
    final record = await _record(id);
    final retired = List<String>.from(record?['retired'] ?? []);
    if (retired.isEmpty) return;
    final db = await StorageSqlite.instance.executor;
    final rows =
        await db.query('items', columns: ['id'], where: 'is_folder = 0');
    final occupied = <String>{};
    for (final row in rows) {
      if (await isRemote(row['id'] as String)) {
        occupied.add(await _relative(
            await ModelItem.getPathForItem(row['id'] as String)));
      }
    }
    await SessionCleanup.instance.withPublication(() async {
      if ((await _record(id))?['generation'] != record!['generation']) return;
      for (final relative in retired) {
        if (occupied.contains(relative)) continue;
        final file = File(await _path(relative));
        if (await file.exists()) await file.delete();
      }
    });
    await StorageSqlite.instance.runInTransaction(() async {
      final current = await _record(id);
      if (current?['generation'] == record!['generation']) {
        current!['retired'] = List<String>.from(current['retired'] ?? [])
            .where((path) => !retired.contains(path))
            .toList();
        await ModelState.set(_key(id), jsonEncode(current));
      }
    });
  }
}
