import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path_lib;

class DownloadManifest {
  final String itemId;
  final String fileHash;
  final int partCount;
  final int expectedPlaintextLength;
  final Set<int> completedParts;
  final Map<int, String> partChecksums;

  DownloadManifest({
    required this.itemId,
    required this.fileHash,
    required this.partCount,
    required this.expectedPlaintextLength,
    Set<int>? completedParts,
    Map<int, String>? partChecksums,
  })  : completedParts = completedParts ?? <int>{},
        partChecksums = partChecksums ?? <int, String>{};

  Map<String, dynamic> toJson() => {
        'version': 1,
        'item_id': itemId,
        'file_hash': fileHash,
        'part_count': partCount,
        'expected_plaintext_length': expectedPlaintextLength,
        'completed_parts': completedParts.toList()..sort(),
        'part_checksums': {
          for (final entry in partChecksums.entries)
            entry.key.toString(): entry.value,
        },
      };

  static DownloadManifest? fromJson(Map<String, dynamic> map) {
    if (map['version'] != 1 ||
        map['item_id'] is! String ||
        map['file_hash'] is! String ||
        map['part_count'] is! int ||
        map['expected_plaintext_length'] is! int ||
        map['completed_parts'] is! List) {
      return null;
    }
    final completed = <int>{};
    for (final value in map['completed_parts'] as List) {
      if (value is! int) return null;
      completed.add(value);
    }
    final checksums = <int, String>{};
    final rawChecksums = map['part_checksums'];
    if (rawChecksums is! Map) return null;
    for (final entry in rawChecksums.entries) {
      final part = int.tryParse(entry.key.toString());
      if (part == null || entry.value is! String) return null;
      checksums[part] = entry.value as String;
    }
    return DownloadManifest(
      itemId: map['item_id'] as String,
      fileHash: map['file_hash'] as String,
      partCount: map['part_count'] as int,
      expectedPlaintextLength: map['expected_plaintext_length'] as int,
      completedParts: completed,
      partChecksums: checksums,
    );
  }
}

class DownloadStaging {
  final Directory root;
  final String itemId;
  final String fileHash;
  final int partCount;
  final int expectedPlaintextLength;

  DownloadStaging({
    required Directory baseDirectory,
    required this.itemId,
    required this.fileHash,
    required this.partCount,
    required this.expectedPlaintextLength,
  }) : root = Directory(path_lib.join(
          baseDirectory.path,
          'downloads',
          sha256.convert(utf8.encode(itemId)).toString(),
        ));

  File get manifestFile => File(path_lib.join(root.path, 'manifest.json'));
  File get assembledFile => File(path_lib.join(root.path, 'assembled.partial'));
  File encryptedPart(int part) =>
      File(path_lib.join(root.path, 'part-$part.encrypted.partial'));
  File plainPartPartial(int part) =>
      File(path_lib.join(root.path, 'part-$part.plain.partial'));
  File readyPart(int part) =>
      File(path_lib.join(root.path, 'part-$part.plain.ready'));

  Future<DownloadManifest> load() async {
    await root.create(recursive: true);
    final backupManifest = File('${manifestFile.path}.backup');
    if (!await manifestFile.exists() && await backupManifest.exists()) {
      await backupManifest.rename(manifestFile.path);
    }
    DownloadManifest? manifest;
    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          manifest = DownloadManifest.fromJson(decoded);
        }
      } catch (_) {
        manifest = null;
      }
    }
    if (manifest == null ||
        manifest.itemId != itemId ||
        manifest.fileHash != fileHash ||
        manifest.partCount != partCount ||
        manifest.expectedPlaintextLength != expectedPlaintextLength) {
      await reset();
      manifest = DownloadManifest(
        itemId: itemId,
        fileHash: fileHash,
        partCount: partCount,
        expectedPlaintextLength: expectedPlaintextLength,
      );
      await save(manifest);
      return manifest;
    }

    final invalidParts = <int>[];
    for (final part in manifest.completedParts) {
      final ready = readyPart(part);
      final expectedChecksum = manifest.partChecksums[part];
      if (part < 1 ||
          part > partCount ||
          !await ready.exists() ||
          expectedChecksum == null ||
          await _sha256ForFile(ready) != expectedChecksum) {
        invalidParts.add(part);
      }
    }
    manifest.completedParts.removeAll(invalidParts);
    for (final part in invalidParts) {
      manifest.partChecksums.remove(part);
    }
    await save(manifest);
    return manifest;
  }

  Future<void> save(DownloadManifest manifest) async {
    await root.create(recursive: true);
    final temporary = File('${manifestFile.path}.partial');
    final backup = File('${manifestFile.path}.backup');
    await temporary.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await manifestFile.exists()) await manifestFile.rename(backup.path);
    try {
      await temporary.rename(manifestFile.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await manifestFile.exists() && await backup.exists()) {
        await backup.rename(manifestFile.path);
      }
      rethrow;
    }
  }

  Future<void> markComplete(DownloadManifest manifest, int part) async {
    if (part < 1 || part > partCount || !await readyPart(part).exists()) {
      throw StateError('Cannot complete missing download part $part');
    }
    manifest.completedParts.add(part);
    manifest.partChecksums[part] = await _sha256ForFile(readyPart(part));
    await save(manifest);
  }

  Future<void> assemble() async {
    final sink = assembledFile.openWrite(mode: FileMode.write);
    try {
      for (var part = 1; part <= partCount; part++) {
        final source = readyPart(part);
        if (!await source.exists()) {
          throw StateError('Missing download part $part');
        }
        await sink.addStream(source.openRead());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<void> reset() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }

  Future<void> cleanup() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  static Future<String> _sha256ForFile(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }
}
