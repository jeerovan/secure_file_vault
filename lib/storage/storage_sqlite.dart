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
  final logger = AppLogger(prefixes: ["StorageSqlite"]);
  StorageSqlite._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_databaseCompleter != null) return _databaseCompleter!.future;
    _databaseCompleter = Completer();
    try {
      String dbFileName = "fife.sqlite";
      _database = await _initDB(dbFileName);
      _databaseCompleter!.complete(_database);
    } catch (e) {
      _databaseCompleter!.completeError(e);
      _databaseCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDB(String dbFileName) async {
    try {
      String dbDir = Platform.isAndroid
          ? await getDatabasesPath()
          : await getDbStoragePath();
      final dbPath = join(dbDir, dbFileName);
      logger.info("DbPath:$dbPath");
      return await openDatabase(dbPath,
          version: 13,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onOpen: _onOpen);
    } catch (e, stackTrace) {
      logger.error("Failed to initialize database",
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> ensureInitialized() async {
    await database; // Forces lazy initialization if not already done
  }

  static Future<void> initialize(
      {ExecutionMode mode = ExecutionMode.appForeground}) async {
    bool runningOnMobile = Platform.isIOS || Platform.isAndroid;
    if (!runningOnMobile) {
      // Initialize sqflite for FFI (non-mobile platforms)
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
    final db = await instance.database;
    await db.close();
    _database = null;
    _databaseCompleter = null;
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    logger.info("onConfigure:Foreign keys enabled.");
  }

  Future _onOpen(Database db) async {
    List<Map<String, dynamic>> result =
        await db.rawQuery('SELECT sqlite_version()');
    String version = result.first.values.first;
    logger.info('Database opened, Version: $version');
  }

  Future _onCreate(Database db, int version) async {
    await initTables(db);
    logger.info('Database created with version: $version');
    int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(Tables.settings.string,
        {"id": AppString.installedAt.string, "value": now});
    await createDbEntriesOnFreshInstall(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    //await dbMigration_N(db);
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
        storage_id TEXT,
        provider INTEGER DEFAULT 0,
        remote_id TEXT,
        access_token TEXT,
        token_expiry INTEGER DEFAULT 0,
        updated_at INTEGER
      )
    ''');
    // id : FileId_PartNumber
    //state:
    await db.execute('''
      CREATE TABLE parts (
        id TEXT PRIMARY KEY,
        file_id TEXT NOT NULL,
        sha1 TEXT,
        part_number INTEGER NOT NULL,
        size INTEGER DEFAULT 0,
        state INTEGER DEFAULT 0,
        cipher TEXT NOT NULL,
        nonce TEXT NOT NULL,
        updated_at INTEGER,
        FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
      )
    ''');
    // id: uuid
    // path: only for synced folders, rest will be relative to parent_id
    // name: file, folder , device (will not have path, rootId and parentId)
    // rootId: all folders and files will have item(id) of synced folder
    // size required while reconciliation for quickly find matching files
    await db.execute('''
      CREATE TABLE items (
        id TEXT PRIMARY KEY,
        path TEXT,
        name TEXT,
        is_folder INTEGER DEFAULT 0,
        parent_id TEXT,
        root_id TEXT,
        scan_state INTEGER DEFAULT 0,
        file_id TEXT,
        size INTEGER DEFAULT 0,
        archived_at INTEGER,
        updated_at INTEGER,
        FOREIGN KEY (parent_id) REFERENCES items(id) ON DELETE CASCADE,
        FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
        CREATE VIRTUAL TABLE items_fts USING fts4(
            content="items",
            name, 
            tokenize=unicode61
        );
    ''');
    await db.execute('''
    CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
      INSERT INTO items_fts(rowid, name) VALUES (new.rowid, new.name);
    END;
  ''');
    await db.execute('''
      CREATE TRIGGER items_bd BEFORE DELETE ON items BEGIN
        DELETE FROM items_fts WHERE docid = old.rowid;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER items_bu BEFORE UPDATE ON items 
      WHEN old.name IS NOT new.name
      BEGIN
        DELETE FROM items_fts WHERE docid = old.rowid;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER items_au AFTER UPDATE ON items 
      WHEN old.name IS NOT new.name
      BEGIN
        INSERT INTO items_fts(docid, name) VALUES (new.rowid, new.name);
      END;
    ''');
    await db.execute('''
      CREATE TABLE changes (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        changed_data TEXT NOT NULL,
        change_type INTEGER NOT NULL,
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

  Future<Uint8List> loadImageAsUint8List(String assetPath) async {
    ByteData data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  Future<void> createDbEntriesOnFreshInstall(Database db) async {
    /* int createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    Uuid uuid = const Uuid();
    String uniqueId = uuid.v4(); */
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

  Future<void> clear(String tableName) async {
    final db = await instance.database;
    await db.delete(tableName);
  }
}
