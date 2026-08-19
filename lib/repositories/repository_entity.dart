import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:sqflite/sqflite.dart';

typedef RepositoryDecoder<T> = Future<T> Function(Map<String, dynamic> row);

/// Shared, typed persistence boundary for one SQLite-backed model.
class RepositoryEntity<T> {
  final String table;
  final RepositoryDecoder<T> decoder;
  final DatabaseExecutor? _database;

  RepositoryEntity({
    required this.table,
    required this.decoder,
    DatabaseExecutor? database,
  }) : _database = database;

  Future<DatabaseExecutor> get executor async =>
      _database ?? await StorageSqlite.instance.executor;

  Future<T?> get(String id) async {
    final db = await executor;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : decoder(rows.first);
  }

  Future<int> insert(Map<String, dynamic> row) async {
    final db = await executor;
    return db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> update(String id, Map<String, dynamic> row) async {
    final db = await executor;
    return db.update(table, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String id) async {
    final db = await executor;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clear() async {
    final db = await executor;
    return db.delete(table);
  }

  Future<int> upsertFromServer(
    Map<String, dynamic> row, {
    bool overwrite = false,
  }) async {
    Future<int> operation() async {
      final db = await executor;
      final id = row['id'] as String;
      final existing =
          await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
      if (existing.isEmpty) {
        return db.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final existingUpdatedAt = existing.first['updated_at'] as int? ?? 0;
      final incomingUpdatedAt = row['updated_at'] as int? ?? 0;
      if (!overwrite && incomingUpdatedAt <= existingUpdatedAt) return 0;
      return db.update(table, row, where: 'id = ?', whereArgs: [id]);
    }

    if (_database != null) return operation();
    return StorageSqlite.instance.runInTransaction(operation);
  }
}

class RepositoryItem<T> extends RepositoryEntity<T> {
  RepositoryItem({
    required super.decoder,
    super.database,
  }) : super(table: Tables.items.string);

  Future<T?> findSyncedFolder(String deviceRootId, String path) async {
    final db = await executor;
    final rows = await db.query(
      table,
      where: 'path = ? AND parent_id = ?',
      whereArgs: [path, deviceRootId],
      limit: 1,
    );
    return rows.isEmpty ? null : decoder(rows.first);
  }

  Future<List<T>> getSyncedFolders(String deviceRootId) async {
    final db = await executor;
    final rows = await db.query(
      table,
      where: 'parent_id = ?',
      whereArgs: [deviceRootId],
    );
    return Future.wait(rows.map(decoder));
  }
}

class RepositoryFile<T> extends RepositoryEntity<T> {
  RepositoryFile({
    required super.decoder,
    super.database,
  }) : super(table: Tables.files.string);
}

class RepositoryPart<T> extends RepositoryEntity<T> {
  RepositoryPart({
    required super.decoder,
    super.database,
  }) : super(table: Tables.parts.string);
}

class RepositoryTask<T> extends RepositoryEntity<T> {
  RepositoryTask({
    required super.decoder,
    super.database,
  }) : super(table: Tables.itemTasks.string);

  Future<int> recoverInterrupted({required int now}) async {
    final db = await executor;
    return db.rawUpdate(
      'UPDATE item_tasks SET state = ?, next_attempt_at = ?, '
      'last_error = ?, updated_at = ? '
      'WHERE state = ? AND next_attempt_at <= ?',
      [
        'retryWaiting',
        now,
        'process_interrupted',
        now,
        'running',
        now,
      ],
    );
  }

  Future<int> recoverTransientBlocks({required int now}) async {
    final db = await executor;
    return db.rawUpdate(
      'UPDATE item_tasks SET state = ?, next_attempt_at = ?, '
      'last_error = ?, updated_at = ? '
      'WHERE state = ? AND last_error IN (?, ?)',
      [
        'pending',
        0,
        null,
        now,
        'blocked',
        'missing_file_metadata',
        'missing_part_metadata',
      ],
    );
  }

  Future<String?> fetchPendingId(
    Set<String> activeTasks, {
    required int now,
  }) async {
    final db = await executor;
    var query = 'SELECT id FROM item_tasks WHERE '
        'state IN (?, ?) AND next_attempt_at <= ?';
    final args = <dynamic>['pending', 'retryWaiting', now];
    if (activeTasks.isNotEmpty) {
      final placeholders = List.filled(activeTasks.length, '?').join(',');
      query += ' AND id NOT IN ($placeholders)';
      args.addAll(activeTasks);
    }
    query += ' ORDER BY updated_at ASC LIMIT 1';
    final rows = await db.rawQuery(query, args);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<int?> fetchNextWakeAt() async {
    final db = await executor;
    final rows = await db.rawQuery(
      'SELECT MIN(next_attempt_at) AS next_attempt_at FROM item_tasks '
      'WHERE state IN (?, ?)',
      ['running', 'retryWaiting'],
    );
    if (rows.isEmpty) return null;
    return rows.first['next_attempt_at'] as int?;
  }
}
