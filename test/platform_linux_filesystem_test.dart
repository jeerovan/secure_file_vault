import 'dart:io';

import 'package:file_vault_bb/services/service_recon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Linux scan preserves exact distinct names and prunes links and hidden trees',
    () async {
      final root = await Directory.systemTemp.createTemp('fife-linux-scan-');
      try {
        const expectedNames = <String>{
          ' leading.txt',
          'trailing.txt ',
          'Case.txt',
          'case.txt',
          '\u00e9.txt',
          'e\u0301.txt',
        };
        for (final name in expectedNames) {
          await File('${root.path}/$name').writeAsString(name);
        }
        final hidden = Directory('${root.path}/.hidden')..createSync();
        await File('${hidden.path}/secret.txt').writeAsString('hidden');
        await Link('${root.path}/linked.txt')
            .create('${root.path}/Case.txt', recursive: false);

        final first = await ReconciliationService.inspectSource(root.path);
        final second = await ReconciliationService.inspectSource(root.path);

        expect(first.status, ReconciliationStatus.completed);
        expect(first.relativePaths.toSet(), expectedNames);
        expect(second.relativePaths, first.relativePaths);
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux,
  );
}
