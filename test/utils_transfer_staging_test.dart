import 'dart:io';

import 'package:file_vault_bb/utils/utils_transfer_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('fife-stage-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('same-basename items receive isolated staging roots', () async {
    final first = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'item-a',
      fileHash: 'hash-a',
      partCount: 1,
      expectedPlaintextLength: 1,
    );
    final second = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'item-b',
      fileHash: 'hash-b',
      partCount: 1,
      expectedPlaintextLength: 1,
    );

    expect(first.root.path, isNot(second.root.path));
  });

  test('manifest resumes only parts with committed ready files', () async {
    final staging = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'item',
      fileHash: 'hash',
      partCount: 2,
      expectedPlaintextLength: 11,
    );
    final manifest = await staging.load();
    await staging.readyPart(1).writeAsString('first');
    await staging.markComplete(manifest, 1);

    final resumed = await staging.load();
    expect(resumed.completedParts, {1});

    await staging.readyPart(1).delete();
    final repaired = await staging.load();
    expect(repaired.completedParts, isEmpty);
  });

  test('assembly writes ready parts in deterministic order', () async {
    final staging = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'item',
      fileHash: 'hash',
      partCount: 2,
      expectedPlaintextLength: 11,
    );
    await staging.load();
    await staging.readyPart(1).writeAsString('hello ');
    await staging.readyPart(2).writeAsString('world');

    await staging.assemble();

    expect(await staging.assembledFile.readAsString(), 'hello world');
  });

  test('every committed part boundary survives restart', () async {
    for (var boundary = 0; boundary <= 3; boundary++) {
      final staging = DownloadStaging(
        baseDirectory: temporaryDirectory,
        itemId: 'item-$boundary',
        fileHash: 'hash-$boundary',
        partCount: 3,
        expectedPlaintextLength: 3,
      );
      final manifest = await staging.load();
      for (var part = 1; part <= boundary; part++) {
        await staging.readyPart(part).writeAsString('$part');
        await staging.markComplete(manifest, part);
      }

      final resumed = await staging.load();

      expect(resumed.completedParts, {
        for (var part = 1; part <= boundary; part++) part,
      });
    }
  });

  test('partial plaintext without manifest commit is never resumed', () async {
    final staging = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'partial-item',
      fileHash: 'partial-hash',
      partCount: 1,
      expectedPlaintextLength: 4,
    );
    await staging.load();
    await staging.plainPartPartial(1).writeAsString('x');

    final resumed = await staging.load();

    expect(resumed.completedParts, isEmpty);
  });

  test('corrupted ready part is removed from resume manifest', () async {
    final staging = DownloadStaging(
      baseDirectory: temporaryDirectory,
      itemId: 'corrupt-item',
      fileHash: 'corrupt-hash',
      partCount: 1,
      expectedPlaintextLength: 4,
    );
    final manifest = await staging.load();
    await staging.readyPart(1).writeAsString('good');
    await staging.markComplete(manifest, 1);
    await staging.readyPart(1).writeAsString('evil');

    final resumed = await staging.load();

    expect(resumed.completedParts, isEmpty);
  });

  test('staging write failure cannot commit a manifest', () async {
    final blocker = File('${temporaryDirectory.path}/not-a-directory');
    await blocker.writeAsString('blocked');
    final staging = DownloadStaging(
      baseDirectory: Directory(blocker.path),
      itemId: 'item',
      fileHash: 'hash',
      partCount: 1,
      expectedPlaintextLength: 1,
    );

    await expectLater(staging.load(), throwsA(isA<FileSystemException>()));
    expect(await staging.manifestFile.exists(), isFalse);
  });
}
