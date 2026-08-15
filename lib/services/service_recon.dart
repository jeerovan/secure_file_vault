import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/storage/storage_channel.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';

import '../utils/enums.dart';

import '../models/model_file.dart';
import '../models/model_item.dart';
import '../services/service_logger.dart';
import '../services/service_reconciliation_coordinator.dart';
import '../services/service_reconciliation_planner.dart';
import '../utils/common.dart';
import '../utils/utils_file.dart';
import 'package:path/path.dart' as path_lib;
import 'package:uuid/uuid.dart';
import 'package:sodium/sodium_sumo.dart';

enum ReconciliationStatus { completed, busy, unavailable, partial, failed }

class ReconciliationResult {
  final ReconciliationStatus status;
  final int scannedItems;

  const ReconciliationResult(this.status, {this.scannedItems = 0});

  bool get succeeded => status == ReconciliationStatus.completed;
}

class ReconciliationSourceInspection {
  final ReconciliationStatus status;
  final List<String> relativePaths;

  const ReconciliationSourceInspection(this.status, this.relativePaths);
}

enum _SnapshotStatus { complete, partial, unavailable }

class _FileSystemSnapshot {
  final String rootPath;
  final Map<String, List<FSItem>> childrenByDirectory;
  final Set<String> paths;
  final List<String> filePaths;
  final _SnapshotStatus status;

  const _FileSystemSnapshot({
    required this.rootPath,
    required this.childrenByDirectory,
    required this.paths,
    required this.filePaths,
    required this.status,
  });

  int get itemCount => paths.length;

  List<FSItem> childrenOf(String path) =>
      childrenByDirectory[path] ?? const <FSItem>[];
}

class _HashScanResult {
  final Map<String, String> hashes;
  final bool complete;

  const _HashScanResult(this.hashes, {required this.complete});
}

class ReconciliationService {
  final AppLogger logger = AppLogger(prefixes: ["RECON"]);
  final Uuid uuid;
  final SodiumSumo _sodium;
  ReconciliationService(this._sodium) : uuid = const Uuid();

  static Future<ReconciliationSourceInspection> inspectSource(
      String rootPath) async {
    final snapshot = await _scanFileSystemTree(rootPath);
    final status = switch (snapshot.status) {
      _SnapshotStatus.complete => ReconciliationStatus.completed,
      _SnapshotStatus.partial => ReconciliationStatus.partial,
      _SnapshotStatus.unavailable => ReconciliationStatus.unavailable,
    };
    final relativePaths = snapshot.paths
        .where((path) => path != snapshot.rootPath)
        .map((path) => path_lib.relative(path, from: snapshot.rootPath))
        .toList()
      ..sort();
    return ReconciliationSourceInspection(
      status,
      List.unmodifiable(relativePaths),
    );
  }

  /// Main entry point: reconcile a root synced folder
  Future<ReconciliationResult> reconcile(ModelItem rootItem) async {
    final OperationLease lease;
    try {
      final acquired = await ReconciliationCoordinator.tryAcquire(rootItem.id);
      if (acquired == null) {
        return const ReconciliationResult(ReconciliationStatus.busy);
      }
      lease = acquired;
    } catch (e, s) {
      logger.error('Failed to acquire reconciliation lease',
          error: e, stackTrace: s);
      return const ReconciliationResult(ReconciliationStatus.failed);
    }

    String? acquiredAccessPath;
    OperationLease? metadataLease;
    try {
      String? directoryPath = rootItem.path;
      logger.info("Starting reconciliation scan");

      if (Platform.isIOS || Platform.isMacOS) {
        final bookmark = rootItem.bookmark;
        if (bookmark == null || bookmark.isEmpty) {
          return const ReconciliationResult(ReconciliationStatus.unavailable);
        }
        if (Platform.isIOS) {
          final accessPath = await ChannelStorage.startAccessing(bookmark);
          if (accessPath == null) {
            return const ReconciliationResult(ReconciliationStatus.unavailable);
          }
          acquiredAccessPath = accessPath;
          directoryPath = accessPath;
          logger.info("Platform directory access acquired");
        }
      }
      if (directoryPath == null || directoryPath.isEmpty) {
        return const ReconciliationResult(ReconciliationStatus.unavailable);
      }

      final snapshot = await _scanFileSystemTree(directoryPath);
      if (snapshot.status == _SnapshotStatus.unavailable) {
        return const ReconciliationResult(ReconciliationStatus.unavailable);
      }
      if (snapshot.status == _SnapshotStatus.partial) {
        return ReconciliationResult(
          ReconciliationStatus.partial,
          scannedItems: snapshot.itemCount,
        );
      }

      final stopwatch = Stopwatch()..start();
      final hashResult = await _computeFileHashes(snapshot.filePaths);
      stopwatch.stop();
      if (!hashResult.complete) {
        return ReconciliationResult(
          ReconciliationStatus.partial,
          scannedItems: snapshot.itemCount,
        );
      }
      logger.info(
          'Computed ${hashResult.hashes.length} hashes in ${stopwatch.elapsedMilliseconds / 1000.0} seconds');

      if (!lease.isValid || !await lease.prepareForCommit()) {
        return const ReconciliationResult(ReconciliationStatus.busy);
      }
      metadataLease =
          await ExclusiveOperationCoordinator.tryAcquire('metadata');
      if (metadataLease == null || !await metadataLease.prepareForCommit()) {
        return const ReconciliationResult(ReconciliationStatus.busy);
      }

      await StorageSqlite.instance.runInTransaction(() async {
        await ModelItem.resetScanState(rootItem.id);
        await _reconcileNode(
          rootItemId: rootItem.id,
          dbParentId: rootItem.id,
          fsPath: snapshot.rootPath,
          hashes: hashResult.hashes,
          snapshot: snapshot,
        );

        if (!lease.isValid) {
          throw StateError('Reconciliation lease lost');
        }

        final remainingDbItems =
            await ModelItem.getAllUnScannedItemsForRootItemId(rootItem.id);
        for (final dbChild in remainingDbItems) {
          if (!dbChild.isFolder) await _handleDeletion(dbChild);
        }
        for (final dbChild in remainingDbItems) {
          if (dbChild.isFolder) {
            final folderItems = await ModelItem.getAllInFolder(dbChild);
            if (folderItems.isEmpty) await _handleDeletion(dbChild);
          }
        }
      });
      return ReconciliationResult(
        ReconciliationStatus.completed,
        scannedItems: snapshot.itemCount,
      );
    } catch (e, s) {
      logger.error('Reconciliation failed', error: e, stackTrace: s);
      return const ReconciliationResult(ReconciliationStatus.failed);
    } finally {
      try {
        if (acquiredAccessPath != null) {
          await ChannelStorage.stopAccessing(acquiredAccessPath);
        }
      } catch (e, s) {
        logger.error('Failed to release platform directory access',
            error: e, stackTrace: s);
      }
      try {
        await metadataLease?.release();
      } catch (e, s) {
        logger.error('Failed to release metadata lease',
            error: e, stackTrace: s);
      }
      try {
        await lease.release();
      } catch (e, s) {
        logger.error('Failed to release reconciliation lease',
            error: e, stackTrace: s);
      }
    }
  }

  /// Recursively reconcile a single node (folder) in the hierarchy
  Future<void> _reconcileNode({
    required String rootItemId,
    required String dbParentId,
    required String fsPath,
    required Map<String, String> hashes,
    required _FileSystemSnapshot snapshot,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    //logger.info('📁 Reconciling: $fsPath');

    // 1. Get current state from File System and Database
    final fsChildren = snapshot.childrenOf(fsPath);
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

        if (validCandidates.length == 1) {
          dbChild = validCandidates.single;
        } else if (validCandidates.length > 1) {
          logger.warning('Ambiguous direct match deferred');
          for (final candidate in validCandidates) {
            await ModelItem.setScanState(candidate.id, ScanState.exists.value);
          }
          continue;
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
              hashes: hashes,
              snapshot: snapshot);
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
              await checkCreateUploadTask(dbChild.id, File(childPath), fsHash);
            }
          }
        }
      } else {
        // 3. No direct match by name, could be renamed / moved or new item
        bool renamed = false;
        //3.a check if item was renamed
        if (fsChild.isFolder) {
          renamed = await _handleRenamedFolder(
              rootItemId, fsChild, dbChildren, childPath, hashes, snapshot);
        } else {
          if (hashes.containsKey(childPath)) {
            String fsHash = hashes[childPath]!;
            renamed = await _handleRenamedFile(
                rootItemId, fsChild, dbChildren, childPath, fsHash, snapshot);
          }
        }
        if (renamed) {
          logger.info("Renamed item");
        } else {
          ModelItem? movedDbItem;
          if (fsChild.isFolder) {
            movedDbItem = await _findMovedFolder(
                rootItemId, fsChild, childPath, snapshot, hashes);
          } else {
            if (hashes.containsKey(childPath)) {
              String fsHash = hashes[childPath]!;
              movedDbItem = await _findMovedFile(
                  rootItemId, fsChild, childPath, fsHash, snapshot);
            }
          }

          if (movedDbItem != null &&
              await ModelItem.wouldCreateCycle(movedDbItem.id, dbParentId)) {
            logger.warning('Rejected move that would create a cycle');
            movedDbItem = null;
          }

          if (movedDbItem != null) {
            // --- MOVE DETECTED ---
            movedDbItem.name = fsChild.name;
            movedDbItem.parentId = dbParentId;
            movedDbItem.scanState = ScanState.modified.value;
            movedDbItem.archivedAt = 0;
            await movedDbItem
                .update(["name", "parent_id", "scan_state", "archived_at"]);
            logger.info("Moved item");
            if (fsChild.isFolder) {
              await _reconcileNode(
                  rootItemId: rootItemId,
                  dbParentId: movedDbItem.id,
                  fsPath: childPath,
                  hashes: hashes,
                  snapshot: snapshot);
            }
          } else {
            // 4. Create NEW ITEM
            // No move was detected, so this is a genuinely new item.
            if (fsChild.isFolder) {
              await _handleFolderCreation(
                  rootItemId, fsChild, dbParentId, childPath, hashes, snapshot);
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
      String rootItemId,
      FSItem fsFolder,
      String fsPath,
      _FileSystemSnapshot snapshot,
      Map<String, String> hashes) async {
    final fsFingerprint = _fileSystemFolderFingerprint(
      fsPath,
      snapshot,
      hashes,
      requireMultipleEntries: false,
    );
    if (fsFingerprint == null) return null;
    final candidateDbFolders =
        await ModelItem.getAllUnScannedFolderForRootItemId(rootItemId);
    final candidates = <ReconciliationIdentityCandidate<ModelItem>>[];
    for (final candidate in candidateDbFolders) {
      final oldPath = await ModelItem.getPathForLocalItem(candidate.id);
      final dbFingerprint = await _databaseFolderFingerprint(
        candidate,
        requireMultipleEntries: candidate.name != fsFolder.name,
      );
      if (dbFingerprint != null) {
        candidates.add(ReconciliationIdentityCandidate(
          value: candidate,
          stableId: candidate.id,
          oldPath: oldPath,
          fingerprint: dbFingerprint,
        ));
      }
    }
    return selectUniqueMissingIdentity(
      candidates: candidates,
      snapshotPaths: snapshot.paths,
      targetFingerprint: fsFingerprint,
    );
  }

  // ON-DEMAND GLOBAL SEARCH: Finds a moved file. A moved file in db will not be available at its fsPath.
  Future<ModelItem?> _findMovedFile(String rootItemId, FSItem fsFile,
      String fsPath, String fsHash, _FileSystemSnapshot snapshot) async {
    // first search matching files with size
    final dbCandidatesMatchingSize =
        await ModelItem.getAllUnScannedFilesForRootItemIdMatchingSize(
            rootItemId, fsFile.size!);
    if (dbCandidatesMatchingSize.isEmpty) {
      return null;
    }
    final candidates = <ReconciliationIdentityCandidate<ModelItem>>[];
    for (final candidate in dbCandidatesMatchingSize) {
      final oldPath = await ModelItem.getPathForLocalItem(candidate.id);
      candidates.add(ReconciliationIdentityCandidate(
        value: candidate,
        stableId: candidate.id,
        oldPath: oldPath,
        fingerprint: 'file|${candidate.size}|${candidate.fileHash}',
      ));
    }
    return selectUniqueMissingIdentity(
      candidates: candidates,
      snapshotPaths: snapshot.paths,
      targetFingerprint: 'file|${fsFile.size}|$fsHash',
    );
  }

  /// Detects renamed folders by comparing children sets
  Future<bool> _handleRenamedFolder(
      String rootItemId,
      FSItem fsItem,
      List<ModelItem> dbChildren,
      String fsPath,
      Map<String, String> hashses,
      _FileSystemSnapshot snapshot) async {
    final fsFingerprint = _fileSystemFolderFingerprint(
      fsPath,
      snapshot,
      hashses,
      requireMultipleEntries: true,
    );
    if (fsFingerprint == null) return false;
    final dbChildrenFolders =
        dbChildren.where((c) => c.isFolder && c.scanState == 0).toList();
    final candidates = <ReconciliationIdentityCandidate<ModelItem>>[];

    for (final dbFolder in dbChildrenFolders) {
      final oldPath = await ModelItem.getPathForLocalItem(dbFolder.id);
      final dbFingerprint = await _databaseFolderFingerprint(
        dbFolder,
        requireMultipleEntries: true,
      );
      if (dbFingerprint != null) {
        candidates.add(ReconciliationIdentityCandidate(
          value: dbFolder,
          stableId: dbFolder.id,
          oldPath: oldPath,
          fingerprint: dbFingerprint,
        ));
      }
    }
    final bestMatch = selectUniqueMissingIdentity(
      candidates: candidates,
      snapshotPaths: snapshot.paths,
      targetFingerprint: fsFingerprint,
    );
    if (bestMatch != null) {
      bestMatch.name = fsItem.name;
      bestMatch.scanState = ScanState.modified.value;
      bestMatch.archivedAt = 0;
      await bestMatch.update(["name", "scan_state", "archived_at"]);
      // Recurse into the now-matched folder
      await _reconcileNode(
          rootItemId: rootItemId,
          dbParentId: bestMatch.id,
          fsPath: fsPath,
          hashes: hashses,
          snapshot: snapshot);
      return true;
    }
    return false;
  }

  /// Detects moved files using size, mtime, and finally hash
  Future<bool> _handleRenamedFile(
    String rootItemId,
    FSItem fsFile,
    List<ModelItem> dbChildren,
    String fsPath,
    String fsHash,
    _FileSystemSnapshot snapshot,
  ) async {
    final unmatchedDbFiles =
        dbChildren.where((c) => !c.isFolder && c.scanState == 0).toList();
    if (unmatchedDbFiles.isEmpty) return false;

    // Group DB files by size for faster lookup
    final dbFilesBySize = <int, List<ModelItem>>{};
    for (var file in unmatchedDbFiles) {
      dbFilesBySize.putIfAbsent(file.size, () => []).add(file);
    }

    final identityCandidates = <ReconciliationIdentityCandidate<ModelItem>>[];
    for (final candidate in dbFilesBySize[fsFile.size] ?? <ModelItem>[]) {
      final oldPath = await ModelItem.getPathForLocalItem(candidate.id);
      identityCandidates.add(ReconciliationIdentityCandidate(
        value: candidate,
        stableId: candidate.id,
        oldPath: oldPath,
        fingerprint: 'file|${candidate.size}|${candidate.fileHash}',
      ));
    }
    final matchedDbItem = selectUniqueMissingIdentity(
      candidates: identityCandidates,
      snapshotPaths: snapshot.paths,
      targetFingerprint: 'file|${fsFile.size}|$fsHash',
    );
    if (matchedDbItem != null) {
      matchedDbItem.name = fsFile.name;
      matchedDbItem.scanState = 2;
      matchedDbItem.archivedAt = 0;
      await matchedDbItem.update(["name", "scan_state", "archived_at"]);
      return true;
    }
    return false;
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

    await checkCreateUploadTask(dbItem.id, File(fsPath), fsHash);
    logger.info('Modified file');
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

    await checkCreateUploadTask(itemId, File(fsPath), fsHash);
    logger.info('Created file');
  }

  Future<void> _handleFolderCreation(
      String rootItemId,
      FSItem fsItem,
      String parentId,
      String fsPath,
      Map<String, String> hashses,
      _FileSystemSnapshot snapshot) async {
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
    logger.info('Created folder');

    // Recurse into the newly created folder to process its children
    await _reconcileNode(
        rootItemId: rootItemId,
        dbParentId: itemId,
        fsPath: fsPath,
        hashes: hashses,
        snapshot: snapshot);
  }

  Future<void> _handleDeletion(ModelItem item) async {
    if (item.isFolder) {
      // Only empty folders are deleted.
      await item.delete();
      logger.info('Deleted folder');
    } else {
      // Do not delete if already uploaded
      ModelFile? modelFile = await ModelFile.get(item.fileHash!);
      if (modelFile == null || modelFile.uploadedAt == 0) {
        // check if not uploading
        ModelItemTask? uploadTask = await ModelItemTask.get(item.id);
        if (uploadTask == null) {
          await item.remove();
          logger.info('Deleted file');
        }
      }
    }
  }

  // For a newly created item
  static Future<bool> isValidUploadSource(File sourceFile) async {
    if (!await sourceFile.exists()) return false;
    return await FileSystemEntity.type(
          sourceFile.path,
          followLinks: false,
        ) ==
        FileSystemEntityType.file;
  }

  Future<void> checkCreateUploadTask(
      String newItemId, File sourceFile, String hash) async {
    if (!await isValidUploadSource(sourceFile)) {
      logger.warning('Skipped upload task for invalid file source');
      return;
    }
    ModelFile? hashFile = await ModelFile.get(hash);
    bool createUploadTask = false;
    if (hashFile == null) {
      FileSplitter fileSplitter = FileSplitter(file: sourceFile);
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
  String? _fileSystemFolderFingerprint(
    String folderPath,
    _FileSystemSnapshot snapshot,
    Map<String, String> hashes, {
    required bool requireMultipleEntries,
  }) {
    final entries = <ReconciliationFingerprintEntry>[];

    void visit(String currentPath, String relativeParent) {
      for (final child in snapshot.childrenOf(currentPath)) {
        final relativePath = relativeParent.isEmpty
            ? child.name
            : path_lib.join(relativeParent, child.name);
        final childPath = path_lib.join(currentPath, child.name);
        if (child.isFolder) {
          entries.add(ReconciliationFingerprintEntry(
            relativePath: relativePath,
            isFolder: true,
            size: 0,
          ));
          visit(childPath, relativePath);
        } else {
          final hash = hashes[childPath];
          if (hash == null) continue;
          entries.add(ReconciliationFingerprintEntry(
            relativePath: relativePath,
            isFolder: false,
            size: child.size ?? 0,
            hash: hash,
          ));
        }
      }
    }

    visit(folderPath, '');
    return buildFolderFingerprint(
      entries,
      requireMultipleEntries: requireMultipleEntries,
    );
  }

  Future<String?> _databaseFolderFingerprint(
    ModelItem folder, {
    required bool requireMultipleEntries,
  }) async {
    final entries = <ReconciliationFingerprintEntry>[];
    final visited = <String>{};
    var valid = true;

    Future<void> visit(ModelItem current, String relativeParent) async {
      if (!visited.add(current.id)) {
        valid = false;
        return;
      }
      final children = await ModelItem.getAllInFolder(current);
      children.sort((a, b) {
        final nameOrder = a.name.compareTo(b.name);
        return nameOrder != 0 ? nameOrder : a.id.compareTo(b.id);
      });
      for (final child in children) {
        final relativePath = relativeParent.isEmpty
            ? child.name
            : path_lib.join(relativeParent, child.name);
        if (child.isFolder) {
          entries.add(ReconciliationFingerprintEntry(
            relativePath: relativePath,
            isFolder: true,
            size: 0,
          ));
          await visit(child, relativePath);
        } else if (child.fileHash != null) {
          entries.add(ReconciliationFingerprintEntry(
            relativePath: relativePath,
            isFolder: false,
            size: child.size,
            hash: child.fileHash,
          ));
        }
      }
    }

    await visit(folder, '');
    if (!valid) return null;
    return buildFolderFingerprint(
      entries,
      requireMultipleEntries: requireMultipleEntries,
    );
  }

  Future<_HashScanResult> _computeFileHashes(List<String> filePaths) async {
    String? fileHashKey = await getFileHashKey();
    if (fileHashKey == null) throw Exception("Failed to fetch file hash key");

    final keyBytes = base64Decode(fileHashKey);
    final secureKey = _sodium.secureCopy(keyBytes);

    try {
      final result = await _sodium.runIsolated<Map<String, dynamic>>(
        (List<SecureKey> isolatedSecureKeys, List<KeyPair> _) async {
          final isolateSecureKey = isolatedSecureKeys.first;
          final resultMap = <String, String>{};
          var complete = true;
          for (final filePath in filePaths) {
            final entity = File(filePath);
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
                final hashConsumer = _sodium.crypto.genericHash.createConsumer(
                  key: isolateSecureKey,
                  outLen: _sodium.crypto.genericHash.bytes,
                );

                final byteStream = entity.openRead().map((chunk) =>
                    chunk is Uint8List ? chunk : Uint8List.fromList(chunk));

                await byteStream.pipe(hashConsumer);
                digest = await hashConsumer.hash;
              }

              resultMap[filePath] = base64UrlEncode(digest).replaceAll('=', '');
            } catch (_) {
              complete = false;
            }
          }
          return {'hashes': resultMap, 'complete': complete};
        },
        secureKeys: [secureKey],
      );
      return _HashScanResult(
        Map<String, String>.from(result['hashes'] as Map),
        complete: result['complete'] as bool,
      );
    } finally {
      // Dispose the key on the main thread to prevent memory leaks
      secureKey.dispose();
    }
  }

  static Future<_FileSystemSnapshot> _scanFileSystemTree(
      String rootPath) async {
    final normalizedRoot = path_lib.normalize(path_lib.absolute(rootPath));
    final rootType = await FileSystemEntity.type(
      normalizedRoot,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory) {
      return _FileSystemSnapshot(
        rootPath: normalizedRoot,
        childrenByDirectory: const {},
        paths: const {},
        filePaths: const [],
        status: _SnapshotStatus.unavailable,
      );
    }

    final childrenByDirectory = <String, List<FSItem>>{};
    final paths = <String>{normalizedRoot};
    final filePaths = <String>[];
    final pendingDirectories = <String>[normalizedRoot];
    var complete = true;

    while (pendingDirectories.isNotEmpty) {
      final directoryPath = pendingDirectories.removeLast();
      final children = <FSItem>[];
      try {
        await for (final entity in Directory(directoryPath)
            .list(recursive: false, followLinks: false)) {
          try {
            final entityPath =
                path_lib.normalize(path_lib.absolute(entity.path));
            final name = path_lib.basename(entityPath);
            if (name.startsWith('.')) continue;
            final type = await FileSystemEntity.type(
              entityPath,
              followLinks: false,
            );
            if (type == FileSystemEntityType.link ||
                type == FileSystemEntityType.notFound) {
              continue;
            }
            final isFolder = type == FileSystemEntityType.directory;
            if (!isFolder && type != FileSystemEntityType.file) continue;
            final stats = await entity.stat();
            paths.add(entityPath);
            children.add(FSItem(
              name: name,
              isFolder: isFolder,
              size: isFolder ? 0 : stats.size,
            ));
            if (isFolder) {
              pendingDirectories.add(entityPath);
            } else {
              filePaths.add(entityPath);
            }
          } catch (_) {
            complete = false;
          }
        }
      } catch (_) {
        complete = false;
      }
      children.sort((a, b) {
        final nameOrder = a.name.compareTo(b.name);
        if (nameOrder != 0) return nameOrder;
        return a.isFolder == b.isFolder ? 0 : (a.isFolder ? -1 : 1);
      });
      childrenByDirectory[directoryPath] = List.unmodifiable(children);
    }

    filePaths.sort();
    return _FileSystemSnapshot(
      rootPath: normalizedRoot,
      childrenByDirectory: Map.unmodifiable(childrenByDirectory),
      paths: Set.unmodifiable(paths),
      filePaths: List.unmodifiable(filePaths),
      status: complete ? _SnapshotStatus.complete : _SnapshotStatus.partial,
    );
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
