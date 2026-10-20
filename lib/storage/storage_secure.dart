import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/service_session_work.dart';
import 'storage_sqlite.dart';

class SecureStorage {
  // Singleton instance
  static final SecureStorage _instance = SecureStorage._internal();

  // Factory constructor to return the singleton instance
  factory SecureStorage() {
    return _instance;
  }

  // Private constructor
  SecureStorage._internal();

  // FlutterSecureStorage instance
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  // CRUD Methods

  /// Write a key-value pair securely
  Future<void> write({required String key, required String value}) async {
    await _mutate(() => _storage.write(key: key, value: value));
  }

  /// Read a value by key
  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }

  Future<bool> containsKey({required String key}) async {
    return await _storage.containsKey(key: key);
  }

  /// Delete a value by key
  Future<void> delete({required String key}) async {
    await _mutate(() => _storage.delete(key: key));
  }

  Future<void> clear() async {
    await _mutate(_storage.deleteAll);
  }

  /// Retained reset staging/session keys stay in place through interruption.
  Future<void> clearExcept(Set<String> retained) async {
    await _mutate(() async {
      final values = await _storage.readAll();
      for (final key in values.keys) {
        if (!retained.contains(key)) await _storage.delete(key: key);
      }
      if ((await _storage.readAll())
          .keys
          .any((key) => !retained.contains(key))) {
        throw StateError('Private storage cleanup is incomplete');
      }
    });
  }

  Future<void> _mutate(Future<void> Function() action) async {
    // Once the application configures durable sessions, serialize platform
    // key-store writes with cleanup. A platform write already in flight must
    // finish before deleteAll, so it cannot resurrect a retired key afterward.
    if (SessionWork.readRevision == null) return action();
    await StorageSqlite.instance.runInTransaction(() async {
      await SessionWork.checkpoint();
      await action();
      await SessionWork.checkpoint();
    });
  }
}
