import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import '../utils/enums.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/common.dart';
import '../models/model_setting.dart';
import '../services/service_logger.dart';

enum SyncPageMutationType { upsertIfNewer, deleteIfNotNewer, updateExisting }

class SyncPageMutation {
  final SyncPageMutationType type;
  final String table;
  final String id;
  final Map<String, dynamic>? row;
  final int? remoteUpdatedAt;

  const SyncPageMutation.upsertIfNewer({
    required this.table,
    required this.id,
    required Map<String, dynamic> this.row,
    required int this.remoteUpdatedAt,
  }) : type = SyncPageMutationType.upsertIfNewer;

  const SyncPageMutation.deleteIfNotNewer({
    required this.table,
    required this.id,
    required int this.remoteUpdatedAt,
  })  : type = SyncPageMutationType.deleteIfNotNewer,
        row = null;

  const SyncPageMutation.updateExisting({
    required this.table,
    required this.id,
    required Map<String, dynamic> this.row,
  })  : type = SyncPageMutationType.updateExisting,
        remoteUpdatedAt = null;
}

class StorageSqlite {
  static final StorageSqlite instance = StorageSqlite._init();
  static Database? _database;
  static Completer<Database>? _databaseCompleter;
  static final Object _transactionExecutorKey = Object();

  // Track execution mode to handle background isolate behaviors safely
  static ExecutionMode _currentMode = ExecutionMode.mainApp;

  late AppLogger logger;
  StorageSqlite._init() {
    logger = AppLogger(prefixes: ["StorageSqlite", _currentMode.string]);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (_databaseCompleter != null) {
      return _databaseCompleter!.future;
    }

    _databaseCompleter = Completer<Database>();
    try {
      String dbFileName = "fife.sqlite";
      _database = await _initDB(dbFileName);
      _databaseCompleter!.complete(_database);
    } catch (e) {
      _databaseCompleter!.completeError(e);
      _databaseCompleter = null;
      rethrow;
    }
    return _databaseCompleter!.future; // Safely return the future
  }

  DatabaseExecutor? get _transactionExecutor =>
      Zone.current[_transactionExecutorKey] as DatabaseExecutor?;

  Future<DatabaseExecutor> get executor async =>
      _transactionExecutor ?? await database;

  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    if (_transactionExecutor != null) return action();
    final db = await database;
    return runInDatabaseTransaction(db, action);
  }

  static Future<T> runInDatabaseTransaction<T>(
    Database db,
    Future<T> Function() action,
  ) {
    return db.transaction(
      (txn) => runZoned(
        action,
        zoneValues: {_transactionExecutorKey: txn},
      ),
      exclusive: true,
    );
  }

  Future<Database> _initDB(String dbFileName) async {
    try {
      String dbDir = await getDbStoragePath();
      final dbPath = join(dbDir, dbFileName);
      return await openDatabase(
        dbPath,
        version: 2,
        // CRITICAL: Prevent isolate clashes. Use separate native instances in background.
        singleInstance: _currentMode == ExecutionMode.mainApp,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: _onOpen,
      );
    } catch (e, stackTrace) {
      logger.error("Failed to initialize database",
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> ensureInitialized() async {
    await database;
  }

  static Future<void> initialize(ExecutionMode mode) async {
    _currentMode = mode; // Store mode for the lazy initializer
    instance.logger = AppLogger(prefixes: ["StorageSqlite", mode.string]);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
    }
    // Force FFI on ALL platforms (Android, iOS, Desktop)
    databaseFactory = databaseFactoryFfi;

    await instance.ensureInitialized();
    List<Map<String, dynamic>> keyValuePairs =
        await instance.getAll(Tables.settings.string);

    ModelSetting.settingJson = {
      for (var pair in keyValuePairs) pair['id']: pair['value']
    };

    instance.logger.info("Initialized SqliteDB");
  }

  Future close() async {
    // Guard: Never close the DB from a background isolate.
    // Doing so would kill the shared native connection for the foreground app.
    if (_currentMode == ExecutionMode.foregroundService) {
      logger.warning(
          "Ignored close() call from background isolate to protect foreground UI.");
      return;
    }

    if (_database != null) {
      await _database!.close();
      _database = null;
      _databaseCompleter = null;
    }
  }

  Future _onConfigure(Database db) async {
    // CRITICAL: Enable WAL mode for concurrent read/write between isolates
    await db.rawQuery('PRAGMA journal_mode = WAL');

    // Add a busy timeout (e.g., 5 seconds) so queries wait instead of immediately failing
    // if the other isolate temporarily holds a lock.
    await db.rawQuery('PRAGMA busy_timeout = 5000');

    await db.execute('PRAGMA foreign_keys = ON');
    logger
        .info("onConfigure: WAL mode, busy_timeout, and Foreign keys enabled.");
  }

  Future _onOpen(Database db) async {
    List<Map<String, dynamic>> result =
        await db.rawQuery('SELECT sqlite_version()');
    String version = result.first.values.first as String;
    logger.info('Database opened, Version: $version');
  }

  Future _onCreate(Database db, int version) async {
    await initTables(db);
    logger.info('Database created with version: $version');
    await createDbEntriesOnFreshInstall(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion == 1) {
      await dbMigration_2(db);
    }
    logger.info('Database upgraded from version $oldVersion to $newVersion');
  }

  Future<void> initTables(Database db) async {
    // id: supabase id
    // email required for internal communication
    // username required for sharing files
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        username TEXT,
        image TEXT,
        plan_expires_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER
      )
    ''');
    // id : File Hash
    await db.execute('''
      CREATE TABLE files (
        id TEXT PRIMARY KEY,
        item_count INTEGER DEFAULT 0,
        parts INTEGER DEFAULT 1,
        parts_uploaded INTEGER DEFAULT 0,
        uploaded_at INTEGER DEFAULT 0,
        provider_id INTEGER,
        storage_id INTEGER,
        data TEXT,
        updated_at INTEGER
      )
    ''');
    // id : FileHash_PartNumber
    await db.execute('''
      CREATE TABLE parts (
        id TEXT PRIMARY KEY,
        size INTEGER DEFAULT 0,
        uploaded INTEGER DEFAULT 0,
        cipher TEXT,
        nonce TEXT,
        data TEXT,
        updated_at INTEGER
      )
    ''');
    // id: uuid
    // path: only for synced folders, rest will be relative to parent_id
    // name: file, folder , device (will not have path, rootId and parentId)
    // rootId: all folders and files will have item(id) of synced folder
    // size required while reconciliation for quickly find matching files
    // data: attributes on folers/path
    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        path TEXT,
        name TEXT,
        is_folder INTEGER DEFAULT 0,
        parent_id TEXT,
        root_id TEXT,
        scan_state INTEGER DEFAULT 0,
        file_hash TEXT,
        size INTEGER DEFAULT 0,
        archived_at INTEGER,
        data TEXT,
        bookmark TEXT,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
    CREATE INDEX idx_items_file_hash ON items (file_hash)
    ''');

    await db.execute('''
        CREATE VIRTUAL TABLE items_fts USING fts5(
            name,
            content='items',
            content_rowid='rowid',
            tokenize='trigram'
        );
      ''');

    await db.execute('''
        CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, name) VALUES (new.rowid, new.name);
        END;
      ''');

    await db.execute('''
        CREATE TRIGGER items_bd AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
        END;
      ''');

    // Note: BEFORE UPDATE is no longer needed. FTS5 handles both steps in AFTER UPDATE.
    await db.execute('''
        CREATE TRIGGER items_au AFTER UPDATE ON items 
        WHEN old.name IS NOT new.name
        BEGIN
          -- First, 'delete' the old index
          INSERT INTO items_fts(items_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
          -- Then, insert the new index
          INSERT INTO items_fts(rowid, name) VALUES (new.rowid, new.name);
        END;
      ''');

    await db.execute('''
      CREATE TABLE changes (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        data TEXT NOT NULL,
        updated_at INTEGER
      )
    ''');
    // id : item_id
    // task: 1(Upload), 2(Download)
    await db.execute('''
      CREATE TABLE item_tasks (
        id TEXT PRIMARY KEY,
        task INTEGER DEFAULT 0,
        progress INTEGER DEFAULT 0,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        id TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE states (
        id TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log TEXT
      )
    ''');
    logger.info("Tables Created");
  }

  Future<void> dbMigration_2(Database db) async {
    await db.execute("ALTER TABLE items ADD COLUMN bookmark TEXT");
  }

  Future<Uint8List> loadImageAsUint8List(String assetPath) async {
    ByteData data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  Future<void> createDbEntriesOnFreshInstall(Database db) async {
    // Insert app settings
    int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(Tables.settings.string,
        {"id": AppString.installedAt.string, "value": now});
  }

  Future<int> insert(String tableName, Map<String, dynamic> row) async {
    final db = await executor;
    return db.insert(
      tableName,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> update(
      String tableName, Map<String, dynamic> row, dynamic id) async {
    final db = await executor;
    return db.update(tableName, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String tableName, dynamic id) async {
    final db = await executor;
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertWithChange(
    String tableName,
    Map<String, dynamic> row,
    Map<String, dynamic>? changeRow,
  ) async {
    final current = _transactionExecutor;
    if (current != null) {
      final result = await current.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (changeRow != null) {
        await current.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    }
    final db = await instance.database;
    return insertWithChangeInDatabase(db, tableName, row, changeRow);
  }

  static Future<int> insertWithChangeInDatabase(
    Database db,
    String tableName,
    Map<String, dynamic> row,
    Map<String, dynamic>? changeRow,
  ) {
    return db.transaction((txn) async {
      final result = await txn.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (changeRow != null) {
        await txn.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    });
  }

  Future<int> updateWithChange(
    String tableName,
    Map<String, dynamic> row,
    dynamic id,
    Map<String, dynamic>? changeRow,
  ) async {
    final current = _transactionExecutor;
    if (current != null) {
      final result = await current
          .update(tableName, row, where: 'id = ?', whereArgs: [id]);
      if (changeRow != null) {
        await current.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    }
    final db = await instance.database;
    return updateWithChangeInDatabase(db, tableName, row, id, changeRow);
  }

  static Future<int> updateWithChangeInDatabase(
    Database db,
    String tableName,
    Map<String, dynamic> row,
    dynamic id,
    Map<String, dynamic>? changeRow,
  ) {
    return db.transaction((txn) async {
      final result =
          await txn.update(tableName, row, where: 'id = ?', whereArgs: [id]);
      if (changeRow != null) {
        await txn.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    });
  }

  Future<int> deleteWithChange(
    String tableName,
    dynamic id,
    Map<String, dynamic>? changeRow,
  ) async {
    final current = _transactionExecutor;
    if (current != null) {
      final result =
          await current.delete(tableName, where: 'id = ?', whereArgs: [id]);
      if (changeRow != null) {
        await current.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    }
    final db = await instance.database;
    return deleteWithChangeInDatabase(db, tableName, id, changeRow);
  }

  static Future<int> deleteWithChangeInDatabase(
    Database db,
    String tableName,
    dynamic id,
    Map<String, dynamic>? changeRow,
  ) {
    return db.transaction((txn) async {
      final result =
          await txn.delete(tableName, where: 'id = ?', whereArgs: [id]);
      if (changeRow != null) {
        await txn.insert(
          Tables.changes.string,
          changeRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return result;
    });
  }

  Future<List<Map<String, dynamic>>> getWithId(
      String tableName, dynamic id) async {
    final db = await executor;
    return db.query(tableName, where: "id = ?", whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final db = await executor;
    return db.query(tableName);
  }

  Future<void> clearTable(String tableName) async {
    final db = await executor;
    await db.delete(tableName);
  }

  Future<void> applySyncPage(
    List<SyncPageMutation> mutations,
    Map<String, int> cursors,
  ) async {
    final db = await instance.database;
    await applySyncPageInDatabase(db, mutations, cursors);
  }

  Future<bool> tryAcquireLease({
    required String key,
    required String owner,
    required int now,
    required int expiresAt,
  }) async {
    final db = await instance.database;
    return tryAcquireLeaseInDatabase(
      db,
      key: key,
      owner: owner,
      now: now,
      expiresAt: expiresAt,
    );
  }

  static Future<bool> tryAcquireLeaseInDatabase(
    Database db, {
    required String key,
    required String owner,
    required int now,
    required int expiresAt,
  }) {
    return db.transaction((txn) async {
      final rows = await txn.query(
        Tables.states.string,
        columns: ['value'],
        where: 'id = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        try {
          final current = jsonDecode(rows.single['value'] as String)
              as Map<String, dynamic>;
          final currentExpiry = current['expires_at'] as int;
          if (currentExpiry > now) return false;
        } catch (_) {
          // Malformed leases are treated as stale and safely replaced.
        }
      }
      await txn.insert(
        Tables.states.string,
        {
          'id': key,
          'value': jsonEncode({'owner': owner, 'expires_at': expiresAt}),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }, exclusive: true);
  }

  Future<bool> renewLease({
    required String key,
    required String owner,
    required int expiresAt,
  }) async {
    final db = await instance.database;
    return renewLeaseInDatabase(
      db,
      key: key,
      owner: owner,
      expiresAt: expiresAt,
    );
  }

  static Future<bool> renewLeaseInDatabase(
    Database db, {
    required String key,
    required String owner,
    required int expiresAt,
  }) {
    return db.transaction((txn) async {
      final rows = await txn.query(
        Tables.states.string,
        columns: ['value'],
        where: 'id = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final current =
          jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
      if (current['owner'] != owner) return false;
      await txn.update(
        Tables.states.string,
        {
          'value': jsonEncode({'owner': owner, 'expires_at': expiresAt})
        },
        where: 'id = ?',
        whereArgs: [key],
      );
      return true;
    }, exclusive: true);
  }

  Future<void> releaseLease({
    required String key,
    required String owner,
  }) async {
    final db = await instance.database;
    await releaseLeaseInDatabase(db, key: key, owner: owner);
  }

  static Future<void> releaseLeaseInDatabase(
    Database db, {
    required String key,
    required String owner,
  }) {
    return db.transaction((txn) async {
      final rows = await txn.query(
        Tables.states.string,
        columns: ['value'],
        where: 'id = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current =
          jsonDecode(rows.single['value'] as String) as Map<String, dynamic>;
      if (current['owner'] == owner) {
        await txn.delete(
          Tables.states.string,
          where: 'id = ?',
          whereArgs: [key],
        );
      }
    }, exclusive: true);
  }

  Future<bool> hasActiveLeasePrefix(String prefix, int now) async {
    final db = await instance.database;
    final rows = await db.query(
      Tables.states.string,
      columns: ['value'],
      where: 'id LIKE ?',
      whereArgs: ['$prefix%'],
    );
    for (final row in rows) {
      try {
        final lease =
            jsonDecode(row['value'] as String) as Map<String, dynamic>;
        if ((lease['expires_at'] as int) > now) return true;
      } catch (_) {
        // Ignore malformed/stale lease rows.
      }
    }
    return false;
  }

  static Future<void> applySyncPageInDatabase(
    Database db,
    List<SyncPageMutation> mutations,
    Map<String, int> cursors,
  ) async {
    await db.transaction((txn) async {
      for (final mutation in mutations) {
        switch (mutation.type) {
          case SyncPageMutationType.upsertIfNewer:
            final existing = await txn.query(
              mutation.table,
              columns: ['updated_at'],
              where: 'id = ?',
              whereArgs: [mutation.id],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert(
                mutation.table,
                mutation.row!,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } else {
              final existingUpdatedAt = existing.single['updated_at'] as int;
              if (mutation.remoteUpdatedAt! > existingUpdatedAt) {
                await txn.update(
                  mutation.table,
                  mutation.row!,
                  where: 'id = ?',
                  whereArgs: [mutation.id],
                );
              }
            }
          case SyncPageMutationType.deleteIfNotNewer:
            final existing = await txn.query(
              mutation.table,
              columns: ['updated_at'],
              where: 'id = ?',
              whereArgs: [mutation.id],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              final existingUpdatedAt = existing.single['updated_at'] as int;
              if (existingUpdatedAt <= mutation.remoteUpdatedAt!) {
                await txn.delete(
                  mutation.table,
                  where: 'id = ?',
                  whereArgs: [mutation.id],
                );
              }
            }
          case SyncPageMutationType.updateExisting:
            await txn.update(
              mutation.table,
              mutation.row!,
              where: 'id = ?',
              whereArgs: [mutation.id],
            );
        }
      }

      for (final cursor in cursors.entries) {
        await txn.insert(
          Tables.states.string,
          {'id': cursor.key, 'value': cursor.value.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> clearDb() async {
    final db = await instance.database;
    List<String> tables = [
      "profiles",
      "files",
      "parts",
      "items",
      "changes",
      "item_tasks",
      "settings",
      "states",
      "logs"
    ];
    await db.transaction((txn) async {
      for (String table in tables) {
        await txn.delete(table);
      }
    });
  }
}
