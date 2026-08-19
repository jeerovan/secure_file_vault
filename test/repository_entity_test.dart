import 'package:file_vault_bb/repositories/repository_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Map<String, dynamic>> _decode(Map<String, dynamic> row) async =>
    Map<String, dynamic>.from(row);

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE items ('
      'id TEXT PRIMARY KEY, path TEXT, parent_id TEXT, updated_at INTEGER)',
    );
    await db.execute(
      'CREATE TABLE files ('
      'id TEXT PRIMARY KEY, value TEXT, updated_at INTEGER)',
    );
    await db.execute(
      'CREATE TABLE parts ('
      'id TEXT PRIMARY KEY, value TEXT, updated_at INTEGER)',
    );
    await db.execute(
      'CREATE TABLE item_tasks ('
      'id TEXT PRIMARY KEY, state TEXT, next_attempt_at INTEGER, '
      'last_error TEXT, updated_at INTEGER)',
    );
  });

  tearDown(() => db.close());

  test('item repository scopes synced folders to one device root', () async {
    final repository = RepositoryItem<Map<String, dynamic>>(
      decoder: _decode,
      database: db,
    );
    await repository.insert({
      'id': 'local',
      'path': '/local',
      'parent_id': 'device-a',
      'updated_at': 1,
    });
    await repository.insert({
      'id': 'other',
      'path': '/local',
      'parent_id': 'device-b',
      'updated_at': 1,
    });
    await repository.insert({
      'id': 'root-child-without-path',
      'path': null,
      'parent_id': 'device-a',
      'updated_at': 1,
    });

    final match = await repository.findSyncedFolder('device-a', '/local');
    final folders = await repository.getSyncedFolders('device-a');

    expect(match?['id'], 'local');
    expect(folders.map((row) => row['id']),
        containsAll(['local', 'root-child-without-path']));
    expect(folders.map((row) => row['id']), isNot(contains('other')));
  });

  test('file repository ignores stale server rows', () async {
    final repository = RepositoryFile<Map<String, dynamic>>(
      decoder: _decode,
      database: db,
    );
    await repository.insert({'id': 'file', 'value': 'local', 'updated_at': 20});

    final result = await repository.upsertFromServer(
      {'id': 'file', 'value': 'stale', 'updated_at': 10},
    );

    expect(result, 0);
    expect((await repository.get('file'))?['value'], 'local');
  });

  test('part repository permits explicit authoritative overwrite', () async {
    final repository = RepositoryPart<Map<String, dynamic>>(
      decoder: _decode,
      database: db,
    );
    await repository.insert({'id': 'part', 'value': 'local', 'updated_at': 20});

    await repository.upsertFromServer(
      {'id': 'part', 'value': 'server', 'updated_at': 10},
      overwrite: true,
    );

    expect((await repository.get('part'))?['value'], 'server');
  });

  test('task repository recovers expired work and skips active IDs', () async {
    final repository = RepositoryTask<Map<String, dynamic>>(
      decoder: _decode,
      database: db,
    );
    await repository.insert({
      'id': 'active',
      'state': 'pending',
      'next_attempt_at': 0,
      'updated_at': 1,
    });
    await repository.insert({
      'id': 'next',
      'state': 'pending',
      'next_attempt_at': 0,
      'updated_at': 2,
    });
    await repository.insert({
      'id': 'interrupted',
      'state': 'running',
      'next_attempt_at': 5,
      'updated_at': 3,
    });
    await repository.insert({
      'id': 'later-retry',
      'state': 'retryWaiting',
      'next_attempt_at': 20,
      'updated_at': 4,
    });
    await repository.insert({
      'id': 'metadata-blocked',
      'state': 'blocked',
      'next_attempt_at': 0,
      'last_error': 'missing_part_metadata',
      'updated_at': 5,
    });
    await repository.insert({
      'id': 'file-metadata-blocked',
      'state': 'blocked',
      'next_attempt_at': 0,
      'last_error': 'missing_file_metadata',
      'updated_at': 6,
    });
    await repository.insert({
      'id': 'storage-blocked',
      'state': 'blocked',
      'next_attempt_at': 0,
      'last_error': 'storage_full',
      'updated_at': 7,
    });

    expect(await repository.fetchPendingId({'active'}, now: 10), 'next');
    expect(await repository.fetchNextWakeAt(), 5);
    expect(await repository.recoverInterrupted(now: 10), 1);
    final interrupted = await repository.get('interrupted');
    expect(interrupted?['state'], 'retryWaiting');
    expect(interrupted?['last_error'], 'process_interrupted');
    expect(await repository.recoverTransientBlocks(now: 11), 2);
    final metadataBlocked = await repository.get('metadata-blocked');
    expect(metadataBlocked?['state'], 'pending');
    expect(metadataBlocked?['next_attempt_at'], 0);
    expect(metadataBlocked?['last_error'], isNull);
    expect(
        (await repository.get('file-metadata-blocked'))?['state'], 'pending');
    expect((await repository.get('storage-blocked'))?['state'], 'blocked');
  });
}
