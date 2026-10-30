import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/model_item.dart';
import '../utils/common.dart';
import 'storage_channel.dart';
import 'storage_sqlite.dart';
import 'managed_file_copies.dart';

/// Reconnects an explicitly chosen existing root without replacing its identity.
/// Apple uses security-scoped bookmarks; Windows uses a validated source path.
class SyncedFolderAccess {
  static bool get supported =>
      Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  static Future<bool> _windowsDirectoryAvailable(String? location) async {
    if (location == null || !path.isAbsolute(location)) return false;
    final normalized = path.normalize(location);
    if (path
        .split(normalized)
        .any((part) => part.toLowerCase() == r'$recycle.bin')) {
      return false;
    }
    try {
      if (await FileSystemEntity.type(normalized, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      // Existence alone does not establish permission to read the directory.
      // Inspect at most one entry; never write a permission-probe file.
      await Directory(normalized).list(followLinks: false).isEmpty;
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> isAvailable(ModelItem root) async {
    if (Platform.isWindows) return _windowsDirectoryAvailable(root.path);
    if (!ChannelStorage.hasUsableBookmark(root.bookmark)) return false;
    String? accessPath;
    try {
      accessPath = await ChannelStorage.startAccessing(root.bookmark!);
      return accessPath != null &&
          accessPath.isNotEmpty &&
          await Directory(accessPath).exists();
    } on PlatformException {
      return false;
    } on FileSystemException {
      return false;
    } finally {
      if (accessPath != null && accessPath.isNotEmpty) {
        await ChannelStorage.stopAccessing(accessPath);
      }
    }
  }

  static Future<ModelItem?> reselect(ModelItem root) async {
    final deviceHash = await getDeviceHash();
    if (!root.isFolder || root.parentId != deviceHash) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    final Map<String, String>? picked;
    if (Platform.isWindows) {
      final selected = await FilePicker.getDirectoryPath(
          initialDirectory:
              await _windowsDirectoryAvailable(root.path) ? root.path : null,
          windowsOptions: const WindowsOptions(lockParentWindow: true));
      picked =
          selected == null ? null : {'path': selected, 'bookmark': 'sandboxed'};
    } else {
      picked = await ChannelStorage.pickDirectory(initialDirectory: root.path);
    }
    if (picked == null) return null;
    final pickedPath = picked['path'];
    final bookmark = picked['bookmark'];
    if (pickedPath == null ||
        !path.isAbsolute(pickedPath) ||
        (!Platform.isWindows && !ChannelStorage.hasUsableBookmark(bookmark))) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }

    final accessPath = Platform.isWindows
        ? (await _windowsDirectoryAvailable(pickedPath) ? pickedPath : null)
        : await ChannelStorage.startAccessing(bookmark!);
    if (accessPath == null || accessPath.isEmpty) {
      throw PlatformException(code: 'ACCESS_DENIED');
    }
    try {
      if (!await Directory(accessPath).exists()) {
        throw PlatformException(code: 'FOLDER_UNAVAILABLE');
      }
      // A recovery copy is owned by FiFe and will be deleted on reconnect.
      // It must never become the new source, including through an alias.
      final copies = Directory(
          path.join(await ModelItem.getPathForItem('fife'), '.downloads'));
      if (await copies.exists()) {
        var owned = await copies.resolveSymbolicLinks();
        var selected = await Directory(accessPath).resolveSymbolicLinks();
        if (Platform.isWindows) {
          owned = owned.toLowerCase();
          selected = selected.toLowerCase();
        }
        if (path.equals(owned, selected) || path.isWithin(owned, selected)) {
          throw PlatformException(code: 'FOLDER_UNAVAILABLE');
        }
      }
      final recovered = await StorageSqlite.instance.runInTransaction(() async {
        // A picker may outlive logout, root removal or another recovery attempt.
        if (await getDeviceHash() != deviceHash) {
          throw PlatformException(code: 'FOLDER_UNAVAILABLE');
        }
        final other = await ModelItem.syncFolderExists(pickedPath);
        var duplicate = other != null && other.id != root.id;
        if (Platform.isWindows) {
          // Windows paths are normally case-insensitive. Do not merge roots
          // just because the picker returned different casing/separators.
          final rows = await (await StorageSqlite.instance.executor).query(
              'items',
              columns: ['id', 'path'],
              where: 'parent_id = ?',
              whereArgs: [deviceHash]);
          duplicate = rows.any((row) =>
              row['id'] != root.id &&
              row['path'] is String &&
              path.equals((row['path'] as String).toLowerCase(),
                  pickedPath.toLowerCase()));
        }
        if (duplicate) {
          throw PlatformException(code: 'FOLDER_ALREADY_SELECTED');
        }
        if (!await ModelItem.replaceFolderAccess(root,
            pickedPath: pickedPath, bookmark: bookmark!)) {
          throw PlatformException(code: 'FOLDER_UNAVAILABLE');
        }
        await ManagedFileCopies.prepareRootCleanup(root);
        return ModelItem.get(root.id);
      });
      await ManagedFileCopies.finishRootCleanup(root.id);
      return recovered;
    } finally {
      if (!Platform.isWindows) await ChannelStorage.stopAccessing(accessPath);
    }
  }
}
