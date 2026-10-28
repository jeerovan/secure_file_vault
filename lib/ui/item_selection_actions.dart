import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/model_item.dart';
import '../models/model_item_task.dart';
import '../services/service_logger.dart';
import '../services/service_events.dart';
import '../storage/local_item_access.dart';
import '../storage/managed_file_copies.dart';
import '../storage/remote_file_copies.dart';
import '../storage/archived_sync_folders.dart';
import '../storage/synced_folder_access.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';

enum ItemSelectionAction { deleteLocal, archive, download, reconnect }

/// Source-folder ancestry determines ownership. Filesystem presence only
/// determines what may be done to the source or its downloaded copy.
class ItemSelectionActions extends ChangeNotifier {
  ItemSelectionActions(this.selection) {
    selection.addListener(_selectionChanged);
    _completedTransfers = EventStream().events.listen((event) {
      if (event.type == EventType.system &&
          event.key == EventKey.removed &&
          selection.value.any((item) => item.id == event.id)) {
        unawaited(refresh());
      }
    });
  }

  final ValueListenable<Set<ModelItem>> selection;
  final _logger = AppLogger(prefixes: ['SelectionActions']);
  Set<ItemSelectionAction> _available = {};
  int _revision = 0;
  int _selectionRevision = 0;
  bool _disposed = false;
  bool _busy = false;
  late final StreamSubscription<AppEvent> _completedTransfers;

  bool allows(ItemSelectionAction action) => _available.contains(action);

  void _selectionChanged() {
    _selectionRevision++;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final revision = ++_revision;
    _available = {};
    if (_disposed) return;
    notifyListeners();
    final items = selection.value.toList();
    if (items.isEmpty || _busy) return;
    try {
      final states = await Future.wait(items.map((item) => _inspect(item.id)));
      if (_disposed || revision != _revision) return;
      _available = ItemSelectionAction.values
          .where((action) => states.every((state) => state.contains(action)))
          .toSet();
      if (items.length != 1) _available.remove(ItemSelectionAction.reconnect);
      notifyListeners();
    } catch (error, stack) {
      _logger.error('Could not check selected items',
          error: error, stackTrace: stack);
    }
  }

  /// Validate the entire selection again, then keep access held while checking
  /// and acting on each current row. A stale toolbar callback grants no rights.
  Future<bool> perform(ItemSelectionAction action) async {
    if (action == ItemSelectionAction.reconnect) return false;
    if (_disposed || _busy) return false;
    final ids = selection.value.map((item) => item.id).toList();
    if (ids.isEmpty) return false;
    final selectionRevision = _selectionRevision;
    _busy = true;
    await refresh();
    try {
      final states = await Future.wait(ids.map(_inspect));
      if (_disposed ||
          selectionRevision != _selectionRevision ||
          states.any((state) => !state.contains(action))) {
        return false;
      }
      for (final id in ids) {
        if (_disposed || selectionRevision != _selectionRevision) return false;
        final applied =
            await _withItem(id, (item, itemPath, actions, managed) async {
          if (!actions.contains(action)) return false;
          switch (action) {
            case ItemSelectionAction.archive:
              item.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
              if (item.isFolder) {
                await StorageSqlite.instance.runInTransaction(() async {
                  final root = await ManagedFileCopies.localRoot(item.id);
                  if (root == null) throw StateError('Archive root changed');
                  await ManagedFileCopies.prepareFolderCleanup(item);
                  await ArchivedSyncFolders.mark(item, root);
                  await item.update(['archived_at']);
                });
                await ManagedFileCopies.finishRootCleanup(item.id);
              } else {
                await item.update(['archived_at']);
              }
            case ItemSelectionAction.deleteLocal:
              // Cache deletion must remain confined to app-managed storage,
              // even if source-folder metadata changes during an async read.
              final cacheRoot = await ModelItem.getPathForItem('fife');
              if (!path.isWithin(
                  path.normalize(cacheRoot), path.normalize(itemPath))) {
                return false;
              }
              await RemoteFileCopies.deleteLocal(item, itemPath);
            case ItemSelectionAction.download:
              if (managed) {
                await ManagedFileCopies.requestTree(item);
              } else {
                await ManagedFileCopies.useSourceForDownload(item.id);
                await RemoteFileCopies.request(item.id);
                await ModelItemTask.addTask(item.id, ItemTask.download.value);
              }
            case ItemSelectionAction.reconnect:
              return false;
          }
          return true;
        }, false);
        if (!applied) return false;
      }
      return true;
    } catch (error, stack) {
      _logger.error('Selected item action failed',
          error: error, stackTrace: stack);
      return false;
    } finally {
      _busy = false;
      if (!_disposed) unawaited(refresh());
    }
  }

  Future<ModelItem?> reconnect() async {
    if (_disposed || _busy || selection.value.length != 1) return null;
    final id = selection.value.single.id;
    final revision = _selectionRevision;
    _busy = true;
    await refresh();
    try {
      final actions = await _inspect(id);
      if (_disposed ||
          revision != _selectionRevision ||
          !actions.contains(ItemSelectionAction.reconnect)) {
        return null;
      }
      final item = await ModelItem.get(id);
      if (item == null) return null;
      return await SyncedFolderAccess.reselect(item);
    } finally {
      _busy = false;
      if (!_disposed) unawaited(refresh());
    }
  }

  static Future<Set<ItemSelectionAction>> _inspect(String id) => _withItem(
      id, (_, __, actions, ___) async => actions, <ItemSelectionAction>{});

  static Future<T> _withItem<T>(
      String id,
      Future<T> Function(ModelItem, String, Set<ItemSelectionAction>, bool)
          body,
      T unavailable) async {
    try {
      final item = await ModelItem.get(id);
      // Device roots and archived/deleted rows are not actionable file items.
      if (item == null ||
          item.parentId == null ||
          item.parentId == 'fife' ||
          item.archivedAt != 0) {
        return unavailable;
      }
      final ancestry = await ModelItem.getPathRowsForItem(id);
      final device = await getDeviceHash();
      final isLocal = ancestry.any((row) => row['id'] == device);
      if (await ManagedFileCopies.hasArchivedAncestor(id)) return unavailable;
      final root = isLocal ? await ManagedFileCopies.localRoot(id) : null;
      final disconnected = root != null &&
              (Platform.isIOS || Platform.isMacOS) &&
              !await SyncedFolderAccess.isAvailable(root)
          ? root
          : null;
      if (disconnected != null) {
        final currentAncestry = await ModelItem.getPathRowsForItem(id);
        final currentItem = await ModelItem.get(id);
        if (currentItem == null ||
            currentItem.archivedAt != 0 ||
            ancestry.length != currentAncestry.length ||
            !Iterable.generate(ancestry.length)
                .every((i) => mapEquals(ancestry[i], currentAncestry[i]))) {
          return unavailable;
        }
        final isRoot = currentItem.id == disconnected.id;
        return body(
            currentItem,
            '',
            {
              if (isRoot) ItemSelectionAction.reconnect,
              if (currentItem.isFolder) ItemSelectionAction.archive,
              if (currentItem.isFolder ||
                  (await ManagedFileCopies.hasBackup(currentItem) &&
                      await ManagedFileCopies.existingPath(id) == null))
                ItemSelectionAction.download,
            },
            true);
      }
      return await LocalItemAccess.withAccess(id, (itemPath) async {
        final exists = await (item.isFolder
            ? Directory(itemPath).exists()
            : File(itemPath).exists());
        // A different entity at the same path is not a confirmed absence.
        final missing = !exists &&
            await FileSystemEntity.type(itemPath, followLinks: false) ==
                FileSystemEntityType.notFound;
        final currentAncestry = await ModelItem.getPathRowsForItem(id);
        if (ancestry.length != currentAncestry.length ||
            !Iterable.generate(ancestry.length)
                .every((i) => mapEquals(ancestry[i], currentAncestry[i]))) {
          return unavailable;
        }
        final currentItem = await ModelItem.get(id);
        if (currentItem == null ||
            currentItem.archivedAt != 0 ||
            currentItem.isFolder != item.isFolder) {
          return unavailable;
        }
        final actions = <ItemSelectionAction>{
          if (isLocal && missing) ItemSelectionAction.archive,
          if (!isLocal && exists) ItemSelectionAction.deleteLocal,
          if (!item.isFolder && missing) ItemSelectionAction.download,
        };
        return body(currentItem, itemPath, actions, false);
      });
    } on PlatformException {
      return unavailable;
    } on FileSystemException {
      return unavailable;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _completedTransfers.cancel();
    selection.removeListener(_selectionChanged);
    super.dispose();
  }
}
