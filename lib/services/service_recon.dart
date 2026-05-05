import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/storage/storage_channel.dart';

import '../utils/enums.dart';

import '../models/model_file.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';
import '../utils/common.dart';
import '../utils/utils_file.dart';
import 'package:path/path.dart' as path_lib;
import 'package:uuid/uuid.dart';
import 'package:sodium/sodium_sumo.dart';

class ReconciliationService {
  final AppLogger logger = AppLogger(prefixes: ["RECON"]);
  final Uuid uuid;
  static const double jaccardSimilarityThreshold = 0.7;
  final SodiumSumo _sodium;
  ReconciliationService(this._sodium) : uuid = const Uuid();

  /// Main entry point: reconcile a root synced folder
  Future<void> reconcile(String rootItemId) async {
    final rootItem = await ModelItem.get(rootItemId);
    if (rootItem == null) return;
    // initialize scan
    await ModelItem.resetScanState(rootItemId);
    //time to calculate hashes
    final stopwatch = Stopwatch()..start();
    String? directoryPath = rootItem.path;
    logger.info("Directory Path: $directoryPath");
    String? bookmark;
    if (Platform.isIOS) {
      bookmark = rootItem.bookmark;
      if (bookmark != null) {
        String? accessPath = await ChannelStorage.startAccessing(bookmark);
        if (accessPath != null) {
          directoryPath = accessPath;
          logger.info("iOS Path: $directoryPath");
        }
      }
    }
    if (directoryPath == null) {
      return;
    }
    Map<String, String> fileHashes = await _computeFileHashes(directoryPath);

    logger.debug("fileHashes: $fileHashes");
    stopwatch.stop();
    final secondsTaken = stopwatch.elapsedMilliseconds / 1000.0;
    logger
        .info('Computed ${fileHashes.length} hashes in $secondsTaken seconds');
    await _reconcileNode(
        rootItemId: rootItemId,
        dbParentId: rootItemId,
        fsPath: directoryPath,
        hashes: fileHashes);
    if (Platform.isIOS && bookmark != null) {
      await ChannelStorage.stopAccessing(bookmark);
    }
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
    required Map<String, String> hashes,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    //logger.info('📁 Reconciling: $fsPath');

    // 1. Get current state from File System and Database
    final fsChildren = await _scanFileSystemChildren(fsPath);
    //logger.debug("fsChildren:$fsChildren");
    ModelItem? dbParent = await ModelItem.get(dbParentId);
    final dbChildren = await ModelItem.getAllInFolder(dbParent);
    //logger.debug("dbChildren:$dbChildren");

    final dbChildrenByName = <String, List<ModelItem>>{};
    for (var c in dbChildren) {
      dbChildrenByName.putIfAbsent(c.name, () => []).add(c);
    }

    //2. Find directly matched and modified items
    for (final fsChild in fsChildren) {
      final dbChildItems = dbChildrenByName[fsChild.name];
      ModelItem? dbChild;
      if (dbChildItems != null && dbChildItems.isNotEmpty) {
        final validCandidates = dbChildItems
            .where((item) =>
                item.isFolder == fsChild.isFolder && item.scanState == 0)
            .toList();

        if (validCandidates.isNotEmpty) {
          // 2. The first item is our active matched DB child
          dbChild = validCandidates.first;

          // 3. Any remaining valid candidates are guaranteed duplicates
          if (validCandidates.length > 1) {
            final duplicates = validCandidates.skip(1);

            for (final duplicate in duplicates) {
              logger.info(
                  '🗑️ Removing duplicate DB item: ${duplicate.name} (${duplicate.id})');
              await duplicate.remove();
            }
          }
        }
      }
      final childPath = path_lib.join(fsPath, fsChild.name);
      if (dbChild != null) {
        // Item with same name exists in DB under the same parent
        await ModelItem.setScanState(dbChild.id, ScanState.exists.value);
        if (fsChild.isFolder) {
          // Recurse into matched folder
          await _reconcileNode(
              rootItemId: rootItemId,
              dbParentId: dbChild.id,
              fsPath: childPath,
              hashes: hashes);
        } else {
          // Check if the file was modified based on hash
          if (hashes.containsKey(childPath)) {
            String fsHash = hashes[childPath]!;
            bool fileModified = dbChild.fileHash != fsHash;

            if (fileModified) {
              await ModelItem.setScanState(
                  dbChild.id, ScanState.modified.value);
              await _handleModifiedFile(
                  dbChild, fsChild, childPath, fsHash, timestamp);
            } else {
              await checkCreateUploadTask(dbChild.id, fsPath, fsHash);
            }
          }
        }
      } else {
        // 3. No direct match by name, could be renamed / moved or new item
        bool renamed = false;
        //3.a check if item was renamed
        if (fsChild.isFolder) {
          renamed = await _handleRenamedFolder(
              rootItemId, fsChild, dbChildren, childPath, hashes);
        } else {
          if (hashes.containsKey(childPath)) {
            String fsHash = hashes[childPath]!;
            renamed = await _handleRenamedFile(
                rootItemId, fsChild, dbChildren, childPath, fsHash);
          }
        }
        if (renamed) {
          logger.info("  ~ Renamed: $childPath");
        } else {
          ModelItem? movedDbItem;
          if (fsChild.isFolder) {
            movedDbItem =
                await _findMovedFolder(rootItemId, fsChild, childPath);
          } else {
            if (hashes.containsKey(childPath)) {
              String fsHash = hashes[childPath]!;
              movedDbItem =
                  await _findMovedFile(rootItemId, fsChild, childPath, fsHash);
            }
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
                  fsPath: childPath,
                  hashes: hashes);
            }
          } else {
            // 4. Create NEW ITEM
            // No move was detected, so this is a genuinely new item.
            if (fsChild.isFolder) {
              await _handleFolderCreation(
                  rootItemId, fsChild, dbParentId, childPath, hashes);
            } else {
              if (hashes.containsKey(childPath)) {
                String fsHash = hashes[childPath]!;
                await _handleFileCreation(
                    rootItemId, fsChild, dbParentId, childPath, fsHash);
              }
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
    final fsSizes = fsChildren.map((c) => c.size ?? 0).toList();
    final fsSizeFrequency = _generateSizeFrequency(fsSizes);
    final candidateDbFolders =
        await ModelItem.getAllUnScannedFolderForRootItemId(rootItemId);
    ModelItem? bestMatch;
    double bestScore = 0.0;
    for (final candidate in candidateDbFolders) {
      // Fetch children once
      final dbChildren = await ModelItem.getAllInFolder(candidate);
      final dbSizes = dbChildren.map((c) => c.size).toList();
      final dbSizeFrequency = _generateSizeFrequency(dbSizes);
      // If the folder is massive, checking name similarity is cheap.

      // Score 1: Name Match (Strongest signal)
      if (candidate.name == fsFolder.name) {
        if (fsSizes.isEmpty && dbSizes.isEmpty) {
          return candidate;
        }
        double score =
            _calculateJaccardSimilarity(fsSizeFrequency, dbSizeFrequency);
        if (score > 0.3 && score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
        continue;
      }

      // If names DO NOT match, do not attempt to match empty folders
      // or folders containing only empty subdirectories
      if (fsSizes.isEmpty ||
          dbSizes.isEmpty ||
          (fsSizes.every((s) => s == 0))) {
        continue;
      }

      // Score 2: Content Match
      double score =
          _calculateJaccardSimilarity(fsSizeFrequency, dbSizeFrequency);

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
      String rootItemId, FSItem fsFile, String fsPath, String fsHash) async {
    // first search matching files with size
    final dbCandidatesMatchingSize =
        await ModelItem.getAllUnScannedFilesForRootItemIdMatchingSize(
            rootItemId, fsFile.size!);
    if (dbCandidatesMatchingSize.isEmpty) {
      return null;
    }
    // match hash to confirm
    for (final candidate in dbCandidatesMatchingSize) {
      if (candidate.fileHash == fsHash) {
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
      Map<String, String> hashses) async {
    final fsChildren = await _scanFileSystemChildren(fsPath);
    final fsSizes = fsChildren.map((c) => c.size ?? 0).toList();
    final fsSizeFrequency = _generateSizeFrequency(fsSizes);
    final dbChildrenFolders =
        dbChildren.where((c) => c.isFolder && c.scanState == 0).toList();

    ModelItem? bestMatch;
    double bestScore = 0.0;

    for (final dbFolder in dbChildrenFolders) {
      final dbChildren = await ModelItem.getAllInFolder(dbFolder);
      final dbSizes = dbChildren.map((c) => c.size).toList();
      // Skip renaming detection for purely empty folders or subfolder-only trees
      if (fsSizes.isEmpty && dbSizes.isEmpty) continue;
      final dbSizeFrequency = _generateSizeFrequency(dbSizes);
      final score =
          _calculateJaccardSimilarity(fsSizeFrequency, dbSizeFrequency);

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
          hashes: hashses);
    }
    return matched;
  }

  /// Detects moved files using size, mtime, and finally hash
  Future<bool> _handleRenamedFile(
    String rootItemId,
    FSItem fsFile,
    List<ModelItem> dbChildren,
    String fsPath,
    String fsHash,
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
    ModelItem? matchedDbItem;

    if (candidates.isNotEmpty) {
      for (final candidate in candidates) {
        if (candidate.fileHash == fsHash) {
          matchedDbItem = candidate;
          break;
        }
      }
    }
    bool matched = false;
    if (matchedDbItem != null) {
      matched = true;
      matchedDbItem.name = fsFile.name;
      matchedDbItem.scanState = 2;
      matchedDbItem.archivedAt = 0;
      await matchedDbItem.update(["name", "scan_state", "archived_at"]);
    }
    return matched;
  }

  // --- Change Handlers ---

  Future<void> _handleModifiedFile(ModelItem dbItem, FSItem fsItem,
      String fsPath, String fsHash, int timestamp) async {
    // old file hash
    String oldFileHash = dbItem.fileHash!;

    // update item
    dbItem.fileHash = fsHash;
    dbItem.size = fsItem.size!;
    dbItem.archivedAt = 0;
    await dbItem.update(["file_hash", "size", "archived_at"]);

    // update item count on oldfile
    ModelFile? oldModelFile = await ModelFile.get(oldFileHash);
    if (oldModelFile != null) {
      int newItemCount = await ModelItem.getItemCountForFileHash(oldFileHash);
      await oldModelFile.updateCount(newItemCount);
    }

    await checkCreateUploadTask(dbItem.id, fsPath, fsHash);
    logger.info('  ~ Modified: ${fsItem.name}');
  }

  Future<void> _handleFileCreation(
    String rootItemId,
    FSItem fsItem,
    String parentId,
    String fsPath,
    String fsHash,
  ) async {
    final modelItem = await ModelItem.fromMap({
      'root_id': rootItemId,
      'parent_id': parentId,
      'is_folder': 0,
      'name': fsItem.name,
      'file_hash': fsHash,
      'size': fsItem.size,
      'scan_state': 1,
    });
    await modelItem.insert();
    String itemId = modelItem.id;

    await checkCreateUploadTask(itemId, fsPath, fsHash);
    logger.info('  + Created File: ${fsItem.name}');
  }

  Future<void> _handleFolderCreation(String rootItemId, FSItem fsItem,
      String parentId, String fsPath, Map<String, String> hashses) async {
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
        rootItemId: rootItemId,
        dbParentId: itemId,
        fsPath: fsPath,
        hashes: hashses);
  }

  Future<void> _handleDeletion(ModelItem item) async {
    if (item.isFolder) {
      // Only empty folders are deleted.
      await item.delete();
      logger.info('  - Deleted Folder: ${item.name}');
    } else {
      // Do not delete if already uploaded
      ModelFile? modelFile = await ModelFile.get(item.fileHash!);
      if (modelFile == null || modelFile.uploadedAt == 0) {
        // check if not uploading
        ModelItemTask? uploadTask = await ModelItemTask.get(item.id);
        if (uploadTask == null) {
          await item.remove();
          logger.info('  - Deleted File: ${item.name}');
        }
      }
    }
  }

  // For a newly created item
  Future<void> checkCreateUploadTask(
      String newItemId, String fsPath, String hash) async {
    ModelFile? hashFile = await ModelFile.get(hash);
    bool createUploadTask = false;
    if (hashFile == null) {
      FileSplitter fileSplitter = FileSplitter(file: File(fsPath));
      int parts = fileSplitter.partSizes.length;
      final modelFile = await ModelFile.fromMap({'id': hash, 'parts': parts});
      await modelFile.insert();
      createUploadTask = true;
    } else {
      // update count and check uploadedAt
      int count = await ModelItem.getItemCountForFileHash(hash);
      if (hashFile.itemCount != count) {
        await hashFile.updateCount(count);
      }
      if (hashFile.uploadedAt == 0) {
        createUploadTask = true;
      }
    }
    if (createUploadTask) {
      await ModelItemTask.addTask(newItemId, ItemTask.upload.value);
    }
  }

  // --- Helpers ---
  Map<int, int> _generateSizeFrequency(Iterable<int> sizes) {
    final map = <int, int>{};
    for (final size in sizes) {
      map[size] = (map[size] ?? 0) + 1;
    }
    return map;
  }

  double _calculateJaccardSimilarity(Map<int, int> freq1, Map<int, int> freq2) {
    if (freq1.isEmpty && freq2.isEmpty) {
      return 0.0; // Do not default empty matches to 1.0
    }

    int intersection = 0;
    int union = 0;

    final allKeys = {...freq1.keys, ...freq2.keys};
    for (final key in allKeys) {
      final count1 = freq1[key] ?? 0;
      final count2 = freq2[key] ?? 0;

      // Minimum count is the intersection, Maximum count is the union
      intersection += count1 < count2 ? count1 : count2;
      union += count1 > count2 ? count1 : count2;
    }

    return union == 0 ? 0.0 : intersection / union;
  }

  Future<Map<String, String>> _computeFileHashes(String directoryPath) async {
    String? fileHashKey = await getFileHashKey();
    if (fileHashKey == null) throw Exception("Key missing");

    final keyBytes = base64Decode(fileHashKey);
    final secureKey = _sodium.secureCopy(keyBytes);

    try {
      // Spawn exactly ONE isolate for the entire directory.
      // The directoryPath string is automatically captured by the isolate closure.
      return await _sodium.runIsolated<Map<String, String>>(
        (List<SecureKey> isolatedSecureKeys, List<KeyPair> _) async {
          final isolateSecureKey = isolatedSecureKeys.first;
          final dir = Directory(directoryPath);
          final resultMap = <String, String>{};

          if (!await dir.exists()) {
            return resultMap; // Return empty if directory is missing
          }

          // Recursively traverse directory.
          // followLinks: false prevents infinite loops from symlinks.
          await for (final entity
              in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final path = entity.path;

              try {
                final fileSize = await entity.length();
                Uint8List digest;

                if (fileSize < 10 * 1024 * 1024) {
                  // Fast path (< 10 MB)
                  final bytes = await entity.readAsBytes();
                  digest = _sodium.crypto.genericHash(
                    message: bytes,
                    key: isolateSecureKey,
                    outLen: _sodium.crypto.genericHash.bytes,
                  );
                } else {
                  // Memory-safe stream path (>= 10 MB)
                  final hashConsumer =
                      _sodium.crypto.genericHash.createConsumer(
                    key: isolateSecureKey,
                    outLen: _sodium.crypto.genericHash.bytes,
                  );

                  final byteStream = entity.openRead().map((chunk) =>
                      chunk is Uint8List ? chunk : Uint8List.fromList(chunk));

                  await byteStream.pipe(hashConsumer);
                  digest = await hashConsumer.hash;
                }

                resultMap[path] = base64UrlEncode(digest).replaceAll('=', '');
              } catch (e) {
                // If a single file fails (e.g., OS permission denied, file locked),
                // skip it so the rest of the directory can successfully sync.
                // In a production app, you might want to log this via a SendPort.
                //print('Failed to hash file: $path - $e');
              }
            }
          }

          return resultMap;
        },
        secureKeys: [secureKey],
      );
    } finally {
      // Dispose the key on the main thread to prevent memory leaks
      secureKey.dispose();
    }
  }

  // --- Data Loading ---

  Future<List<FSItem>> _scanFileSystemChildren(String dirPath) async {
    final children = <FSItem>[];
    final dir = Directory(dirPath);

    if (!await dir.exists()) return children;

    await for (var entity in dir.list(recursive: false, followLinks: false)) {
      try {
        final name = path_lib.basename(entity.path);
        final stats = await entity.stat();
        final isFolder = entity is Directory;

        children.add(FSItem(
          name: name.trim(),
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
  @override
  String toString() {
    return name;
  }
}
