import 'package:file_vault_bb/services/service_reconciliation_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = ReconciliationIdentityCandidate<String>(
    value: 'original-id',
    stableId: 'original-id',
    oldPath: '/vault/original.txt',
    fingerprint: 'file|10|same-hash',
  );

  test('copy cannot steal identity while original path exists', () {
    final match = selectUniqueMissingIdentity(
      candidates: const [original],
      snapshotPaths: {'/vault/original.txt', '/vault/copy.txt'},
      targetFingerprint: 'file|10|same-hash',
    );

    expect(match, isNull);
  });

  test('rename can retain identity only after old path disappears', () {
    final match = selectUniqueMissingIdentity(
      candidates: const [original],
      snapshotPaths: {'/vault/renamed.txt'},
      targetFingerprint: 'file|10|same-hash',
    );

    expect(match, 'original-id');
  });

  test('ambiguous missing candidates are rejected', () {
    final match = selectUniqueMissingIdentity(
      candidates: const [
        original,
        ReconciliationIdentityCandidate<String>(
          value: 'other-id',
          stableId: 'other-id',
          oldPath: '/vault/other.txt',
          fingerprint: 'file|10|same-hash',
        ),
      ],
      snapshotPaths: {'/vault/new.txt'},
      targetFingerprint: 'file|10|same-hash',
    );

    expect(match, isNull);
  });

  test('same-size different-content candidate is rejected', () {
    final match = selectUniqueMissingIdentity(
      candidates: const [original],
      snapshotPaths: {'/vault/new.txt'},
      targetFingerprint: 'file|10|different-hash',
    );

    expect(match, isNull);
  });

  test('folder fingerprint is deterministic and structure-sensitive', () {
    const file = ReconciliationFingerprintEntry(
      relativePath: 'nested/file.txt',
      isFolder: false,
      size: 10,
      hash: 'hash-a',
    );
    const folder = ReconciliationFingerprintEntry(
      relativePath: 'nested',
      isFolder: true,
      size: 0,
    );

    final first = buildFolderFingerprint(
      const [folder, file],
      requireMultipleEntries: true,
    );
    final reordered = buildFolderFingerprint(
      const [file, folder],
      requireMultipleEntries: true,
    );
    final changed = buildFolderFingerprint(
      const [
        folder,
        ReconciliationFingerprintEntry(
          relativePath: 'nested/file.txt',
          isFolder: false,
          size: 10,
          hash: 'hash-b',
        ),
      ],
      requireMultipleEntries: true,
    );

    expect(first, reordered);
    expect(changed, isNot(first));
  });

  test('low-information folder cannot authorize rename', () {
    final fingerprint = buildFolderFingerprint(
      const [
        ReconciliationFingerprintEntry(
          relativePath: 'only-file.txt',
          isFolder: false,
          size: 10,
          hash: 'hash-a',
        ),
      ],
      requireMultipleEntries: true,
    );

    expect(fingerprint, isNull);
  });
}
