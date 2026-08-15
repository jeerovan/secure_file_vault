import 'dart:io';

import 'package:file_vault_bb/services/service_recon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upload source accepts files and rejects directories', () async {
    final directory = await Directory.systemTemp.createTemp('fife-recon-');
    addTearDown(() => directory.delete(recursive: true));
    final childFile = File('${directory.path}/child.txt');
    await childFile.writeAsString('content');

    expect(
      await ReconciliationService.isValidUploadSource(childFile),
      isTrue,
    );
    expect(
      await ReconciliationService.isValidUploadSource(File(directory.path)),
      isFalse,
    );
    expect(
      await ReconciliationService.isValidUploadSource(
        File('${directory.path}/missing.txt'),
      ),
      isFalse,
    );
  });

  test('filesystem snapshot preserves exact names and prunes hidden trees',
      () async {
    final directory = await Directory.systemTemp.createTemp('fife-scan-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/ leading and trailing .txt ')
        .writeAsString('visible');
    final hidden = await Directory('${directory.path}/.hidden').create();
    await File('${hidden.path}/leak.txt').writeAsString('hidden');

    final inspection =
        await ReconciliationService.inspectSource(directory.path);

    expect(inspection.status, ReconciliationStatus.completed);
    expect(inspection.relativePaths, contains(' leading and trailing .txt '));
    expect(inspection.relativePaths, isNot(contains('.hidden')));
    expect(inspection.relativePaths, isNot(contains('.hidden/leak.txt')));
  }, skip: Platform.isWindows);

  test('missing root is unavailable, not an empty complete scan', () async {
    final directory = await Directory.systemTemp.createTemp('fife-missing-');
    final missingPath = directory.path;
    await directory.delete();

    final inspection = await ReconciliationService.inspectSource(missingPath);

    expect(inspection.status, ReconciliationStatus.unavailable);
    expect(inspection.relativePaths, isEmpty);
  });
}
