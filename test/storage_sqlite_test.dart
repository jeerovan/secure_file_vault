import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE items (id TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE changes ('
      'id TEXT PRIMARY KEY, table_name TEXT NOT NULL, data TEXT NOT NULL)',
    );
  });

  tearDown(() => db.close());

  test('insert and journal roll back together', () async {
    await expectLater(
      StorageSqlite.insertWithChangeInDatabase(
        db,
        'items',
        {'id': 'item-1', 'value': 'new'},
        {'id': 'change-1', 'table_name': 'items'},
      ),
      throwsA(anything),
    );

    expect(await db.query('items'), isEmpty);
  });

  test('update and journal roll back together', () async {
    await db.insert('items', {'id': 'item-1', 'value': 'old'});

    await expectLater(
      StorageSqlite.updateWithChangeInDatabase(
        db,
        'items',
        {'value': 'new'},
        'item-1',
        {'id': 'change-1', 'table_name': 'items'},
      ),
      throwsA(anything),
    );

    final rows = await db.query('items');
    expect(rows.single['value'], 'old');
  });

  test('delete and journal roll back together', () async {
    await db.insert('items', {'id': 'item-1', 'value': 'old'});

    await expectLater(
      StorageSqlite.deleteWithChangeInDatabase(
        db,
        'items',
        'item-1',
        {'id': 'change-1', 'table_name': 'items'},
      ),
      throwsA(anything),
    );

    expect(await db.query('items'), hasLength(1));
  });
}
