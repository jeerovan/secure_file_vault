import 'dart:async';

class SessionInvalidated implements Exception {
  const SessionInvalidated();

  @override
  String toString() => 'The local session is no longer active';
}

class SessionRevision {
  const SessionRevision(this.id,
      {this.cleanupPending = false, this.authenticationRequired = false});

  final String id;
  final bool cleanupPending;
  final bool authenticationRequired;
}

/// A work item keeps the revision it started with, including across awaits.
/// The durable probe also detects cleanup performed by a different isolate.
class SessionWork {
  SessionWork._();

  static final _revisionKey = Object();
  static final _maintenanceKey = Object();
  static final _authenticationKey = Object();
  static SessionRevision _current = const SessionRevision('');
  static final Set<void Function()> _abortActions = {};
  static Future<SessionRevision> Function()? readRevision;

  static String get revision => _current.id;
  static bool get authenticationRequired => _current.authenticationRequired;

  static bool get _maintenance => Zone.current[_maintenanceKey] == true;

  static bool get active {
    try {
      check();
      return true;
    } on SessionInvalidated {
      return false;
    }
  }

  static void check() {
    if (_maintenance) return;
    final started = Zone.current[_revisionKey] as String?;
    if (_current.cleanupPending ||
        (_current.authenticationRequired &&
            Zone.current[_authenticationKey] != true) ||
        (started != null && started != _current.id)) {
      throw const SessionInvalidated();
    }
  }

  static Future<void> checkpoint() async {
    if (_maintenance) return;
    check();
    if (readRevision case final read?) {
      final before = _current;
      final next = await read();
      // File reads may finish out of order with another probe or cleanup.
      // Never replace a newer in-memory invalidation/completion with an older
      // snapshot merely because that snapshot's I/O finished last.
      if (_current.id != before.id ||
          _current.cleanupPending != before.cleanupPending ||
          _current.authenticationRequired != before.authenticationRequired) {
        check();
        return;
      }
      if (next.id != _current.id ||
          next.cleanupPending != _current.cleanupPending ||
          next.authenticationRequired != _current.authenticationRequired) {
        _abort();
        _current = next;
      }
    }
    check();
  }

  static Future<T> run<T>(Future<T> Function() action) async {
    if (_maintenance) return action();
    check();
    if (Zone.current[_revisionKey] != null) {
      await checkpoint();
      return action();
    }
    // Bind before the first asynchronous probe. A callback queued before
    // cleanup must not acquire the next login's revision after that await.
    return runZoned(() async {
      await checkpoint();
      return action();
    }, zoneValues: {_revisionKey: _current.id});
  }

  static void invalidate(String revision) {
    _current = SessionRevision(revision, cleanupPending: true);
    _abort();
  }

  static void _abort() {
    for (final action in _abortActions.toList()) {
      try {
        action();
      } catch (_) {
        // Continue canceling the other resources even if one close fails.
      }
    }
    _abortActions.clear();
  }

  static void Function() onInvalidated(void Function() abort) {
    check();
    _abortActions.add(abort);
    return () => _abortActions.remove(abort);
  }

  static void complete(String revision, {bool authenticationRequired = false}) {
    _current = SessionRevision(revision,
        authenticationRequired: authenticationRequired);
  }

  /// Only authentication/its public settings may run while a retained vault is
  /// locked. Cleanup and revision changes still invalidate this work normally.
  static Future<T> authenticate<T>(Future<T> Function() action) =>
      runZoned(() => run(action), zoneValues: {_authenticationKey: true});

  /// Only the cleanup coordinator may mutate storage after invalidation.
  static Future<T> maintain<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_maintenanceKey: true});

  static void resetForTesting() {
    readRevision = null;
    _current = const SessionRevision('');
    _abortActions.clear();
  }
}
