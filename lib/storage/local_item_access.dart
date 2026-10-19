import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/model_item.dart';
import '../utils/common.dart';
import 'storage_channel.dart';

/// Keeps a selected folder accessible throughout a file operation, including
/// awaits. A denied bookmark must never be treated as a missing source file.
class LocalItemAccess {
  final String itemPath;
  String? _accessPath;

  LocalItemAccess._(this.itemPath, this._accessPath);

  static Future<LocalItemAccess> acquire(String itemId) async {
    final itemPath = await ModelItem.getPathForItem(itemId);
    final rows = await ModelItem.getPathRowsForItem(itemId);
    final deviceHash = await getDeviceHash();
    final deviceIndex = rows.indexWhere((row) => row['id'] == deviceHash);
    // Copies of another device's files live in this app's own Documents folder.
    if (deviceIndex < 0) {
      await _validatePath(await ModelItem.getPathForItem('fife'), itemPath);
      return LocalItemAccess._(itemPath, null);
    }

    final roots = rows.skip(deviceIndex + 1).where((row) {
      final rootPath = row['path'] as String?;
      return rootPath != null && rootPath.isNotEmpty;
    });
    if (roots.isEmpty) throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    final root = await ModelItem.get(roots.first['id'] as String);
    if (root == null) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }

    final storedRootPath = path.normalize(root.path!);
    final storedItemPath = path.normalize(itemPath);
    if (!path.isAbsolute(storedRootPath) ||
        (storedItemPath != storedRootPath &&
            !path.isWithin(storedRootPath, storedItemPath))) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    if (!Platform.isIOS && !Platform.isMacOS) {
      await _validatePath(storedRootPath, storedItemPath);
      return LocalItemAccess._(storedItemPath, null);
    }
    if (!ChannelStorage.hasUsableBookmark(root.bookmark)) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    final accessPath = await ChannelStorage.startAccessing(root.bookmark!);
    if (accessPath == null || accessPath.isEmpty) {
      throw PlatformException(code: 'ACCESS_DENIED');
    }
    // The bookmark may restore a moved folder. Derive the child from the
    // resolved root instead of relying on the old persisted absolute path.
    final relativePath = path.relative(storedItemPath, from: storedRootPath);
    final resolvedItemPath = path.join(accessPath, relativePath);
    try {
      await _validatePath(accessPath, resolvedItemPath);
      return LocalItemAccess._(resolvedItemPath, accessPath);
    } catch (_) {
      // No access object is returned on failure, so release the bookmark here.
      try {
        await ChannelStorage.stopAccessing(accessPath);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> _validatePath(String rootPath, String itemPath) async {
    final root = path.normalize(rootPath);
    final item = path.normalize(itemPath);
    if (!path.isAbsolute(root) ||
        (root != item && !path.isWithin(root, item))) {
      throw PlatformException(code: 'FOLDER_UNAVAILABLE');
    }
    // A directory may have been replaced since the scan. Never follow a link
    // when reading or publishing content under a selected or managed root.
    var current = root;
    final relative = path.relative(item, from: root);
    for (final segment in ['.', ...path.split(relative)]) {
      current = path.normalize(path.join(current, segment));
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw PlatformException(code: 'FOLDER_UNAVAILABLE');
      }
    }
  }

  Future<void> release() async {
    final accessPath = _accessPath;
    _accessPath = null;
    if (accessPath != null) await ChannelStorage.stopAccessing(accessPath);
  }

  static Future<T> withAccess<T>(
      String itemId, Future<T> Function(String itemPath) operation) async {
    final access = await acquire(itemId);
    try {
      return await operation(access.itemPath);
    } finally {
      await access.release();
    }
  }
}
