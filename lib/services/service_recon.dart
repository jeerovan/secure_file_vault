import 'dart:convert';
import 'dart:io';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';
import '../utils/common.dart';
import 'package:crypto/crypto.dart';
import '../utils/utils_crypto.dart';
import '../utils/utils_file.dart';
import 'package:flutter/foundation.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path_lib;

class ReconciliationService {
  final AppLogger logger = AppLogger(prefixes: ["RECON"]);
  final Uuid uuid;
  static const double jaccardSimilarityThreshold = 0.6;

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
    // first delete all files
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
        dbChild.scanState = 1;
        await ModelItem.setScanState(dbChild.id, 1);
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
            await ModelItem.setScanState(dbChild.id, 2);
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
            String dbItemPath = await ModelItem.getPathForItem(movedDbItem.id);
            movedDbItem.name = fsChild.name;
            movedDbItem.parentId = dbParentId;
            movedDbItem.scanState = 2;
            await movedDbItem.update(["name", "parent_id", "scan_state"]);
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

  /// ON-DEMAND GLOBAL SEARCH: Finds a moved/renamed folder in the unresolved set.
  Future<ModelItem?> _findMovedFolder(
      String rootItemId, FSItem fsFolder, String fsPath) async {
    final candidateDbFolders =
        await ModelItem.getAllUnScannedFolderForRootItemId(rootItemId);
    ModelItem? bestMatch;
    double bestScore = 0.0;
    final fsChildrenNames =
        (await _scanFileSystemChildren(fsPath)).map((c) => c.name).toSet();
    // Strategy 1:Folder Move: Find a folder with the same name. It's the strongest signal.
    final sameNameCandidates =
        candidateDbFolders.where((f) => f.name == fsFolder.name).toList();
    if (sameNameCandidates.isNotEmpty) {
      for (final candidate in sameNameCandidates) {
        final dbChildrenNames = (await ModelItem.getAllInFolder(candidate))
            .map((c) => c.name)
            .toSet();
        final score =
            _calculateJaccardSimilarity(fsChildrenNames, dbChildrenNames);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
      }
      if (bestMatch != null) {
        String directoryPath = await ModelItem.getPathForItem(bestMatch.id);
        bool directoryExist = await directoryExistAtPath(directoryPath);
        if (!directoryExist) {
          return bestMatch;
        }
      }
    }

    // Strategy 2:Folder Rename: If no name match, check content similarity against all other unresolved folders.
    for (final candidate in candidateDbFolders) {
      final dbChildrenNames = (await ModelItem.getAllInFolder(candidate))
          .map((c) => c.name)
          .toSet();
      final score =
          _calculateJaccardSimilarity(fsChildrenNames, dbChildrenNames);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = candidate;
      }
    }
    if (bestScore >= jaccardSimilarityThreshold && bestMatch != null) {
      String directoryPath = await ModelItem.getPathForItem(bestMatch.id);
      bool directoryExist = await directoryExistAtPath(directoryPath);
      if (!directoryExist) {
        return bestMatch;
      }
    }
    return null;
  }

  // ON-DEMAND GLOBAL SEARCH: Finds a moved file.
  Future<ModelItem?> _findMovedFile(
      String rootItemId, FSItem fsFile, String fsPath) async {
    final hash = await _computeFileHash(fsPath);
    // first search matching files with name and size
    final dbCandidatesMatchingNameSize =
        await ModelItem.getAllUnScannedFilesForRootItemIdMatchingNameAndSize(
            rootItemId, fsFile.name, fsFile.size!);
    // match hash to confirm
    if (dbCandidatesMatchingNameSize.isNotEmpty) {
      for (final candidate in dbCandidatesMatchingNameSize) {
        if (candidate.fileId == hash) {
          String filePath = await ModelItem.getPathForItem(candidate.id);
          bool fileExist = await fileExistAtPath(filePath);
          if (!fileExist) return candidate;
        }
      }
    }
    // Search the entire unresolved map for a matching hash.
    final dbCandidatesMatchingHash =
        await ModelItem.getAllUnScannedFilesForRootItemIdMatchingHash(
            rootItemId, hash);
    if (dbCandidatesMatchingHash.isNotEmpty) {
      ModelItem candidate = dbCandidatesMatchingHash[0];
      String filePath = await ModelItem.getPathForItem(candidate.id);
      bool fileExist = await fileExistAtPath(filePath);
      if (!fileExist) return candidate;
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
    final fsChildrenNames =
        (await _scanFileSystemChildren(fsPath)).map((c) => c.name).toSet();
    final dbChildrenFolders =
        dbChildren.where((c) => c.isFolder && c.scanState == 0).toList();

    ModelItem? bestMatch;
    double bestScore = 0.0;

    for (final dbFolder in dbChildrenFolders) {
      final dbChildrenNames =
          (await ModelItem.getAllInFolder(dbFolder)).map((c) => c.name).toSet();
      final score =
          _calculateJaccardSimilarity(fsChildrenNames, dbChildrenNames);

      if (score > bestScore) {
        bestScore = score;
        bestMatch = dbFolder;
      }
    }
    bool matched = false;
    if (bestMatch != null && bestScore >= jaccardSimilarityThreshold) {
      matched = true;
      bestMatch.name = fsItem.name;
      bestMatch.scanState = 2;
      await bestMatch.update(["name", "scan_state"]);
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
      await matchedDbFile.update(["name", "scan_state"]);
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
    String? mime = await getFileMime(fsPath);
    FileSplitter fileSplitter = FileSplitter(File(fsPath));
    int parts = fileSplitter.partSizes.length;
    final modelFile = await ModelFile.fromMap(
        {'id': newHash, 'mime': mime ?? "", 'parts': parts});
    await modelFile.insert();
    dbItem.fileId = newHash;
    dbItem.size = fsItem.size!;
    await dbItem.update(["file_id", "size"]);
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
    if (hashFile == null) {
      String? mime = await getFileMime(fsPath);
      FileSplitter fileSplitter = FileSplitter(File(fsPath));
      int parts = fileSplitter.partSizes.length;
      final modelFile = await ModelFile.fromMap(
          {'id': hash, 'mime': mime ?? "", 'parts': parts});
      await modelFile.insert();
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

  Future<void> _handleDeletion(ModelItem dbItem) async {
    if (dbItem.isFolder) {
      await dbItem.delete();
      logger.info('  - Deleted Folder: ${dbItem.name}');
    } else {
      if (dbItem.fileId != null) {
        await ModelFile.updateItemCount(dbItem.fileId!, false);
      }
      await dbItem.delete();
      logger.info('  - Deleted File: ${dbItem.name}');
    }

    // TODO Decrement content reference count if it's a file
  }

  // --- Helpers ---

  double _calculateJaccardSimilarity(Set<String> set1, Set<String> set2) {
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
    // 1. Create the HMAC using SHA-256 and your secret key
    var hmac = Hmac(sha256, base64Decode(masterKey!));
    // 2. Pass the file bytes (content) to the HMAC
    var digest = hmac.convert(await File(path).readAsBytes());
    // 3. Return the hexadecimal string representation
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
