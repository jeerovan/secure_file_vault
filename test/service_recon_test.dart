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
}
