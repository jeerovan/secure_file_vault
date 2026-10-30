import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/temporary_directory.dart';

/// Windows' production DB location comes directly from APPDATA, not the mocked
/// path_provider channel. Isolate every host test, including old fixtures that
/// predate Windows execution. This file is not used by the product/native app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isWindows) {
    final bootstrap =
        await Directory.systemTemp.createTemp('fife-test-bootstrap-');
    StorageSqlite.setDatabaseDirectoryForTesting(bootstrap.path);
    tearDownAll(() async {
      await StorageSqlite.instance.close();
      await deleteTestDirectory(bootstrap);
    });
    Directory? databaseDirectory;
    setUp(() async {
      databaseDirectory =
          await Directory.systemTemp.createTemp('fife-test-db-');
      StorageSqlite.setDatabaseDirectoryForTesting(databaseDirectory!.path);
    });
    tearDown(() async {
      await StorageSqlite.instance.close();
      // A late fixture callback must remain isolated between tests too. Never
      // restore the production APPDATA path anywhere in this test process.
      StorageSqlite.setDatabaseDirectoryForTesting(bootstrap.path);
      if (databaseDirectory != null) {
        await deleteTestDirectory(databaseDirectory!);
      }
    });
  }
  await testMain();
}
