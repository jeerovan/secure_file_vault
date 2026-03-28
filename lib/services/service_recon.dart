import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:file_vault_bb/models/model_item_task.dart';

import '../utils/enums.dart';

import '../models/model_file.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';
import '../utils/common.dart';
import 'package:crypto/crypto.dart';
import '../utils/utils_file.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path_lib;

class ReconciliationService {
  final AppLogger logger = AppLogger(prefixes: ["RECON"]);
  final Uuid uuid;
  static const double jaccardSimilarityThreshold = 0.7;

  ReconciliationService() : uuid = Uuid();

  /// Main entry point: reconcile a root synced folder
  Future<void> reconcile(String rootItemId) async {
    final rootItem = await ModelItem.get(rootItemId);
    if (rootItem == null) return;
    // initialize scan
    await ModelItem.resetScanState(rootItemId);
    await _reconcileNode(
      rootItemId: rootItemId,
      dbParentId: rootItemId,
      fsPath: rootItem.path!,
    );

    // Mark remaining DB items as deleted
    final remainingDbItems =
        await ModelItem.getAllUnScannedItemsForRootItemId(rootItemId);
    // first delete all files if they are not uploaded yet
    for (final dbChild in remainingDbItems) {
      if (!dbChild.isFolder) {
        await _handleDeletion(dbChild);
      }
    }
    // delete folders if they do not have any files
    for (final dbChild in remainingDbItems) {
      if (dbChild.isFolder) {
        final folderItems = await ModelItem.getAllInFolder(dbChild);
        if (folderItems.isEmpty) {
          await _handleDeletion(dbChild);
        }
      }
    }
  }

  /// Recursively reconcile a single node (folder) in the hierarchy
  Future<void> _reconcileNode({
    required String rootItemId,
    required String dbParentId,
    required String fsPath,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    logger.info('📁 Reconciling: $fsPath');

    // 1. Get current state from File System and Database
    final fsChildren = await _scanFileSystemChildren(fsPath);

    ModelItem? dbParent = await ModelItem.get(dbParentId);
    final dbChildren = await ModelItem.getAllInFolder(dbParent);

    final dbChildrenByName = {for (var c in dbChildren) c.name: c};

    //2. Find directly matched and modified items
    for (final fsChild in fsChildren) {
      final dbChildItem = dbChildrenByName[fsChild.name];
      ModelItem? dbChild;
      if (dbChildItem?.isFolder == fsChild.isFolder &&
          dbChildItem?.scanState == 0) {
        dbChild = dbChildItem;
      }
      final childPath = path_lib.join(fsPath, fsChild.name);
      if (dbChild != null) {
        // Item with same name exists in DB under the same parent
        dbChild.scanState = ScanState.exists.value;
        await ModelItem.setScanState(dbChild.id, ScanState.exists.value);
        if (fsChild.isFolder) {
          // Recurse into matched folder
          await _reconcileNode(
            rootItemId: rootItemId,
            dbParentId: dbChild.id,
            fsPath: childPath,
          );
        } else {
          // Check if the file was modified based on hash
          bool fileModified = await _isFileModified(childPath, dbChild);
          if (fileModified) {
            await ModelItem.setScanState(dbChild.id, ScanState.modified.value);
            await _handleModifiedFile(dbChild, fsChild, childPath, timestamp);
          }
        }
      } else {
        // 3. No direct match by name, could be renamed / moved or new item
        bool renamed = false;
        //3.a check if item was renamed
        if (fsChild.isFolder) {
          renamed = await _handleRenamedFolder(
              rootItemId, fsChild, dbChildren, childPath);
        } else {
          renamed = await _handleRenamedFile(
              rootItemId, fsChild, dbChildren, childPath);
        }
        if (renamed) {
          logger.info("  ~ Renamed: $childPath");
        } else {
          ModelItem? movedDbItem;
          if (fsChild.isFolder) {
            movedDbItem =
                await _findMovedFolder(rootItemId, fsChild, childPath);
          } else {
            movedDbItem = await _findMovedFile(rootItemId, fsChild, childPath);
          }

          if (movedDbItem != null) {
            // --- MOVE DETECTED ---
            String dbItemPath =
                await ModelItem.getPathForLocalItem(movedDbItem.id);
            movedDbItem.name = fsChild.name;
            movedDbItem.parentId = dbParentId;
            movedDbItem.scanState = ScanState.modified.value;
            movedDbItem.archivedAt = 0;
            await movedDbItem
                .update(["name", "parent_id", "scan_state", "archived_at"]);
            logger.info("  ~ Moved: $dbItemPath to $childPath");
            if (fsChild.isFolder) {
              await _reconcileNode(
                  rootItemId: rootItemId,
                  dbParentId: movedDbItem.id,
                  fsPath: childPath);
            }
          } else {
            // 4. Create NEW ITEM
            // No move was detected, so this is a genuinely new item.
            if (fsChild.isFolder) {
              await _handleFolderCreation(
                  rootItemId, fsChild, dbParentId, childPath);
            } else {
              await _handleFileCreation(
                  rootItemId, fsChild, dbParentId, childPath);
            }
          }
        }
      }
    }
  }

  /// ON-DEMAND GLOBAL SEARCH: Finds a moved/renamed folder in the unresolved set. A moved directory in db will not exist at its fsPath.
  Future<ModelItem?> _findMovedFolder(
      String rootItemId, FSItem fsFolder, String fsPath) async {
    final fsChildren = await _scanFileSystemChildren(fsPath);
    final fsSizes = fsChildren.map((c) => c.size ?? 0).toSet();
    final candidateDbFolders =
        await ModelItem.getAllUnScannedFolderForRootItemId(rootItemId);
    ModelItem? bestMatch;
    double bestScore = 0.0;
    for (final candidate in candidateDbFolders) {
      // Fetch children once
      final dbChildren = await ModelItem.getAllInFolder(candidate);

      // If the folder is massive, checking name similarity is cheap.

      // Score 1: Name Match (Strongest signal)
      if (candidate.name == fsFolder.name) {
        // Lower the threshold if the folder name is identical.
        // Even a small content overlap indicates a move if the name is same.
        double score = _calculateJaccardSimilarity(
            fsSizes, dbChildren.map((c) => c.size).toSet());
        if (score > 0.3 && score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
        continue;
      }

      // Score 2: Content Match
      final dbSizes = dbChildren.map((c) => c.size).toSet();
      double score = _calculateJaccardSimilarity(fsSizes, dbSizes);

      if (score > bestScore) {
        bestScore = score;
        bestMatch = candidate;
      }
    }

    if (bestMatch != null && bestScore > jaccardSimilarityThreshold) {
      String directoryPath = await ModelItem.getPathForLocalItem(bestMatch.id);
      bool directoryExist = await directoryExistAtPath(directoryPath);
      if (!directoryExist) {
        return bestMatch;
      }
    }
    return null;
  }

  // ON-DEMAND GLOBAL SEARCH: Finds a moved file. A moved file in db will not be available at its fsPath.
  Future<ModelItem?> _findMovedFile(
      String rootItemId, FSItem fsFile, String fsPath) async {
    // first search matching files with size
    final dbCandidatesMatchingSize =
        await ModelItem.getAllUnScannedFilesForRootItemIdMatchingSize(
            rootItemId, fsFile.size!);
    if (dbCandidatesMatchingSize.isEmpty) {
      return null;
    }
    final hash = await _computeFileHash(fsPath);
    // match hash to confirm
    for (final candidate in dbCandidatesMatchingSize) {
      if (candidate.fileId == hash) {
        String filePath = await ModelItem.getPathForLocalItem(candidate.id);
        bool fileExist = await fileExistAtPath(filePath);
        if (!fileExist) return candidate;
      }
    }
    return null;
  }

  /// Detects renamed folders by comparing children sets
  Future<bool> _handleRenamedFolder(
    String rootItemId,
    FSItem fsItem,
    List<ModelItem> dbChildren,
    String fsPath,
  ) async {
    final fsSizes =
        (await _scanFileSystemChildren(fsPath)).map((c) => c.size ?? 0).toSet();
    final dbChildrenFolders =
        dbChildren.where((c) => c.isFolder && c.scanState == 0).toList();

    ModelItem? bestMatch;
    double bestScore = 0.0;

    for (final dbFolder in dbChildrenFolders) {
      final dbSizes =
          (await ModelItem.getAllInFolder(dbFolder)).map((c) => c.size).toSet();
      final score = _calculateJaccardSimilarity(fsSizes, dbSizes);

      if (score > bestScore) {
        bestScore = score;
        bestMatch = dbFolder;
      }
    }
    bool matched = false;
    if (bestMatch != null && bestScore >= jaccardSimilarityThreshold) {
      matched = true;
      bestMatch.name = fsItem.name;
      bestMatch.scanState = ScanState.modified.value;
      bestMatch.archivedAt = 0;
      await bestMatch.update(["name", "scan_state", "archived_at"]);
      // Recurse into the now-matched folder
      await _reconcileNode(
        rootItemId: rootItemId,
        dbParentId: bestMatch.id,
        fsPath: fsPath,
      );
    }
    return matched;
  }

  /// Detects moved files using size, mtime, and finally hash
  Future<bool> _handleRenamedFile(
    String rootItemId,
    FSItem fsFile,
    List<ModelItem> dbChildren,
    String fsPath,
  ) async {
    final unmatchedDbFiles =
        dbChildren.where((c) => !c.isFolder && c.scanState == 0).toList();
    if (unmatchedDbFiles.isEmpty) return false;

    // Group DB files by size for faster lookup
    final dbFilesBySize = <int, List<ModelItem>>{};
    for (var file in unmatchedDbFiles) {
      dbFilesBySize.putIfAbsent(file.size, () => []).add(file);
    }

    final candidates = dbFilesBySize[fsFile.size] ?? [];
    ModelItem? matchedDbFile;

    if (candidates.isNotEmpty) {
      // Compute hash only when needed
      final currentHash = await _computeFileHash(fsPath);
      for (final candidate in candidates) {
        if (candidate.fileId == currentHash) {
          matchedDbFile = candidate;
          break;
        }
      }
    }
    bool matched = false;
    if (matchedDbFile != null) {
      matched = true;
      matchedDbFile.name = fsFile.name;
      matchedDbFile.scanState = 2;
      matchedDbFile.archivedAt = 0;
      await matchedDbFile.update(["name", "scan_state", "archived_at"]);
    }
    return matched;
  }

  // --- Change Handlers ---

  Future<void> _handleModifiedFile(
      ModelItem dbItem, FSItem fsItem, String fsPath, int timestamp) async {
    final newHash = await _computeFileHash(fsPath);
    if (dbItem.fileId == newHash) {
      return; // Only metadata changed, no content change
    }

    // decrement reference count for old file
    await ModelFile.updateItemCount(dbItem.fileId!, false);
    FileSplitter fileSplitter = FileSplitter(file: File(fsPath));
    int parts = fileSplitter.partSizes.length;
    final modelFile = await ModelFile.fromMap({'id': newHash, 'parts': parts});
    await modelFile.insert();
    // create new upload task
    ModelItemTask task =
        await ModelItemTask.fromMap({'id': dbItem.id, 'task': 1});
    await task.insert();
    // update item
    dbItem.fileId = newHash;
    dbItem.size = fsItem.size!;
    dbItem.archivedAt = 0;
    await dbItem.update(["file_id", "size", "archived_at"]);
    logger.info('  ~ Modified: ${fsItem.name}');
  }

  Future<void> _handleFileCreation(
    String rootItemId,
    FSItem fsItem,
    String parentId,
    String fsPath,
  ) async {
    final hash = await _computeFileHash(fsPath);
    final hashFile = await ModelFile.get(hash);
    bool createUploadTask = false;
    if (hashFile == null) {
      FileSplitter fileSplitter = FileSplitter(file: File(fsPath));
      int parts = fileSplitter.partSizes.length;
      final modelFile = await ModelFile.fromMap({'id': hash, 'parts': parts});
      await modelFile.insert();
      createUploadTask = true;
    } else {
      await ModelFile.updateItemCount(hash, true);
    }
    final modelItem = await ModelItem.fromMap({
      'root_id': rootItemId,
      'parent_id': parentId,
      'is_folder': 0,
      'name': fsItem.name,
      'file_id': hash,
      'size': fsItem.size,
      'scan_state': 1,
    });
    await modelItem.insert();
    if (createUploadTask) {
      await ModelItemTask.addTask(modelItem.id, ItemTask.upload.value);
    }
    logger.info('  + Created File: ${fsItem.name}');
  }

  Future<void> _handleFolderCreation(
    String rootItemId,
    FSItem fsItem,
    String parentId,
    String fsPath,
  ) async {
    final itemId = uuid.v4();
    final modelItem = await ModelItem.fromMap({
      'id': itemId,
      'root_id': rootItemId,
      'parent_id': parentId,
      'is_folder': 1,
      'name': fsItem.name,
      'scan_state': 1,
    });
    await modelItem.insert();
    logger.info('  + Created Folder: ${fsItem.name}');

    // Recurse into the newly created folder to process its children
    await _reconcileNode(
        rootItemId: rootItemId, dbParentId: itemId, fsPath: fsPath);
  }

  Future<void> _handleDeletion(ModelItem item) async {
    if (item.isFolder) {
      await item.delete();
      logger.info('  - Deleted Folder: ${item.name}');
    } else {
      if (item.fileId != null) {
        ModelFile? modelFile = await ModelFile.get(item.fileId!);
        if (modelFile != null) {
          if (modelFile.uploadedAt == 0) {
            // if not already uploaded
            // add item delete task
            ModelItemTask task =
                await ModelItemTask.fromMap({'id': item.id, 'task': 3});
            await task.insert();
          }
        }
      }
      logger.info('  - Deleted File: ${item.name}');
    }
  }

  // --- Helpers ---

  double _calculateJaccardSimilarity(Set<int> set1, Set<int> set2) {
    if (set1.isEmpty && set2.isEmpty) return 1.0;
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    return union == 0 ? 0 : intersection / union;
  }

  Future<bool> _isFileModified(String fsPath, ModelItem dbItem) async {
    String fsHash = await _computeFileHash(fsPath);
    return dbItem.fileId != fsHash;
  }

  Future<String> _computeFileHash(String path) async {
    String? masterKey = await getMasterKey();
    if (masterKey == null) throw Exception("Key missing");

    return await Isolate.run(() => _calculateHashInIsolate(path, masterKey));
  }

  static Future<String> _calculateHashInIsolate(String path, String key) async {
    final file = File(path);
    final hmac = Hmac(sha256, base64Decode(key));
    final digest = await hmac.bind(file.openRead()).first;
    return digest.toString();
  }

  // --- Data Loading ---

  Future<List<FSItem>> _scanFileSystemChildren(String dirPath) async {
    final children = <FSItem>[];
    final dir = Directory(dirPath);

    if (!await dir.exists()) return children;

    await for (var entity in dir.list(recursive: false)) {
      try {
        final name = path_lib.basename(entity.path);
        final stats = await entity.stat();
        final isFolder = entity is Directory;

        children.add(FSItem(
          name: name,
          isFolder: isFolder,
          size: isFolder ? 0 : stats.size,
        ));
      } catch (e) {
        logger.info('Error scanning ${entity.path}: $e');
      }
    }

    return children;
  }
}

// --- Data Models ---

class FSItem {
  final String name;
  final bool isFolder;
  final int? size;
  FSItem({
    required this.name,
    required this.isFolder,
    this.size,
  });
}
