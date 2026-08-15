import 'dart:async';

import 'package:uuid/uuid.dart';

import '../storage/storage_sqlite.dart';

class OperationLease {
  final String operationId;
  final String owner;
  final String _key;
  Timer? _heartbeat;
  bool _valid = true;

  OperationLease._({
    required this.operationId,
    required this.owner,
    required String key,
  }) : _key = key;

  bool get isValid => _valid;

  Future<bool> prepareForCommit() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      _valid = await StorageSqlite.instance.renewLease(
        key: _key,
        owner: owner,
        expiresAt: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .millisecondsSinceEpoch,
      );
    } catch (_) {
      _valid = false;
    }
    return _valid;
  }

  void _startHeartbeat() {
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final renewed = await StorageSqlite.instance.renewLease(
          key: _key,
          owner: owner,
          expiresAt: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
        );
        if (!renewed) _valid = false;
      } catch (_) {
        _valid = false;
      }
    });
  }

  Future<void> release() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      await StorageSqlite.instance.releaseLease(key: _key, owner: owner);
    } finally {
      _valid = false;
      ExclusiveOperationCoordinator._activeOperations.remove(operationId);
    }
  }
}

class ExclusiveOperationCoordinator {
  static final Set<String> _activeOperations = <String>{};
  static const _uuid = Uuid();

  static Future<OperationLease?> tryAcquire(String operationId) async {
    if (!_activeOperations.add(operationId)) return null;

    final owner = _uuid.v4();
    final key = 'operation_lease:$operationId';
    final now = DateTime.now().toUtc();
    try {
      final acquired = await StorageSqlite.instance.tryAcquireLease(
        key: key,
        owner: owner,
        now: now.millisecondsSinceEpoch,
        expiresAt: now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      );
      if (!acquired) {
        _activeOperations.remove(operationId);
        return null;
      }
      final lease = OperationLease._(
        operationId: operationId,
        owner: owner,
        key: key,
      );
      lease._startHeartbeat();
      return lease;
    } catch (_) {
      _activeOperations.remove(operationId);
      rethrow;
    }
  }
}

class ReconciliationCoordinator {
  static Future<OperationLease?> tryAcquire(String rootId) =>
      ExclusiveOperationCoordinator.tryAcquire('reconciliation:$rootId');
}
