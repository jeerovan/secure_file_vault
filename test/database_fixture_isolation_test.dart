import 'dart:io';

import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/temporary_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit fixture database stays isolated across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('fife-isolation-');
    addTearDown(() async {
      await StorageSqlite.instance.close();
      // Windows' suite wrapper owns its process-wide safe fallback.
      if (!Platform.isWindows) {
        StorageSqlite.setDatabaseDirectoryForTesting(null);
      }
      await deleteTestDirectory(directory);
    });
    StorageSqlite.setDatabaseDirectoryForTesting(directory.path);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final database = await StorageSqlite.instance.database;
    expect(path.equals(database.path, path.join(directory.path, 'fife.sqlite')),
        isTrue);
    await database
        .insert('settings', {'id': 'fixture-marker', 'value': 'kept'});
    expect(() => StorageSqlite.setDatabaseDirectoryForTesting(null),
        throwsStateError);
    await StorageSqlite.instance.close();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final reopened = await StorageSqlite.instance.database;
    expect(
        (await reopened.query('settings',
                where: 'id = ?', whereArgs: ['fixture-marker']))
            .single['value'],
        'kept');
    expect(path.equals(reopened.path, database.path), isTrue);
  });
}
