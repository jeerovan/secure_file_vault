import 'package:path/path.dart' as path_lib;

class ReconciliationFingerprintEntry {
  final String relativePath;
  final bool isFolder;
  final int size;
  final String? hash;

  const ReconciliationFingerprintEntry({
    required this.relativePath,
    required this.isFolder,
    required this.size,
    this.hash,
  });
}

String? buildFolderFingerprint(
  Iterable<ReconciliationFingerprintEntry> entries, {
  required bool requireMultipleEntries,
}) {
  final tokens = <String>[];
  var hasFile = false;
  for (final entry in entries) {
    if (entry.isFolder) {
      tokens.add('D|${entry.relativePath}');
    } else {
      if (entry.hash == null) return null;
      hasFile = true;
      tokens.add('F|${entry.relativePath}|${entry.size}|${entry.hash}');
    }
  }
  tokens.sort();
  if (!hasFile || (requireMultipleEntries && tokens.length < 2)) return null;
  return tokens.join('\n');
}

class ReconciliationIdentityCandidate<T> {
  final T value;
  final String stableId;
  final String oldPath;
  final String fingerprint;

  const ReconciliationIdentityCandidate({
    required this.value,
    required this.stableId,
    required this.oldPath,
    required this.fingerprint,
  });
}

T? selectUniqueMissingIdentity<T>({
  required Iterable<ReconciliationIdentityCandidate<T>> candidates,
  required Set<String> snapshotPaths,
  required String targetFingerprint,
}) {
  final normalizedPaths = snapshotPaths
      .map((path) => path_lib.normalize(path_lib.absolute(path)))
      .toSet();
  final matches = candidates.where((candidate) {
    final oldPath = path_lib.normalize(path_lib.absolute(candidate.oldPath));
    return candidate.fingerprint == targetFingerprint &&
        !normalizedPaths.contains(oldPath);
  }).toList()
    ..sort((a, b) => a.stableId.compareTo(b.stableId));

  return matches.length == 1 ? matches.single.value : null;
}
