import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/model_item.dart';
import '../utils/common.dart';
import 'storage_channel.dart';
import 'storage_sqlite.dart';
import 'managed_file_copies.dart';

/// Renews permission for an explicitly chosen existing root, preserving its
/// identity even when iOS has moved the app container or the folder was recreated.
class SyncedFolderAccess {
  static Future<bool> isAvailable(ModelItem root) async {
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
    final picked =
        await ChannelStorage.pickDirectory(initialDirectory: root.path);
    if (picked == null) return null;
    final pickedPath = picked['path'];
    final bookmark = picked['bookmark'];
    if (pickedPath == null ||
        !path.isAbsolute(pickedPath) ||
        !ChannelStorage.hasUsableBookmark(bookmark)) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }

    final accessPath = await ChannelStorage.startAccessing(bookmark!);
    if (accessPath == null || accessPath.isEmpty) {
      throw PlatformException(code: 'ACCESS_DENIED');
    }
    try {
      if (!await Directory(accessPath).exists()) {
        throw PlatformException(code: 'FOLDER_UNAVAILABLE');
      }
      final recovered = await StorageSqlite.instance.runInTransaction(() async {
        // A picker may outlive logout, root removal or another recovery attempt.
        if (await getDeviceHash() != deviceHash) {
          throw PlatformException(code: 'FOLDER_UNAVAILABLE');
        }
        final other = await ModelItem.syncFolderExists(pickedPath);
        if (other != null && other.id != root.id) {
          throw PlatformException(code: 'FOLDER_ALREADY_SELECTED');
        }
        if (!await ModelItem.replaceFolderAccess(root,
            pickedPath: pickedPath, bookmark: bookmark)) {
          throw PlatformException(code: 'FOLDER_UNAVAILABLE');
        }
        await ManagedFileCopies.prepareRootCleanup(root);
        return ModelItem.get(root.id);
      });
      await ManagedFileCopies.finishRootCleanup(root.id);
      return recovered;
    } finally {
      await ChannelStorage.stopAccessing(accessPath);
    }
  }
}
