import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

class ContentBasedReconciliation {
  final Database db;

  ContentBasedReconciliation(this.db);

  // Main reconciliation with hash-based tracking
  Future<ReconciliationResult> reconcileFolder(
    int folderId,
    String folderPath,
  ) async {
    final result = ReconciliationResult();

    print('Starting content-based reconciliation for: $folderPath');

    // Step 1: Scan current file system with hashes
    final currentFiles = await _scanWithHashes(folderPath);
    final currentFolders = await _scanFolders(folderPath);

    // Step 2: Load database state
    final dbFiles = await _loadDbFiles(folderId);
    final dbFolders = await _loadDbFolders(folderId);

    // Step 3: Reconcile files (hash-based)
    await _reconcileFiles(
      currentFiles,
      dbFiles,
      folderId,
      result,
    );

    // Step 4: Reconcile folders (content similarity-based)
    await _reconcileFolders(
      currentFolders,
      dbFolders,
      currentFiles,
      folderId,
      result,
    );

    return result;
  }

  // Scan file system and compute hashes for files
  Future<Map<String, FileInfo>> _scanWithHashes(String folderPath) async {
    final Map<String, FileInfo> files = {};
    final folder = Directory(folderPath);

    if (!await folder.exists()) return files;

    await for (var entity in folder.list(recursive: true)) {
      if (entity is File) {
        try {
          final stats = await entity.stat();
          final hash = await _computeFileHash(entity.path);

          files[entity.path] = FileInfo(
            path: entity.path,
            name: path.basename(entity.path),
            hash: hash,
            size: stats.size,
            modifiedTime: stats.modified.millisecondsSinceEpoch,
          );
        } catch (e) {
          print('Error scanning file ${entity.path}: $e');
        }
      }
    }

    return files;
  }

  // Scan folders separately
  Future<Map<String, FolderInfo>> _scanFolders(String rootPath) async {
    final Map<String, FolderInfo> folders = {};
    final root = Directory(rootPath);

    if (!await root.exists()) return folders;

    await for (var entity in root.list(recursive: true)) {
      if (entity is Directory) {
        try {
          // Get immediate children files (for content signature)
          final children = await _getDirectChildren(entity.path);

          folders[entity.path] = FolderInfo(
            path: entity.path,
            name: path.basename(entity.path),
            childrenHashes: children,
          );
        } catch (e) {
          print('Error scanning folder ${entity.path}: $e');
        }
      }
    }

    return folders;
  }

  // Get hashes of direct children files
  Future<Set<String>> _getDirectChildren(String folderPath) async {
    final children = <String>{};
    final folder = Directory(folderPath);

    try {
      await for (var entity in folder.list(recursive: false)) {
        if (entity is File) {
          final hash = await _computeFileHash(entity.path);
          children.add(hash);
        } else {
          children.add(path.basename(entity.path));
        }
      }
    } catch (e) {
      print('Error reading children of $folderPath: $e');
    }

    return children;
  }

  // Compute SHA-256 hash of file content
  Future<String> _computeFileHash(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      print('Error hashing file $filePath: $e');
      rethrow;
    }
  }

  // Load files from database
  Future<Map<String, FileInfo>> _loadDbFiles(int folderId) async {
    final Map<String, FileInfo> files = {};

    final rows = await db.query(
      'folder_contents',
      where: 'parent_folder_id = ? AND is_folder = ?',
      whereArgs: [folderId, 0],
    );

    for (var row in rows) {
      files[row['item_path'] as String] = FileInfo(
        path: row['item_path'] as String,
        name: row['item_name'] as String,
        hash: row['content_hash'] as String?,
        size: row['file_size'] as int? ?? 0,
        modifiedTime: row['last_modified'] as int? ?? 0,
        cloudId: row['cloud_id'] as String?,
      );
    }

    return files;
  }

  // Load folders from database
  Future<Map<String, FolderInfo>> _loadDbFolders(int folderId) async {
    final Map<String, FolderInfo> folders = {};

    final rows = await db.query(
      'folder_contents',
      where: 'parent_folder_id = ? AND is_folder = ?',
      whereArgs: [folderId, 1],
    );

    for (var row in rows) {
      final folderPath = row['item_path'] as String;

      // Get children hashes from database
      final children = await _getDbFolderChildren(folderPath, folderId);

      folders[folderPath] = FolderInfo(
        path: folderPath,
        name: row['item_name'] as String,
        childrenHashes: children,
        cloudId: row['cloud_id'] as String?,
      );
    }

    return folders;
  }

  // Get hashes of files that were in this folder
  Future<Set<String>> _getDbFolderChildren(
    String folderPath,
    int parentFolderId,
  ) async {
    final children = <String>{};

    final rows = await db.query(
      'folder_contents',
      columns: ['content_hash'],
      where: 'parent_folder_id = ? AND is_folder = 0 AND item_path LIKE ?',
      whereArgs: [parentFolderId, '$folderPath/%'],
    );

    // add folder names
    for (var row in rows) {
      final hash = row['content_hash'] as String?;
      if (hash != null && hash.isNotEmpty) {
        children.add(hash);
      }
    }

    return children;
  }

  // Reconcile files using hash-based identification
  Future<void> _reconcileFiles(
    Map<String, FileInfo> currentFiles,
    Map<String, FileInfo> dbFiles,
    int folderId,
    ReconciliationResult result,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Build hash -> FileInfo maps for quick lookup
    final currentByHash = <String, FileInfo>{};
    for (var file in currentFiles.values) {
      if (file.hash != null) {
        currentByHash[file.hash!] = file;
      }
    }

    final dbByHash = <String, FileInfo>{};
    for (var file in dbFiles.values) {
      if (file.hash != null) {
        dbByHash[file.hash!] = file;
      }
    }

    // Process current files
    for (var currentFile in currentFiles.values) {
      final hash = currentFile.hash;
      if (hash == null) continue;

      final dbFile = dbByHash[hash];

      if (dbFile == null) {
        // NEW FILE: Hash not in database
        await _handleFileCreated(currentFile, folderId, timestamp);
        result.filesCreated.add(currentFile);
      } else if (dbFile.path == currentFile.path) {
        // SAME PATH: Check if modified
        if (_isFileModified(currentFile, dbFile)) {
          await _handleFileModified(currentFile, folderId, timestamp);
          result.filesModified.add(currentFile);
        }
        // else: unchanged
      } else {
        // DIFFERENT PATH: Name change = delete old + create new
        await _handleFileDeleted(dbFile, folderId, timestamp);
        await _handleFileCreated(currentFile, folderId, timestamp);
        result.filesDeleted.add(dbFile);
        result.filesCreated.add(currentFile);
      }
    }

    // Find deleted files (in DB but not in current state)
    for (var dbFile in dbFiles.values) {
      final hash = dbFile.hash;
      if (hash == null) continue;

      if (!currentByHash.containsKey(hash)) {
        // File hash not found in current state = deleted
        await _handleFileDeleted(dbFile, folderId, timestamp);
        result.filesDeleted.add(dbFile);
      }
    }
  }

  // Check if file was modified based on modification time
  bool _isFileModified(FileInfo current, FileInfo stored) {
    // If modification time changed significantly, file was modified
    final timeDiff = (current.modifiedTime - stored.modifiedTime).abs();
    return timeDiff > 2000; // 2 second tolerance for clock skew
  }

  // Reconcile folders using content similarity (Jaccard)
  Future<void> _reconcileFolders(
    Map<String, FolderInfo> currentFolders,
    Map<String, FolderInfo> dbFolders,
    Map<String, FileInfo> currentFiles,
    int folderId,
    ReconciliationResult result,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const double similarityThreshold = 0.80; // 80% match

    final processedDbPaths = <String>{};

    // Process current folders
    for (var currentFolder in currentFolders.values) {
      final matchingDbFolder = dbFolders[currentFolder.path];

      if (matchingDbFolder != null) {
        // Folder exists at same path - no change
        processedDbPaths.add(currentFolder.path);
        continue;
      }

      // Try to find moved folder by content similarity
      FolderInfo? movedFrom;
      double maxSimilarity = 0.0;

      for (var dbFolder in dbFolders.values) {
        if (processedDbPaths.contains(dbFolder.path)) continue;

        final similarity = _calculateJaccardSimilarity(
          currentFolder.childrenHashes,
          dbFolder.childrenHashes,
        );

        if (similarity >= similarityThreshold && similarity > maxSimilarity) {
          maxSimilarity = similarity;
          movedFrom = dbFolder;
        }
      }

      if (movedFrom != null) {
        // MOVED: Folder with similar content found
        await _handleFolderMoved(
          movedFrom,
          currentFolder,
          folderId,
          timestamp,
          maxSimilarity,
        );
        result.foldersMoved.add(FolderMove(
          from: movedFrom.path,
          to: currentFolder.path,
          similarity: maxSimilarity,
        ));
        processedDbPaths.add(movedFrom.path);
      } else {
        // CREATED: New folder
        await _handleFolderCreated(currentFolder, folderId, timestamp);
        result.foldersCreated.add(currentFolder);
      }
    }

    // Find deleted folders
    for (var dbFolder in dbFolders.values) {
      if (!processedDbPaths.contains(dbFolder.path) &&
          !currentFolders.containsKey(dbFolder.path)) {
        await _handleFolderDeleted(dbFolder, folderId, timestamp);
        result.foldersDeleted.add(dbFolder);
      }
    }
  }

  // Calculate Jaccard similarity between two sets
  double _calculateJaccardSimilarity(Set<String> set1, Set<String> set2) {
    if (set1.isEmpty && set2.isEmpty) return 1.0;
    if (set1.isEmpty || set2.isEmpty) return 0.0;

    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;

    return intersection / union;
  }

  // Handle file created
  Future<void> _handleFileCreated(
    FileInfo file,
    int folderId,
    int timestamp,
  ) async {
    await db.insert(
      'folder_contents',
      {
        'parent_folder_id': folderId,
        'item_path': file.path,
        'item_name': file.name,
        'is_folder': 0,
        'content_hash': file.hash,
        'file_size': file.size,
        'last_modified': file.modifiedTime,
        'sync_status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert('sync_log', {
      'item_path': file.path,
      'operation': 'CREATE',
      'content_hash': file.hash,
      'timestamp': timestamp,
      'synced_to_cloud': 0,
    });

    print(
        '✓ File Created: ${file.path} [hash: ${file.hash?.substring(0, 8)}...]');
  }

  // Handle file modified
  Future<void> _handleFileModified(
    FileInfo file,
    int folderId,
    int timestamp,
  ) async {
    await db.update(
      'folder_contents',
      {
        'content_hash': file.hash,
        'file_size': file.size,
        'last_modified': file.modifiedTime,
        'sync_status': 'pending',
      },
      where: 'item_path = ? AND parent_folder_id = ?',
      whereArgs: [file.path, folderId],
    );

    await db.insert('sync_log', {
      'item_path': file.path,
      'operation': 'MODIFY',
      'content_hash': file.hash,
      'timestamp': timestamp,
      'synced_to_cloud': 0,
    });

    print('✓ File Modified: ${file.path}');
  }

  // Handle file deleted
  Future<void> _handleFileDeleted(
    FileInfo file,
    int folderId,
    int timestamp,
  ) async {
    if (file.cloudId != null) {
      await db.insert('sync_log', {
        'item_path': file.path,
        'operation': 'DELETE',
        'content_hash': file.hash,
        'cloud_id': file.cloudId,
        'timestamp': timestamp,
        'synced_to_cloud': 0,
      });
    }

    await db.delete(
      'folder_contents',
      where: 'item_path = ? AND parent_folder_id = ?',
      whereArgs: [file.path, folderId],
    );

    print('✓ File Deleted: ${file.path}');
  }

  // Handle folder created
  Future<void> _handleFolderCreated(
    FolderInfo folder,
    int folderId,
    int timestamp,
  ) async {
    await db.insert(
      'folder_contents',
      {
        'parent_folder_id': folderId,
        'item_path': folder.path,
        'item_name': folder.name,
        'is_folder': 1,
        'sync_status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert('sync_log', {
      'item_path': folder.path,
      'operation': 'CREATE',
      'timestamp': timestamp,
      'synced_to_cloud': 0,
    });

    print('✓ Folder Created: ${folder.path}');
  }

  // Handle folder moved
  Future<void> _handleFolderMoved(
    FolderInfo from,
    FolderInfo to,
    int folderId,
    int timestamp,
    double similarity,
  ) async {
    await db.update(
      'folder_contents',
      {
        'item_path': to.path,
        'item_name': to.name,
        'sync_status': 'pending',
      },
      where: 'item_path = ? AND parent_folder_id = ?',
      whereArgs: [from.path, folderId],
    );

    // Update all children paths
    await _updateChildrenPaths(from.path, to.path, folderId);

    await db.insert('sync_log', {
      'item_path': to.path,
      'old_path': from.path,
      'operation': 'MOVE',
      'cloud_id': from.cloudId,
      'timestamp': timestamp,
      'synced_to_cloud': 0,
    });

    print(
        '✓ Folder Moved: ${from.path} → ${to.path} (${(similarity * 100).toStringAsFixed(1)}% match)');
  }

  // Update paths of all children when folder moves
  Future<void> _updateChildrenPaths(
    String oldPath,
    String newPath,
    int folderId,
  ) async {
    final children = await db.query(
      'folder_contents',
      where: 'parent_folder_id = ? AND item_path LIKE ?',
      whereArgs: [folderId, '$oldPath/%'],
    );

    for (var child in children) {
      final oldChildPath = child['item_path'] as String;
      final newChildPath = oldChildPath.replaceFirst(oldPath, newPath);

      await db.update(
        'folder_contents',
        {'item_path': newChildPath},
        where: 'id = ?',
        whereArgs: [child['id']],
      );
    }
  }

  // Handle folder deleted
  Future<void> _handleFolderDeleted(
    FolderInfo folder,
    int folderId,
    int timestamp,
  ) async {
    if (folder.cloudId != null) {
      await db.insert('sync_log', {
        'item_path': folder.path,
        'operation': 'DELETE',
        'cloud_id': folder.cloudId,
        'timestamp': timestamp,
        'synced_to_cloud': 0,
      });
    }

    await db.delete(
      'folder_contents',
      where: 'item_path = ? AND parent_folder_id = ?',
      whereArgs: [folder.path, folderId],
    );

    print('✓ Folder Deleted: ${folder.path}');
  }
}

// Data models
class FileInfo {
  final String path;
  final String name;
  final String? hash;
  final int size;
  final int modifiedTime;
  final String? cloudId;

  FileInfo({
    required this.path,
    required this.name,
    this.hash,
    required this.size,
    required this.modifiedTime,
    this.cloudId,
  });
}

class FolderInfo {
  final String path;
  final String name;
  final Set<String> childrenHashes;
  final String? cloudId;

  FolderInfo({
    required this.path,
    required this.name,
    required this.childrenHashes,
    this.cloudId,
  });
}

class FolderMove {
  final String from;
  final String to;
  final double similarity;

  FolderMove({
    required this.from,
    required this.to,
    required this.similarity,
  });
}

class ReconciliationResult {
  final List<FileInfo> filesCreated = [];
  final List<FileInfo> filesModified = [];
  final List<FileInfo> filesDeleted = [];
  final List<FolderInfo> foldersCreated = [];
  final List<FolderInfo> foldersDeleted = [];
  final List<FolderMove> foldersMoved = [];

  int get totalChanges =>
      filesCreated.length +
      filesModified.length +
      filesDeleted.length +
      foldersCreated.length +
      foldersDeleted.length +
      foldersMoved.length;

  @override
  String toString() {
    return '''
Reconciliation Complete:
  Files: ${filesCreated.length} created, ${filesModified.length} modified, ${filesDeleted.length} deleted
  Folders: ${foldersCreated.length} created, ${foldersDeleted.length} deleted, ${foldersMoved.length} moved
  Total changes: $totalChanges
    ''';
  }
}
