import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE items ('
      'id TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE changes ('
      'id TEXT PRIMARY KEY, table_name TEXT NOT NULL, data TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE states (id TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  });

  tearDown(() => db.close());

  test('insert and journal roll back together', () async {
    await expectLater(
      StorageSqlite.insertWithChangeInDatabase(
        db,
        'items',
        {'id': 'item-1', 'value': 'new', 'updated_at': 20},
        {'id': 'change-1', 'table_name': 'items'},
      ),
      throwsA(anything),
    );

    expect(await db.query('items'), isEmpty);
  });

  test('update and journal roll back together', () async {
    await db
        .insert('items', {'id': 'item-1', 'value': 'old', 'updated_at': 10});

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
    await db
        .insert('items', {'id': 'item-1', 'value': 'old', 'updated_at': 10});

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

  test('sync page commits mutations and cursors together', () async {
    await db
        .insert('items', {'id': 'item-1', 'value': 'old', 'updated_at': 10});

    await StorageSqlite.applySyncPageInDatabase(
      db,
      const [
        SyncPageMutation.upsertIfNewer(
          table: 'items',
          id: 'item-1',
          row: {'id': 'item-1', 'value': 'new', 'updated_at': 20},
          remoteUpdatedAt: 20,
        ),
      ],
      const {'last_item_ts': 20},
    );

    expect((await db.query('items')).single['value'], 'new');
    expect((await db.query('states')).single['value'], '20');
  });

  test('sync page failure rolls back mutations and cursors', () async {
    await db
        .insert('items', {'id': 'item-1', 'value': 'old', 'updated_at': 10});

    await expectLater(
      StorageSqlite.applySyncPageInDatabase(
        db,
        const [
          SyncPageMutation.upsertIfNewer(
            table: 'items',
            id: 'item-1',
            row: {'id': 'item-1', 'value': 'new', 'updated_at': 20},
            remoteUpdatedAt: 20,
          ),
          SyncPageMutation.updateExisting(
            table: 'missing_table',
            id: 'bad-record',
            row: {'value': 'invalid'},
          ),
        ],
        const {'last_item_ts': 20},
      ),
      throwsA(anything),
    );

    expect((await db.query('items')).single['value'], 'old');
    expect(await db.query('states'), isEmpty);
  });
}
