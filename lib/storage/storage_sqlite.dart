import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import '../utils/enums.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/common.dart';
import '../models/model_setting.dart';
import '../services/service_logger.dart';

class StorageSqlite {
  static final StorageSqlite instance = StorageSqlite._init();
  static Database? _database;
  static Completer<Database>? _databaseCompleter;

  // Track execution mode to handle background isolate behaviors safely
  static ExecutionMode _currentMode = ExecutionMode.appForeground;

  final logger = AppLogger(prefixes: ["StorageSqlite"]);
  StorageSqlite._init();

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

  Future<Database> _initDB(String dbFileName) async {
    try {
      String dbDir = Platform.isAndroid
          ? await getDatabasesPath()
          : await getDbStoragePath();
      final dbPath = join(dbDir, dbFileName);
      logger.info("DbPath:$dbPath");

      return await openDatabase(
        dbPath,
        version: 1,
        // CRITICAL: Prevent isolate clashes. Use separate native instances in background.
        singleInstance: _currentMode == ExecutionMode.appForeground,
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

  static Future<void> initialize(
      {ExecutionMode mode = ExecutionMode.appForeground}) async {
    _currentMode = mode; // Store mode for the lazy initializer
    bool runningOnMobile = Platform.isIOS || Platform.isAndroid;

    if (!runningOnMobile) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    await instance.ensureInitialized();
    List<Map<String, dynamic>> keyValuePairs =
        await instance.getAll(Tables.settings.string);

    ModelSetting.settingJson = {
      for (var pair in keyValuePairs) pair['id']: pair['value']
    };

    AppLogger(prefixes: [mode.string]).info("Initialized SqliteDB");
  }

  Future close() async {
    // Guard: Never close the DB from a background isolate.
    // Doing so would kill the shared native connection for the foreground app.
    if (_currentMode == ExecutionMode.appBackground) {
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
    await db.execute('PRAGMA journal_mode = WAL');

    // Add a busy timeout (e.g., 5 seconds) so queries wait instead of immediately failing
    // if the other isolate temporarily holds a lock.
    await db.execute('PRAGMA busy_timeout = 5000');

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
    // await dbMigration_N(db);
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
        updated_at INTEGER
      )
    ''');
    await db.execute('''
    CREATE INDEX idx_items_file_hash ON items (file_hash)
    ''');
    bool fts5Available = await isFts5Available(db);
    if (fts5Available) {
      await db.execute('''
        CREATE VIRTUAL TABLE items_fts USING fts5(
            name,
            content='items',
            content_rowid='rowid',
            tokenize='unicode61'
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
    }
    // NOTE: else no need to create normal index on 'name' as the search term
    // will start with a "*" and B-tree does not support it
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

  Future<bool> isFts5Available(Database db) async {
    final result = await db
        .rawQuery("SELECT name FROM pragma_module_list WHERE name = 'fts5'");

    if (result.isNotEmpty) {
      return true;
    } else {
      return false;
    }
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
    String hasFts5 = await isFts5Available(db) ? "yes" : "no";
    await db.insert(Tables.settings.string,
        {"id": AppString.hasFts5.string, "value": hasFts5});
  }

  Future<int> insert(String tableName, Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(
      tableName,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> update(
      String tableName, Map<String, dynamic> row, dynamic id) async {
    final db = await instance.database;
    return await db.update(tableName, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String tableName, dynamic id) async {
    final db = await instance.database;
    return await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getWithId(
      String tableName, dynamic id) async {
    final db = await instance.database;
    return await db.query(tableName, where: "id = ?", whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final db = await instance.database;
    return await db.query(tableName);
  }

  Future<void> clearTable(String tableName) async {
    final db = await instance.database;
    await db.delete(tableName);
  }

  Future<void> clearDb() async {
    List<String> tables = [
      "files",
      "parts",
      "items",
      "changes",
      "item_tasks",
      "settings",
      "states",
      "logs"
    ];
    for (String table in tables) {
      clearTable(table);
    }
  }
}
